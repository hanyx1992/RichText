import SwiftUI

extension InlineAttachmentTextView {
    var nativeViewportRect: CGRect {
        #if canImport(AppKit)
        return visibleRect
        #else
        return bounds
        #endif
    }

    func nativeVisibleTextRange(excludingChrome: Bool = false) -> NSRange? {
        guard nativeScrollViewport != nil, !isDismantled,
              let manager = _layoutManager, let container = _textContainer,
              let storage = manager.textStorage else { return nil }
        var viewport = nativeViewportRect
        if excludingChrome, let insets = nativeScrollViewport?.safeAreaInsets {
            viewport.origin.y += insets.top
            viewport.size.height = max(0, viewport.height - insets.top - insets.bottom)
        }
        let rect = viewport.offsetBy(dx: -textContainerOffset.x, dy: -textContainerOffset.y)
        var glyphs = manager.glyphRange(forBoundingRectWithoutAdditionalLayout: rect, in: container)
        guard glyphs.location != NSNotFound else { return nil }
        if excludingChrome {
            // TextKit's bounding query can include the line above a paragraph gap.
            // Discard only lines already laid out whose painted content ends above the viewport.
            let end = NSMaxRange(glyphs)
            while glyphs.length > 0 {
                var line = NSRange()
                let used = manager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: &line,
                                                        withoutAdditionalLayout: true)
                guard !used.isEmpty, used.maxY <= rect.minY + 0.5, NSMaxRange(line) > glyphs.location else { break }
                let next = min(end, NSMaxRange(line))
                glyphs = NSRange(location: next, length: end - next)
            }
        }
        return NSIntersectionRange(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil),
                                   NSRange(location: 0, length: storage.length))
    }

    func nativeReadingLocation() -> (range: NSRange, atEnd: Bool)? {
        guard let visible = nativeVisibleTextRange(excludingChrome: true), visible.length > 0,
              let manager = _layoutManager, let container = _textContainer,
              let length = manager.textStorage?.length, length > 0 else { return nil }
        guard NSMaxRange(visible) >= length else { return (visible, false) }
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: length - 1, length: 1), actualCharacterRange: nil)
        let bottom = manager.boundingRect(forGlyphRange: glyphs, in: container).maxY + textContainerOffset.y
        return (visible, bottom <= nativeViewportRect.maxY - (nativeScrollViewport?.safeAreaInsets.bottom ?? 0) + 1)
    }

    func scrollNativeTextRange(_ range: NSRange, alignBottom: Bool = false) -> Bool {
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
            let y = alignBottom ? rect.maxY - nativeViewportRect.height + (nativeScrollViewport?.safeAreaInsets.bottom ?? 0)
                                : rect.minY - (nativeScrollViewport?.safeAreaInsets.top ?? 0)
            #if canImport(AppKit)
            scrollToNativeOffset(CGPoint(x: 0, y: max(0, y)))
            #else
            setContentOffset(CGPoint(x: 0, y: max(0, min(y, contentSize.height - bounds.height))), animated: false)
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
