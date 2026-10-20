import SwiftUI
import XCTest
@testable import RichText

final class TextSelectionActionTests: XCTestCase {
    @MainActor
    func testRepeatedSentenceUsesNativeUTF16RangeAndKeepsEmoji() async throws {
        let view = InlineAttachmentTextView(usingTextLayoutManager: false)
        let text = "前😀 first。同一句话。中间👩🏽‍💻 second。同一句话。结尾🎉"
        view.applyAttributedStringPreservingAttachments(AttributedString(text))
        let value = text as NSString
        let range = value.range(of: "同一句话。", options: .backwards)
        let selection = try XCTUnwrap(view.selectionSnapshot(in: range))
        XCTAssertEqual(selection.range, range)
        XCTAssertEqual(selection.before, "前😀 first。同一句话。中间👩🏽‍💻 second。")
        XCTAssertEqual(selection.selected, "同一句话。")
        XCTAssertEqual(selection.after, "结尾🎉")
        XCTAssertEqual(selection.before + selection.selected + selection.after, text)
    }


    @MainActor
    func testNestedReplacementIsExpandedInsideOriginalSelectionRange() async throws {
        let view = InlineAttachmentTextView(usingTextLayoutManager: false)
        let inner = InlineHostingAttachment(Text("inner"), id: "inner", replacement: AttributedString("nested 😀 text"))
        let nested = TextContent(.string("outer "), .view(inner), .string(" end")).fragments
            .reduce(into: AttributedString()) { $0 += $1.asAttributedString() }
        let outer = InlineHostingAttachment(Text("outer"), id: "outer", replacement: nested)
        let value = TextContent(.string("before "), .view(outer), .string(" after")).fragments
            .reduce(into: AttributedString()) { $0 += $1.asAttributedString() }
        view.applyAttributedStringPreservingAttachments(value)
        let selection = try XCTUnwrap(view.selectionSnapshot(in: view.inlineAttachmentRangesByID["outer"]!))
        XCTAssertEqual(selection.selected, "outer nested 😀 text end")
        XCTAssertEqual(selection.before, "before ")
        XCTAssertEqual(selection.after, " after")
    }

    @MainActor
    func testAttachmentReplacementKeepsSelectionBoundariesAndRejectsImageOnly() async throws {
        let view = InlineAttachmentTextView(usingTextLayoutManager: false)
        let code = InlineHostingAttachment(Text("code"), id: "code", replacement: AttributedString("let 👩🏽‍💻 = 1\n"))
        let image = InlineHostingAttachment(Text("image"), id: "image", replacement: nil)
        let table = InlineHostingAttachment(Text("table"), id: "table", replacement: AttributedString("A\tB\n1\t2"))
        let value = TextContent(.string("before "), .view(code), .string(" middle "), .view(image),
                                .string(" "), .view(table), .string(" after")).fragments
            .reduce(into: AttributedString()) { $0 += $1.asAttributedString() }
        view.applyAttributedStringPreservingAttachments(value)
        let ranges = view.inlineAttachmentRangesByID
        let selected = try XCTUnwrap(view.selectionSnapshot(in: ranges["code"]!))
        XCTAssertEqual(selected.before, "before ")
        XCTAssertEqual(selected.selected, "let 👩🏽‍💻 = 1\n")
        XCTAssertEqual(selected.after, " middle  A\tB\n1\t2 after")
        XCTAssertNil(view.selectionSnapshot(in: ranges["image"]!))
        let all = try XCTUnwrap(view.selectionSnapshot(in: NSRange(location: 0, length: view.storageAttributedString!.length)))
        XCTAssertEqual(all.selected, "before let 👩🏽‍💻 = 1\n middle  A\tB\n1\t2 after")
        XCTAssertEqual(all.before, "")
        XCTAssertEqual(all.after, "")
        XCTAssertNil(view.selectionSnapshot(in: NSRange(location: NSNotFound, length: 1)))
        XCTAssertNil(view.selectionSnapshot(in: NSRange(location: 0, length: 0)))
    }
}
