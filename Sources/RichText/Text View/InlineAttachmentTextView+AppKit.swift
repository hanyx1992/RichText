//
//  InlineAttachmentTextView+AppKit.swift
//  RichText
//
//  Created by Yanan Li on 2026/6/20.
//

#if canImport(AppKit)

import AppKit

extension InlineAttachmentTextView {
    
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        if let action = selectionAction, selectionSnapshot(in: selectedRange()) != nil {
            let item = NSMenuItem(title: action.title, action: #selector(performSelectionAction(_:)), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    @objc private func performSelectionAction(_ sender: Any?) {
        guard let selection = selectionSnapshot(in: selectedRange()) else { return }
        selectionAction?.perform(selection)
    }

    var textContainerOffset: CGPoint {
        textContainerOrigin
    }
    
    override func setConstrainedFrameSize(_ desiredSize: NSSize) {
        guard nativeScrollViewport != nil else {
            super.setConstrainedFrameSize(desiredSize)
            return
        }
        // NSTextView adds its symmetric inset while resizing. The header is an
        // asymmetric origin, so account for just the extra top space here.
        let extraTop = max(0, viewportHeaderHeight - textContainerInset.height)
        super.setConstrainedFrameSize(NSSize(width: desiredSize.width,
                                            height: desiredSize.height + extraTop))
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return nativeScrollViewport == nil ? origin : NSPoint(x: origin.x, y: viewportHeaderHeight)
    }

    override func keyDown(with event: NSEvent) {
        nativeScrollViewport?.position.interactionSequence &+= 1
        pendingViewportOffset = nil
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        nativeScrollViewport?.position.interactionSequence &+= 1
        pendingViewportOffset = nil
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        nativeScrollViewport?.position.interactionSequence &+= 1
        pendingViewportOffset = nil
        super.mouseDown(with: event)
    }

    override func layout() {
        guard !isDismantled else { return }
        layoutNativeScrollHeader()
        super.layout()
        if let cachedContentHeightWidth,
           cachedContentHeightWidth != bounds.width {
            cachedContentHeight = nil
            invalidateIntrinsicContentSize()
        }
        restoreNativeScrollPositionIfNeeded()
        updateInlineAttachmentViews()
        nativeScrollViewport?.position.didLayout(self)
    }
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: PlatformView.noIntrinsicMetric,
               height: nativeScrollViewport == nil ? _measuredContentHeight : PlatformView.noIntrinsicMetric)
    }
    
    private var _measuredContentHeight: CGFloat {
        if let cachedContentHeight,
           cachedContentHeightWidth == bounds.width {
            return cachedContentHeight
        }
        
        if let textLayoutManager {
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
            
            var maximumY: CGFloat = 0
            textLayoutManager.enumerateTextSegments(
                in: textLayoutManager.documentRange,
                type: .standard,
                options: [.rangeNotRequired]
            ) { _, segmentFrame, _, _ in
                maximumY = max(maximumY, segmentFrame.maxY)
                return true
            }
            
            let measuredContentHeight = ceil(maximumY + textContainerOffset.y)
            cachedContentHeight = measuredContentHeight
            cachedContentHeightWidth = bounds.width
            return measuredContentHeight
        }
        
        if let layoutManager = _layoutManager,
           let textContainer = _textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let measuredContentHeight = ceil(
                layoutManager.usedRect(for: textContainer).maxY
                + textContainerOffset.y
            )
            cachedContentHeight = measuredContentHeight
            cachedContentHeightWidth = bounds.width
            return measuredContentHeight
        }
        
        return bounds.height
    }
    
    // FIXME: This only works for "Copy" and "Search with Google".
    // Lookup, Translate, Share are using original strings
    override func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        guard let original = super.attributedSubstring(
            forProposedRange: range,
            actualRange: actualRange
        ) else { return nil }

        return replaceAttachmentWithEquivalentText(
            in: original
        )
    }
    
}

#endif
