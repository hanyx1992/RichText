import SwiftUI
import XCTest
@testable import RichText

final class NativeViewportTests: XCTestCase {
    #if canImport(AppKit)
    @MainActor
    func testNativeHeaderTailGeometryAndVisibleRange() async throws {
        let position = RichTextScrollPosition()
        let text = String(repeating: "A long mixed 中文 paragraph with enough words to wrap to another line.\n", count: 3000)
        let root = TextView(text)
            .richTextNativeScrollViewport(RichTextNativeScrollViewport(
                header: Text("Article title\nTAG one TAG two").frame(height: 120),
                columnWidth: 600, padding: 24, headerSpacing: 24, position: position))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(position.textView)
        let manager = try XCTUnwrap(view.layoutManager)
        print("VIEWPORT initial length=\(view.string.utf16.count) firstUnlaid=\(manager.firstUnlaidCharacterIndex()) frame=\(view.frame) origin=\(view.textContainerOrigin) inset=\(view.textContainerInset) visible=\(view.visibleRect)")
        XCTAssertNil(view.textLayoutManager)
        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
        XCTAssertEqual(view.textContainerOrigin.y, 168, accuracy: 1)
        XCTAssertEqual(view.textContainerInset.height, 24)
        let target = NSRange(location: view.string.utf16.count - 30, length: 20)
        let start = ContinuousClock.now
        let ready = position.scroll(to: target)
        let elapsed = start.duration(to: .now)
        print("VIEWPORT tail ready=\(ready) elapsed=\(elapsed) firstUnlaid=\(manager.firstUnlaidCharacterIndex()) frame=\(view.frame) visible=\(view.visibleRect) capture=\(String(describing: position.visibleTextRange()))")
        XCTAssertTrue(ready)
        let initialOffset = view.visibleRect.origin
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.visibleRect.origin.y, initialOffset.y, accuracy: 1)
            XCTAssertGreaterThan(NSIntersectionRange(position.visibleTextRange() ?? NSRange(), target).length, 0)
        }
        print("VIEWPORT tail settled frame=\(view.frame) visible=\(view.visibleRect)")
        let endGlyphs = manager.glyphRange(forCharacterRange: NSRange(location: view.string.utf16.count - 2, length: 1), actualCharacterRange: nil)
        let endRect = manager.boundingRect(forGlyphRange: endGlyphs, in: view.textContainer!)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        print("VIEWPORT end rect=\(endRect) bottomPadding=\(view.bounds.height - endRect.maxY)")
        XCTAssertGreaterThanOrEqual(view.bounds.height - endRect.maxY, 24)
        let visible = try XCTUnwrap(position.visibleTextRange())
        XCTAssertGreaterThan(NSIntersectionRange(visible, target).length, 0)
        XCTAssertFalse(position.scroll(to: NSRange(location: view.string.utf16.count + 1, length: 1)))
    }

    @MainActor
    func testViewportUpdatesAndDeepOffsetRemount() async throws {
        let position = RichTextScrollPosition()
        let model = ViewportModel()
        let host = NSHostingView(rootView: ChangingViewport(model: model, position: position))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let original = try XCTUnwrap(position.textView)
        let target = NSRange(location: model.text.utf16.count - 30, length: 20)
        XCTAssertTrue(position.scroll(to: target))
        for (width, size) in [(CGFloat(420), CGFloat(24)), (600, 18)] {
            model.columnWidth = width
            model.fontSize = size
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(position.textView === original)
            XCTAssertTrue(position.scroll(to: target))
            let offset = original.visibleRect.minY
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(original.visibleRect.minY, offset, accuracy: 1)
            XCTAssertGreaterThan(NSIntersectionRange(position.visibleTextRange() ?? NSRange(), target).length, 0)
        }
        let savedOffset = position.offset
        model.identity += 1
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let remounted = try XCTUnwrap(position.textView)
        XCTAssertFalse(remounted === original)
        XCTAssertTrue(original.isDismantled)
        XCTAssertEqual(remounted.visibleRect.minY, savedOffset.y, accuracy: 1)
        print("VIEWPORT remount requested=\(savedOffset) actual=\(remounted.visibleRect.origin) firstUnlaid=\(remounted.layoutManager!.firstUnlaidCharacterIndex())")
    }

    @MainActor
    func testNativeAttachmentsRetainHostsOffscreenAndRejectOldOwnerInvalidation() async throws {
        let position = RichTextScrollPosition()
        let root = TextView {
            "Before\n"
            InlineView("First table equivalent") { Text("First table").frame(width: 400, height: 120).id("first") }
            String(repeating: "Mixed paragraph words 中文 continue through the document.\n", count: 2000)
            InlineView("Tail media equivalent") { Text("Tail media").frame(width: 400, height: 150).id("last") }
            "\nEnd"
        }
        .richTextNativeScrollViewport(RichTextNativeScrollViewport(
            header: Text("Header").frame(height: 80), columnWidth: 600,
            padding: 24, headerSpacing: 24, position: position))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(position.textView)
        let first = try XCTUnwrap(view.inlineAttachmentsByID.values.first { $0.replacement?.description.contains("First") == true })
        let originalHost = first.hostingView
        XCTAssertTrue(originalHost.superview === view)
        XCTAssertFalse(originalHost.isHidden)
        XCTAssertTrue(position.scroll(to: NSRange(location: view.string.utf16.count - 2, length: 1)))
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(first.hostingView === originalHost)
        XCTAssertTrue(originalHost.superview === view)
        XCTAssertTrue(originalHost.isHidden)
        XCTAssertTrue(view.replaceAttachmentWithEquivalentText(in: view.storageAttributedString!).string.hasSuffix("Tail media equivalent\nEnd"))
        let newOwner = InlineAttachmentTextView(usingTextLayoutManager: false)
        first.attachmentsHostingTextView = newOwner
        XCTAssertFalse(originalHost.isHidden)
        // A late size notification from an old owner must not invalidate it.
        view.cachedContentHeight = 123
        view.inlineAttachmentsByID[first.id] = InlineHostingAttachment(Text("replacement"), id: first.id, replacement: nil)
        view.invalidateTextLayout(for: first)
        XCTAssertEqual(view.cachedContentHeight, 123)
        view.isDismantled = true
        let oldFrame = originalHost.frame
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(originalHost.frame, oldFrame)
    }

    @MainActor
    func testSameIdentityAttachmentGrowthStillInvalidatesAtMeasuredWidth() async throws {
        let position = RichTextScrollPosition()
        let model = GrowingModel()
        let root = TextView {
            InlineView(id: "growing", replacement: AttributedString("Growing attachment"), sizing: .fittingLineFragment) {
                GrowingView(model: model)
            }
            "\nAfter"
        }
        .richTextNativeScrollViewport(RichTextNativeScrollViewport(
            header: Text("Header"), columnWidth: 600, padding: 24, headerSpacing: 24, position: position))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(position.textView)
        let attachment = try XCTUnwrap(view.inlineAttachmentsByID["growing"])
        XCTAssertFalse(attachment.hostedSizeRequiresTextLayout())
        view.cachedContentHeight = 123
        model.height = 240
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        XCTAssertNil(view.cachedContentHeight)
        XCTAssertTrue(view.inlineAttachmentsByID["growing"] === attachment)
        let range = try XCTUnwrap(view.inlineAttachmentRangesByID["growing"])
        let manager = try XCTUnwrap(view.layoutManager)
        manager.ensureLayout(forCharacterRange: range)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        XCTAssertEqual(manager.boundingRect(forGlyphRange: glyphs, in: view.textContainer!).height, 240, accuracy: 1)
        XCTAssertFalse(attachment.hostedSizeRequiresTextLayout())
    }

    @MainActor
    private final class GrowingModel: ObservableObject {
        @Published var height: CGFloat = 80
    }

    private struct GrowingView: View {
        @ObservedObject var model: GrowingModel
        var body: some View { Color.red.frame(height: model.height).frame(maxWidth: .infinity) }
    }

    @MainActor
    func testShortNativeDocumentStaysAtTopOfViewport() async throws {
        let position = RichTextScrollPosition()
        let root = TextView(String(repeating: "短文阅读。", count: 16))
            .richTextNativeScrollViewport(RichTextNativeScrollViewport(
                header: Text("Short title and TAG").frame(height: 60), columnWidth: 600,
                padding: 24, headerSpacing: 24, position: position))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(position.textView)
        print("VIEWPORT short frame=\(view.frame) visible=\(view.visibleRect) offset=\(position.offset)")
        XCTAssertGreaterThanOrEqual(view.frame.height, view.visibleRect.height)
        XCTAssertEqual(view.visibleRect.minY, 0, accuracy: 0.5)
        XCTAssertEqual(view.textContainerOrigin.y, 108, accuracy: 0.5)
    }

    @MainActor
    private final class ViewportModel: ObservableObject {
        let text = String(repeating: "中文 mixed words need several lines and complete native selection.\n", count: 2000)
        @Published var columnWidth: CGFloat = 600
        @Published var fontSize: CGFloat = 18
        @Published var identity = 0
    }

    private struct ChangingViewport: View {
        @ObservedObject var model: ViewportModel
        let position: RichTextScrollPosition
        var body: some View {
            TextView(model.text)
                .font(NSFont.systemFont(ofSize: model.fontSize))
                .richTextNativeScrollViewport(RichTextNativeScrollViewport(
                    header: Text("Title and TAG").frame(height: 120), columnWidth: model.columnWidth,
                    padding: 24, headerSpacing: 24, position: position))
                .id(model.identity)
        }
    }
    #else
    @MainActor
    func testUIKitNativeHeaderAndDeepTargets() async throws {
        let position = RichTextScrollPosition()
        let text = String(repeating: "A long mixed 中文 paragraph with enough words to wrap to another line.\n", count: 3000)
        let root = TextView(text)
            .richTextNativeScrollViewport(RichTextNativeScrollViewport(
                header: Text("Article title\nTAG one TAG two").frame(height: 120),
                columnWidth: 342, padding: 24, headerSpacing: 24, position: position))
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
        let view = try XCTUnwrap(position.textView)
        XCTAssertNil(view.textLayoutManager)
        let length = view.textStorage.length
        print("VIEWPORT UIKit initial length=\(length) firstUnlaid=\(view.layoutManager.firstUnlaidCharacterIndex()) size=\(view.contentSize) inset=\(view.textContainerInset)")
        for location in [length / 2, length * 9 / 10, length - 2] {
            let target = NSRange(location: location, length: 1)
            let start = ContinuousClock.now
            let ready = position.scroll(to: target)
            print("VIEWPORT UIKit target=\(location) ready=\(ready) elapsed=\(start.duration(to: .now)) firstUnlaid=\(view.layoutManager.firstUnlaidCharacterIndex()) offset=\(view.contentOffset) size=\(view.contentSize)")
            let gr = view.layoutManager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
            let r = view.layoutManager.boundingRect(forGlyphRange: gr, in: view.textContainer)
            print("VIEWPORT UIKit desired=\(r) pending=\(String(describing: view.pendingViewportOffset)) enabled=\(view.isScrollEnabled) bounds=\(view.bounds)")
            XCTAssertTrue(ready)
            let offset = view.contentOffset
            try await Task.sleep(for: .milliseconds(150))
            controller.view.layoutIfNeeded()
            XCTAssertEqual(view.contentOffset.y, offset.y, accuracy: 1)
            XCTAssertGreaterThan(NSIntersectionRange(position.visibleTextRange() ?? NSRange(), target).length, 0)
        }
    }
    #endif
}
