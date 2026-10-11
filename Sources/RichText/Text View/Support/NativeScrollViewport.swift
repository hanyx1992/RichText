#if canImport(UIKit)
import SwiftUI

/// Page-local position; native scrolling does not invalidate SwiftUI.
@MainActor
public final class RichTextScrollPosition {
    public var offset: CGPoint = .zero

    public init() {}
}

/// Consumed by the root text view; nested hosted text does not inherit it.
public struct RichTextNativeScrollViewport {
    /// Advance whenever the root content or hosted attachment rendering changes.
    /// Nil keeps the normal conversion path on every update.
    public var contentVersion: AnyHashable?
    var header: AnyView
    var columnWidth: CGFloat
    var padding: CGFloat
    var headerSpacing: CGFloat
    var position: RichTextScrollPosition

    public init(header: some View, columnWidth: CGFloat, padding: CGFloat,
                headerSpacing: CGFloat, position: RichTextScrollPosition) {
        self.header = AnyView(header)
        self.columnWidth = columnWidth
        self.padding = padding
        self.headerSpacing = headerSpacing
        self.position = position
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
#endif
