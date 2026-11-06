import SwiftUI

/// Page-local position; native scrolling does not invalidate SwiftUI.
/// Keep this object stable for one reading page's lifetime. The offset restores
/// the initial viewport and records scrolling; it is not a live scroll command.
/// Give `TextView` a new identity when switching to another page's position.
@MainActor
public final class RichTextScrollPosition {
    public var offset: CGPoint = .zero

    /// Called once after an accepted content version has usable viewport geometry.
    public internal(set) var interactionSequence: UInt = 0
    var acceptedVersion: AnyHashable?
    private var deliveredVersion: AnyHashable?
    private var detachedLocation: (range: NSRange, atEnd: Bool)?

    func didLayout(_ view: InlineAttachmentTextView) {
        guard textView === view, let onAccepted = view.nativeScrollViewport?.onAccepted, let version = acceptedVersion,
              view.nativeScrollViewport?.contentVersion == version, deliveredVersion != version,
              view.window != nil, view.nativeViewportRect.height > 0,
              let storage = view._layoutManager?.textStorage else { return }
        deliveredVersion = version
        // A Swift String is an immutable snapshot of the accepted display text.
        onAccepted(version, storage.string)
    }

    public var hasAcceptedReadingContent: Bool {
        guard let view = textView, view.window != nil, !view.isDismantled, let version = acceptedVersion else { return false }
        return view.nativeScrollViewport?.contentVersion == version && deliveredVersion == version
    }

    public func readingLocation() -> (range: NSRange, atEnd: Bool)? {
        guard let view = textView, !view.isDismantled else { return detachedLocation }
        return view.nativeReadingLocation()
    }

    func willDetach(_ view: InlineAttachmentTextView) {
        guard textView === view else { return }
        detachedLocation = view.nativeReadingLocation()
        deliveredVersion = nil
        acceptedVersion = nil
    }

    /// Reveals the entire page header before the first reading block.
    @discardableResult
    public func scrollToPageStart() -> Bool { textView?.scrollNativePageStart() ?? false }

    public func scrollToReadingEnd() -> Bool {
        guard let view = textView, let length = view._layoutManager?.textStorage?.length, length > 0 else { return false }
        return view.scrollNativeTextRange(NSRange(location: length - 1, length: 1), alignBottom: true)
            && view.nativeReadingLocation()?.atEnd == true
    }

    weak var textView: InlineAttachmentTextView?

    /// Visible display-text UTF-16 range, without requesting full-document layout.
    public func visibleTextRange() -> NSRange? { textView?.nativeVisibleTextRange() }

    /// Synchronously lays out and reveals a display-text range in the accepted document.
    /// Returns false while unmounted or when the range is outside that document.
    @discardableResult
    public func scroll(to range: NSRange) -> Bool { textView?.scrollNativeTextRange(range) ?? false }

    public init() {}
}

/// Consumed by the root text view; nested hosted text does not inherit it.
public struct RichTextNativeScrollViewport {
    /// Advance whenever the root content or hosted attachment rendering changes.
    /// Nil keeps the normal conversion path on every update.
    public var onAccepted: ((AnyHashable, String) -> Void)?
    public var contentVersion: AnyHashable?
    var header: AnyView
    var columnWidth: CGFloat
    var padding: CGFloat
    var headerSpacing: CGFloat
    var position: RichTextScrollPosition
    var safeAreaInsets: EdgeInsets

    /// Vertical safe-area insets when the viewport extends behind system chrome.
    /// The caller continues to constrain the viewport to the horizontal safe area.
    public init(header: some View, columnWidth: CGFloat, padding: CGFloat,
                headerSpacing: CGFloat, position: RichTextScrollPosition,
                safeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.header = AnyView(header)
        self.columnWidth = columnWidth
        self.padding = padding
        self.headerSpacing = headerSpacing
        self.position = position
        self.safeAreaInsets = safeAreaInsets
    }
}

extension View {
    public nonisolated func richTextNativeScrollViewport(_ viewport: RichTextNativeScrollViewport?) -> some View {
        environment(\.richTextNativeScrollViewport, viewport)
    }
}

private struct NativeScrollViewportKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: RichTextNativeScrollViewport? = nil
}

extension EnvironmentValues {
    var richTextNativeScrollViewport: RichTextNativeScrollViewport? {
        get { self[NativeScrollViewportKey.self] }
        set { self[NativeScrollViewportKey.self] = newValue }
    }
}
