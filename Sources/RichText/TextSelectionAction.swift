import SwiftUI

/// A snapshot of the native UTF-16 selection, with attachments converted using
/// the same equivalent text as Copy. The three strings preserve its boundaries.
public struct RichTextSelection {
    public let range: NSRange
    public let before: String
    public let selected: String
    public let after: String
}

struct RichTextSelectionAction {
    let title: String
    let perform: (RichTextSelection) -> Void
}

private struct RichTextSelectionActionKey: EnvironmentKey {
    static var defaultValue: RichTextSelectionAction? { nil }
}

extension EnvironmentValues {
    var richTextSelectionAction: RichTextSelectionAction? {
        get { self[RichTextSelectionActionKey.self] }
        set { self[RichTextSelectionActionKey.self] = newValue }
    }
}

public extension View {
    /// Adds an action to the native selection menu of descendant text views.
    func richTextSelectionAction(_ title: String, perform: ((RichTextSelection) -> Void)?) -> some View {
        environment(\.richTextSelectionAction, perform.map { RichTextSelectionAction(title: title, perform: $0) })
    }
}

extension InlineAttachmentTextView {
    func selectionSnapshot(in range: NSRange) -> RichTextSelection? {
        guard let storage = storageAttributedString,
              range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= storage.length, range.length <= storage.length - range.location else { return nil }
        // Slice first: expanding an attachment changes UTF-16 lengths. Only the
        // original storage range can identify repeated text and its neighbours.
        func plainText(_ value: NSAttributedString) -> String {
            var result = ""
            value.enumerateAttribute(.inlineHostingAttachment, in: NSRange(location: 0, length: value.length)) { attribute, run, _ in
                if let attachment = attribute as? InlineHostingAttachment {
                    if let replacement = attachment.replacement {
                        let nested = (try? replacement.nsAttributedString) ?? NSAttributedString(replacement)
                        result += plainText(nested)
                    }
                } else {
                    result += (value.string as NSString).substring(with: run)
                        .replacingOccurrences(of: "\u{fffc}", with: "")
                }
            }
            return result
        }
        func text(_ range: NSRange) -> String {
            plainText(storage.attributedSubstring(from: range))
        }
        let selected = text(range)
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RichTextSelection(range: range,
                                 before: text(NSRange(location: 0, length: range.location)),
                                 selected: selected,
                                 after: text(NSRange(location: NSMaxRange(range), length: storage.length - NSMaxRange(range))))
    }
}
