import SwiftUI

extension InlineAttachmentTextView {
    var nativeViewportRect: CGRect {
        #if canImport(AppKit)
        return visibleRect
        #else
        return bounds
        #endif
    }

    func nativeVisibleTextRange() -> NSRange? {
        guard nativeScrollViewport != nil, !isDismantled,
              let manager = _layoutManager, let container = _textContainer,
              let storage = manager.textStorage else { return nil }
        let rect = nativeViewportRect.offsetBy(dx: -textContainerOffset.x, dy: -textContainerOffset.y)
        let glyphs = manager.glyphRange(forBoundingRectWithoutAdditionalLayout: rect, in: container)
        guard glyphs.location != NSNotFound else { return nil }
        return NSIntersectionRange(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil),
                                   NSRange(location: 0, length: storage.length))
    }

    func scrollNativeTextRange(_ range: NSRange) -> Bool {
        guard nativeScrollViewport != nil, !isDismantled,
              let manager = _layoutManager, let container = _textContainer,
              let storage = manager.textStorage,
              range.location >= 0, range.location < storage.length,
              range.length >= 0, range.length <= storage.length - range.location else { return false }
        pendingViewportOffset = nil
        let target = NSRange(location: range.location, length: max(1, range.length))
        // TextKit 1 reports estimated target Y values with discontiguous layout.
        // Settle the container before claiming synchronous readiness. This explicit
        // targeting cost is separate from normal viewport-only opening/scrolling.
        manager.ensureLayout(for: container)
        #if canImport(AppKit)
        layoutSubtreeIfNeeded()
        #else
        layoutIfNeeded()
        #endif
        func revealTarget() -> CGRect {
            let glyphs = manager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: textContainerOffset.x, dy: textContainerOffset.y)
            #if canImport(AppKit)
            scrollToNativeOffset(CGPoint(x: 0, y: max(0, rect.minY)))
            #else
            setContentOffset(CGPoint(x: 0, y: max(0, min(rect.minY, contentSize.height - bounds.height))), animated: false)
            layoutIfNeeded()
            #endif
            updateInlineAttachmentViews()
            return rect
        }
        var rect = revealTarget()
        // Mount only visible hosts, then settle one synchronous measurement pass
        // before reporting readiness. Later asynchronous changes retain the usual
        // attachment invalidation path; this does not keep pulling the reader back.
        if settleNativeViewportAttachmentLayout() {
            manager.ensureLayout(for: container)
            #if canImport(AppKit)
            layoutSubtreeIfNeeded()
            #else
            layoutIfNeeded()
            #endif
            rect = revealTarget()
        }
        saveNativeScrollPosition()
        return nativeViewportRect.intersects(rect)
    }
}
