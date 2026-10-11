import SwiftUI
import XCTest
@testable import RichText

final class SubmittedTextTests: XCTestCase {
    @MainActor
    private func makeView() -> InlineAttachmentTextView {
        let view = InlineAttachmentTextView(usingTextLayoutManager: false)
        view.isEditable = false
        return view
    }

    @MainActor
    private func input(_ text: String, size: CGFloat = 18, spacing: CGFloat = 12,
                       color: PlatformColor = .red, link: String = "https://example.com/a") -> AttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 31
        paragraph.paragraphSpacing = spacing
        var result = AttributedString(text)
        #if canImport(AppKit)
        result.appKit.font = NSFont.systemFont(ofSize: size)
        result.appKit.paragraphStyle = paragraph
        result.appKit.foregroundColor = color
        #else
        result.uiKit.font = UIFont.systemFont(ofSize: size)
        result.uiKit.paragraphStyle = paragraph
        result.uiKit.foregroundColor = color
        #endif
        result.link = URL(string: link)
        return result
    }

    @MainActor
    func testRepeatedInputPreservesNativeFontNormalizationAndSelection() async {
        let view = makeView()
        let value = input("中文 ‘quotation’ and English\n")
        view.applyAttributedStringPreservingAttachments(value)
        let storage = view._textStorage!
        let fallback = PlatformFont.systemFont(ofSize: 18, weight: .medium)
        // Model the attribute-only normalization performed by the platform text system.
        storage.addAttribute(.font, value: fallback, range: NSRange(location: 0, length: 2))
        let normalizedFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #if canImport(AppKit)
        view.setSelectedRange(NSRange(location: 0, length: 2))
        #else
        view.selectedRange = NSRange(location: 0, length: 2)
        #endif
        for _ in 0..<3 { view.applyAttributedStringPreservingAttachments(value) }
        XCTAssertEqual(storage.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont, normalizedFont)
        XCTAssertEqual(storage.string, String(value.characters))
        #if canImport(AppKit)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 2))
        #else
        XCTAssertEqual(view.selectedRange, NSRange(location: 0, length: 2))
        #endif
    }

    @MainActor
    func testChangedTextAndAttributesApplyAfterRepeatedInput() async {
        let view = makeView()
        let values = [input("Alpha"), input("Bravo"), input("Bravo", size: 24),
                      input("Bravo", size: 24, spacing: 28, color: .blue, link: "https://example.com/b"),
                      input("Alpha"), input(""), input("Alpha")]
        for value in values {
            view.applyAttributedStringPreservingAttachments(value)
            view.applyAttributedStringPreservingAttachments(value)
            let storage = view._textStorage!
            XCTAssertEqual(storage.string, String(value.characters))
            guard storage.length > 0 else { continue }
            let expected = NSAttributedString(value)
            for key in [NSAttributedString.Key.font, .paragraphStyle, .foregroundColor, .link] {
                XCTAssertEqual(storage.attribute(key, at: 0, effectiveRange: nil) as? NSObject,
                               expected.attribute(key, at: 0, effectiveRange: nil) as? NSObject, "\(key)")
            }
        }
    }

    @MainActor
    func testSameAttachmentIdentityUpdatesReplacementAndKeepsHost() async {
        let view = makeView()
        func content(_ label: String) -> AttributedString {
            let attachment = InlineHostingAttachment(Text(label), id: "block", replacement: AttributedString(label))
            return TextContent(.string("Before "), .view(attachment), .string(" After")).fragments
                .reduce(into: AttributedString()) { $0 += $1.asAttributedString() }
        }
        view.applyAttributedStringPreservingAttachments(content("old code"))
        let original = view.inlineAttachmentsByID["block"]!
        let originalHost = original.hostingView
        view.applyAttributedStringPreservingAttachments(content("new code"))
        XCTAssertTrue(view.inlineAttachmentsByID["block"] === original)
        XCTAssertTrue(original.hostingView === originalHost)
        XCTAssertEqual(view.replaceAttachmentWithEquivalentText(in: view.storageAttributedString!).string,
                       "Before new code After")
    }

    @MainActor
    func testConversionPreservesParagraphSpacingAndFontPrecedence() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("SwiftUI font resolution requires OS 26") }
        var environment = EnvironmentValues()
        environment.font = .system(size: 18)
        environment.richTextMinimumLineHeight = 34
        environment.lineHeight = .multiple(factor: 1.4)
        var value = input("Styled text", size: 14, spacing: 23)
        value.swiftUI.font = .system(size: 28)
        value.swiftUI.foregroundColor = .blue
        value.swiftUI.lineHeight = .exact(points: 42)
        value.inlinePresentationIntent = [.stronglyEmphasized, .strikethrough]
        let converted = try TextContent(.attributedString(value)).attributedString(environmentValues: environment).nsAttributedString
        let font = converted.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        let paragraph = converted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(font?.pointSize, 28)
        XCTAssertEqual(paragraph?.paragraphSpacing, 23)
        XCTAssertEqual(paragraph?.minimumLineHeight, 34)
        XCTAssertEqual(paragraph?.maximumLineHeight, 0)
        XCTAssertEqual(paragraph?.lineHeightMultiple ?? 0, 1.4, accuracy: 0.001)
        XCTAssertEqual(converted.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor, PlatformColor(.blue))
        XCTAssertEqual((converted.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? NSNumber)?.intValue,
                       NSUnderlineStyle.single.rawValue)
    }

    #if canImport(UIKit)
    @MainActor
    func testMeasurementMatchesNativeAfterWidthContentAndLineLimitChanges() async {
        let view = makeView()
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        let text = String(repeating: "中文 mixed English paragraph.\n", count: 20)
        var previousHeight: CGFloat?
        var wideHeight: CGFloat?
        for (width, lines, content) in [(CGFloat(362), Optional<Int>.none, text),
                                       (180, nil, text), (362, nil, text), (362, 1, text),
                                       (362, 2, text), (362, nil, text), (362, nil, "New text.")] {
            var environment = EnvironmentValues()
            environment.lineLimit = lines
            let configuration = TextViewRenderConfiguration(environmentValues: environment)
            TextAttributeConverter.mergeRenderConfigurationIntoTextView(view, configuration: configuration)
            view.applyAttributedStringPreservingAttachments(input(content))
            view.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
            view.layoutIfNeeded()
            let proposal = CGSize(width: width, height: UIView.noIntrinsicMetric)
            let measured = view.measuredSizeThatFits(proposal)
            let repeated = view.measuredSizeThatFits(proposal)
            XCTAssertEqual(measured, view.sizeThatFits(proposal))
            XCTAssertEqual(repeated, measured)
            if content == text && lines == nil {
                if width == 180 { XCTAssertGreaterThan(measured.height, previousHeight!) }
                else if let wideHeight { XCTAssertEqual(measured.height, wideHeight) }
                else { wideHeight = measured.height }
            }
            previousHeight = measured.height
        }
    }
    #endif
}
