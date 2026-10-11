//
//  InlineAttachmentTextView+UIKit.swift
//  RichText
//
//  Created by Yanan Li on 2026/6/20.
//

#if canImport(UIKit)

import UIKit

extension InlineAttachmentTextView {
    // UIKit’s inherited UITextView(usingTextLayoutManager:) factory bypassed Swift stored-property initialization, causing Dictionary.makeIterator() to access null storage.
    convenience init(usingTextLayoutManager: Bool) {
        self.init(frame: .zero, textContainer: nil)
        
        if !usingTextLayoutManager {
            _ = layoutManager // maunally fallback to TextKit 1
        }
    }
    
    var textContainerOffset: CGPoint {
        CGPoint(
            x: textContainerInset.left,
            y: textContainerInset.top
        )
    }

    func measuredSizeThatFits(_ proposal: CGSize) -> CGSize {
        if let cachedFittingSize,
           cachedFittingSize.proposal == proposal,
           cachedFittingSize.containerSize == textContainer.size,
           cachedFittingSize.boundsWidth == bounds.width {
            return cachedFittingSize.size
        }

        let revision = textLayoutRevision
        let size = sizeThatFits(proposal)
        // A synchronous attachment update during measurement must not be cached.
        if revision == textLayoutRevision {
            cachedFittingSize = (proposal, textContainer.size, bounds.width, size)
        }
        return size
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection != traitCollection { _invalidateTextLayout() }
    }
    
    override func layoutSubviews() {
        layoutNativeScrollHeader()
        super.layoutSubviews()
        if nativeScrollViewport == nil { invalidateIntrinsicContentSize() }
        restoreNativeScrollPositionIfNeeded()
        updateInlineAttachmentViews()
        if let header = viewportHeader?.view { bringSubviewToFront(header) }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: PlatformView.noIntrinsicMetric, height: PlatformView.noIntrinsicMetric)
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        finishNativeScrollRestoration()
        return super.accessibilityScroll(direction)
    }
    
    override func attributedText(in range: UITextRange) -> NSAttributedString {
        replaceAttachmentWithEquivalentText(
            in: super.attributedText(in: range)
        )
    }

    override func text(in range: UITextRange) -> String? {
        return attributedText(in: range).string
    }
    
    // TODO: It would be better to have a way to directly modify the copying item for each attachment. `NSItemProviderWriting` is not working here.
    override func copy(_ sender: Any?) {
        let rangeToCopy: UITextRange
        if let selected = selectedTextRange, !selected.isEmpty {
            rangeToCopy = selected
        } else if let documentRange = textRange(from: beginningOfDocument, to: endOfDocument) {
            rangeToCopy = documentRange
        } else {
            super.copy(sender)
            return
        }

        let attributedString = attributedText(in: rangeToCopy)
        UIPasteboard.general.setObjects([attributedString])
    }
}

#endif
