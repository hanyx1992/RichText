//
//  _TextView_AppKit.swift
//  RichText
//
//  Created by Yanan Li on 2025/8/24.
//

#if canImport(AppKit)
import SwiftUI

struct _TextView_AppKit: NSViewRepresentable {
    @Environment(\.richTextSelectionAction) private var selectionAction
    var content: TextContent
    var nativeScrollViewport: RichTextNativeScrollViewport?
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeNSView(context: Context) -> NSView {
        let textView = InlineAttachmentTextView(
            usingTextLayoutManager: nativeScrollViewport == nil && context.environment.usesTextLayoutManager
        )
        textView.drawsBackground = false
        textView.delegate = context.coordinator.self
        context.coordinator.textView = textView
        
        // Behavior
        textView.isEditable = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        
        // Sizing
        textView.textContainerInset = .zero
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineFragmentPadding = .zero
        }
        
        guard nativeScrollViewport != nil else { return textView }
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = textView
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled = false
        textView.viewportBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak textView] _ in
            MainActor.assumeIsolated {
                if let event = NSApp.currentEvent,
                   [.leftMouseDown, .leftMouseDragged, .scrollWheel, .keyDown].contains(event.type) {
                    textView?.pendingViewportOffset = nil
                }
                textView?.saveNativeScrollPosition()
                textView?.needsLayout = true
            }
        }
        textView.updateNativeScrollViewport(nativeScrollViewport)
        return scrollView
    }
    
    func updateNSView(_ view: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let position = textView.pendingViewportOffset ?? textView.nativeViewportRect.origin
        context.coordinator.parent = self
        textView.selectionAction = selectionAction
        textView.updateNativeScrollViewport(nativeScrollViewport)

        let configuration = TextViewRenderConfiguration(context: context)
        TextAttributeConverter.mergeRenderConfigurationIntoTextView(
            textView,
            configuration: configuration
        )
        let coordinator = context.coordinator
        if let version = nativeScrollViewport?.contentVersion,
           coordinator.contentVersion == version,
           coordinator.renderConfiguration == configuration,
           coordinator.isEnabled == context.environment.isEnabled { return }
        if nativeScrollViewport != nil, (textView.textStorage?.length ?? 0) > 0 {
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
    
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard nativeScrollViewport != nil else { return nil }
        return CGSize(width: proposal.width ?? nsView.bounds.width,
                      height: proposal.height ?? nsView.bounds.height)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        guard let textView = coordinator.textView else { return }
        textView.saveNativeScrollPosition()
        textView.isDismantled = true
        textView.delegate = nil
        if let observer = textView.viewportBoundsObserver { NotificationCenter.default.removeObserver(observer) }
        textView.viewportBoundsObserver = nil
        textView.viewportHeader?.view.removeFromSuperview()
        textView.viewportHeader = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: _TextView_AppKit
        weak var textView: InlineAttachmentTextView?
        var contentVersion: AnyHashable?
        var renderConfiguration: TextViewRenderConfiguration?
        var isEnabled: Bool?

        init(_ parent: _TextView_AppKit) {
            self.parent = parent
        }
    }
}
#endif
