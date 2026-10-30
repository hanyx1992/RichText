#if canImport(AppKit)
import SwiftUI

extension InlineAttachmentTextView {
    func updateNativeScrollViewport(_ viewport: RichTextNativeScrollViewport?) {
        nativeScrollViewport = viewport
        guard let viewport else { return }
        viewport.position.textView = self
        enclosingScrollView?.scrollerInsets = NSEdgeInsets(top: viewport.safeAreaInsets.top, left: 0,
                                                          bottom: viewport.safeAreaInsets.bottom, right: 0)
        if viewportHeader == nil {
            let header = NSHostingController(rootView: AnyView(EmptyView()))
            header.sizingOptions = []
            if #available(macOS 14.0, *) { header.safeAreaRegions = [] }
            viewportHeader = header
            addSubview(header.view)
            pendingViewportOffset = viewport.position.offset
        }
        viewportHeader?.rootView = AnyView(
            viewport.header
                .environment(\.richTextNativeScrollViewport, nil)
                .ignoresSafeArea()
                .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                    guard let self, self.viewportHeaderSize != size else { return }
                    self.viewportHeaderSize = size
                    self.viewportHeaderNeedsMeasurement = true
                    self.needsLayout = true
                }
        )
        viewportHeaderNeedsMeasurement = true
        needsLayout = true
    }

    func layoutNativeScrollHeader() {
        guard let viewport = nativeScrollViewport, let header = viewportHeader,
              let scrollView = enclosingScrollView, scrollView.contentSize.width > 0 else { return }
        let viewportWidth = scrollView.contentSize.width
        let width = max(0, min(viewport.columnWidth, viewportWidth - viewport.padding * 2))
        let height: CGFloat
        if viewportHeaderNeedsMeasurement || viewportHeaderWidth != width {
            let measured = header.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            height = measured.height.isFinite ? max(0, ceil(measured.height)) : 0
            viewportHeaderNeedsMeasurement = false
            viewportHeaderWidth = width
        } else {
            height = header.view.frame.height
        }
        let side = max(0, (viewportWidth - width) / 2)
        let top = viewport.safeAreaInsets.top + viewport.padding
        header.view.frame = CGRect(x: side, y: top, width: width, height: height)
        let headerHeight = top + height + viewport.headerSpacing
        let inset = NSSize(width: side, height: viewport.padding + viewport.safeAreaInsets.bottom)
        if viewportHeaderHeight != headerHeight || textContainerInset != inset || frame.width != viewportWidth {
            viewportHeaderHeight = headerHeight
            textContainerInset = inset
            setFrameSize(NSSize(width: viewportWidth, height: max(frame.height, scrollView.contentSize.height)))
            _invalidateTextLayout()
        }
    }

    func scrollToNativeOffset(_ offset: CGPoint) {
        guard let scrollView = enclosingScrollView else { return }
        let bottom = max(0, bounds.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: min(max(0, offset.y), bottom)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func restoreNativeScrollPositionIfNeeded() {
        guard nativeScrollViewport != nil, let offset = pendingViewportOffset,
              (textStorage?.length ?? 0) > 0 else { return }
        if let scrollView = enclosingScrollView,
           offset.y > max(0, bounds.height - scrollView.contentSize.height),
           let manager = _layoutManager, let container = _textContainer,
           manager.firstUnlaidCharacterIndex() < (manager.textStorage?.length ?? 0) {
            // A remounted document may initially underestimate its extent. Resolve
            // that extent before NSClipView clamps a previously valid deep offset.
            manager.ensureLayout(for: container)
            let height = manager.usedRect(for: container).maxY + textContainerOffset.y + textContainerInset.height
            setFrameSize(NSSize(width: frame.width, height: max(height, scrollView.contentSize.height)))
        }
        scrollToNativeOffset(offset)
        // Keep the requested offset while NSTextView refines estimated geometry.
        // User input ends restoration, matching the UIKit viewport.
    }

    func saveNativeScrollPosition() {
        guard pendingViewportOffset == nil else { return }
        nativeScrollViewport?.position.offset = nativeViewportRect.origin
    }
}
#endif
