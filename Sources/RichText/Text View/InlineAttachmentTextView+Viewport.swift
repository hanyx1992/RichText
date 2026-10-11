#if canImport(UIKit)
import SwiftUI

extension InlineAttachmentTextView {
    func updateNativeScrollViewport(_ viewport: RichTextNativeScrollViewport?) {
        nativeScrollViewport = viewport
        isScrollEnabled = viewport != nil
        guard let viewport else { return }

        // The SwiftUI geometry already excludes the system safe area.
        contentInsetAdjustmentBehavior = .never
        clipsToBounds = true
        if viewportHeader == nil {
            viewportHeader = UIHostingController(rootView: AnyView(EmptyView()))
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
        header.view.frame = CGRect(x: side, y: viewport.padding, width: width, height: height)
        let inset = UIEdgeInsets(top: viewport.padding + height + viewport.headerSpacing,
                                 left: side, bottom: viewport.padding, right: side)
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

    func saveNativeScrollPosition() {
        guard pendingViewportOffset == nil else { return }
        nativeScrollViewport?.position.offset = contentOffset
    }
}
#endif
