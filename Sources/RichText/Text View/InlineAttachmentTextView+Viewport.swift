#if canImport(UIKit)
import SwiftUI

extension InlineAttachmentTextView {
    func updateNativeScrollViewport(_ viewport: RichTextNativeScrollViewport?) {
        nativeScrollViewport = viewport
        isScrollEnabled = viewport != nil
        guard let viewport else { return }

        // The caller supplies any vertical safe area included in the viewport.
        // Keep it in text geometry so the page-local offset still begins at zero.
        contentInsetAdjustmentBehavior = .never
        automaticallyAdjustsScrollIndicatorInsets = false
        verticalScrollIndicatorInsets = UIEdgeInsets(top: viewport.safeAreaInsets.top, left: 0,
                                                     bottom: viewport.safeAreaInsets.bottom, right: 0)
        clipsToBounds = true
        if viewportHeader == nil {
            viewportHeader = UIHostingController(rootView: AnyView(EmptyView()))
            if #available(iOS 16.4, *) {
                // Header geometry belongs to the text container, including when offscreen.
                viewportHeader?.safeAreaRegions = []
            }
            viewportHeader?.view.backgroundColor = .clear
            if let view = viewportHeader?.view { addSubview(view) }
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
                    self.setNeedsLayout()
                }
        )
        viewportHeaderNeedsMeasurement = true
        setNeedsLayout()
    }

    func layoutNativeScrollHeader() {
        guard let viewport = nativeScrollViewport, let header = viewportHeader,
              bounds.width > 0 else { return }
        let width = max(0, min(viewport.columnWidth, bounds.width - viewport.padding * 2))
        let height: CGFloat
        if viewportHeaderNeedsMeasurement || viewportHeaderWidth != width {
            let size = header.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            height = size.height.isFinite ? max(0, ceil(size.height)) : 0
            viewportHeaderNeedsMeasurement = false
            viewportHeaderWidth = width
        } else {
            height = header.view.frame.height
        }
        let side = max(0, (bounds.width - width) / 2)
        let top = viewport.safeAreaInsets.top + viewport.padding
        header.view.frame = CGRect(x: side, y: top, width: width, height: height)
        let inset = UIEdgeInsets(top: top + height + viewport.headerSpacing,
                                 left: side, bottom: viewport.padding + viewport.safeAreaInsets.bottom,
                                 right: side)
        if textContainerInset != inset {
            textContainerInset = inset
            _invalidateTextLayout()
        }
    }

    func restoreNativeScrollPositionIfNeeded() {
        if isTracking || isDragging || isDecelerating {
            finishNativeScrollRestoration()
            return
        }
        guard nativeScrollViewport != nil, let offset = pendingViewportOffset,
              bounds.height > 0, textStorage.length > 0 else { return }
        // contentSize is still an estimate here. Clamping to it loses a deep
        // reading position before UIKit has laid out that part of the document.
        let wholeDocumentLaidOut = layoutManager.firstUnlaidCharacterIndex() >= textStorage.length
        let bottom = max(0, contentSize.height - bounds.height)
        let y = wholeDocumentLaidOut ? min(max(0, offset.y), bottom) : max(0, offset.y)
        setContentOffset(CGPoint(x: 0, y: y), animated: false)
        // UIKit refines estimated geometry across subsequent layout passes.
        // Keep the requested position until the reader starts an interaction.
    }

    func finishNativeScrollRestoration() {
        pendingViewportOffset = nil
        saveNativeScrollPosition()
    }

    func prepareNativeScrollLayout(in rect: CGRect) {
        guard nativeScrollViewport != nil, !isDismantled, !rect.isNull,
              rect.minY.isFinite, rect.height.isFinite,
              textContainer.size.width.isFinite, textContainer.size.width > 0,
              bounds.height.isFinite, bounds.height > 0 else { return }
        // Header targets map to the first text viewport, including its attachments.
        let target = CGRect(x: 0, y: max(0, rect.minY - textContainerOffset.y),
                            width: textContainer.size.width,
                            height: max(bounds.height, rect.height))
        layoutManager.ensureLayout(forBoundingRect: target, in: textContainer)
    }

    func saveNativeScrollPosition() {
        guard pendingViewportOffset == nil else { return }
        nativeScrollViewport?.position.offset = contentOffset
    }
}
#endif
