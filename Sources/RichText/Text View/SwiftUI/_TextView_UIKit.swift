//
//  _TextView_UIKit.swift
//  RichText
//
//  Created by Yanan Li on 2025/10/4.
//

#if canImport(UIKit)
import SwiftUI

struct _TextView_UIKit: UIViewRepresentable {
    @Environment(\.richTextSelectionAction) private var selectionAction
    var content: TextContent
    var nativeScrollViewport: RichTextNativeScrollViewport?
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIView(context: Context) -> InlineAttachmentTextView {
        let textView = InlineAttachmentTextView(
            usingTextLayoutManager: nativeScrollViewport == nil && context.environment.usesTextLayoutManager
        )
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textDragDelegate = context.coordinator
        context.coordinator.textView = textView
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        
        textView.textContainer.lineFragmentPadding = .zero
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.updateNativeScrollViewport(nativeScrollViewport)
        
        return textView
    }
    
    func updateUIView(_ textView: InlineAttachmentTextView, context: Context) {
        let position = textView.pendingViewportOffset ?? textView.contentOffset
        context.coordinator.parent = self
        textView.selectionAction = selectionAction
        textView.updateNativeScrollViewport(nativeScrollViewport)
        if nativeScrollViewport != nil {
            textView.isScrollEnabled = context.environment.isEnabled
            textView.isUserInteractionEnabled = context.environment.isEnabled
        }

        let configuration = TextViewRenderConfiguration(context: context)
        TextAttributeConverter.mergeRenderConfigurationIntoTextView(
            textView,
            configuration: configuration
        )
        let coordinator = context.coordinator
        if let version = nativeScrollViewport?.contentVersion,
           coordinator.contentVersion == version,
           coordinator.renderConfiguration == configuration,
           coordinator.isEnabled == context.environment.isEnabled {
            return
        }
        if nativeScrollViewport != nil, textView.textStorage.length > 0,
           !textView.isTracking, !textView.isDragging, !textView.isDecelerating {
            textView.pendingViewportOffset = position
        }
        if textView.applyAttributedStringPreservingAttachments(
            content.attributedString(configuration: configuration,
                                     reuseConvertedAttributes: nativeScrollViewport != nil)
        ) {
            coordinator.contentVersion = nativeScrollViewport?.contentVersion
            coordinator.renderConfiguration = configuration
            coordinator.isEnabled = context.environment.isEnabled
        }
    }
    
    // For UITextView, it comes with a UIScrollView
    //
    // Since we have override `intrinsticContentSize` and disabled scrolling, it should act like a normal UIView
    //
    // For better control of SwiftUI View size when place it inside a ScrollView, we use `sizeThatFits` to explicitly calculate a size in SwiftUI.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: InlineAttachmentTextView,
        context: Context
    ) -> CGSize? {
        if nativeScrollViewport != nil {
            return CGSize(width: proposal.width ?? uiView.bounds.width,
                          height: proposal.height ?? uiView.bounds.height)
        }
        return uiView.measuredSizeThatFits(
            proposal.replacingUnspecifiedDimensions(
                by: CGSize(
                    width: UIView.noIntrinsicMetric,
                    height: UIView.noIntrinsicMetric
                )
            )
        )
    }
    
    final class Coordinator: NSObject, UITextViewDelegate, UITextDragDelegate {
        var parent: _TextView_UIKit
        weak var textView: InlineAttachmentTextView?
        var editMenuInteraction: UIEditMenuInteraction?
        var contentVersion: AnyHashable?
        var renderConfiguration: TextViewRenderConfiguration?
        var isEnabled: Bool?
        
        init(_ parent: _TextView_UIKit) {
            self.parent = parent
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            textView?.saveNativeScrollPosition()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            textView?.finishNativeScrollRestoration()
        }

        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            textView?.finishNativeScrollRestoration()
            textView?.prepareNativeScrollLayout(in: CGRect(origin: .zero, size: scrollView.bounds.size))
            return true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 {
                self.textView?.finishNativeScrollRestoration()
            }
        }
        
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let view = textView as? InlineAttachmentTextView,
                  let action = view.selectionAction,
                  let selection = view.selectionSnapshot(in: range) else { return nil }
            let item = UIAction(title: action.title) { _ in action.perform(selection) }
            return UIMenu(children: [item] + suggestedActions)
        }

        func textDraggableView(
            _ textDraggableView: UIView & UITextDraggable,
            itemsForDrag dragRequest: UITextDragRequest
        ) -> [UIDragItem] {
            guard let textView = textDraggableView as? InlineAttachmentTextView else {
                return dragRequest.suggestedItems
            }

            if textView.containsInlineAttachment(in: dragRequest.dragRange) {
                return []
            } else {
                return dragRequest.suggestedItems
            }
        }
    }

    static func dismantleUIView(_ uiView: InlineAttachmentTextView, coordinator: Coordinator) {
        uiView.isDismantled = true
        uiView.saveNativeScrollPosition()
        uiView.delegate = nil
        uiView.textDragDelegate = nil
        uiView.viewportHeader?.view.removeFromSuperview()
        uiView.viewportHeader = nil
    }
}

private extension InlineAttachmentTextView {
    func containsInlineAttachment(in textRange: UITextRange) -> Bool {
        let rangeStart = offset(from: beginningOfDocument, to: textRange.start)
        let rangeEnd = offset(from: beginningOfDocument, to: textRange.end)
        guard rangeStart >= 0,
              rangeEnd >= rangeStart else {
            return false
        }

        let range = NSRange(location: rangeStart, length: rangeEnd - rangeStart)
        guard range.length > 0,
              NSMaxRange(range) <= attributedText.length else {
            return false
        }

        var containsInlineAttachment = false
        attributedText.enumerateAttributes(in: range) { attributes, _, stop in
            if attributes[.inlineHostingAttachment] is InlineHostingAttachment ||
                attributes[.attachment] is InlineHostingAttachment {
                containsInlineAttachment = true
                stop.pointee = true
            }
        }

        return containsInlineAttachment
    }
}
#endif
