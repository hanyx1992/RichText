//
//  TextAttributeConverter.swift
//  RichText
//
//  Created by Yanan Li on 2025/10/11.
//

import CoreText
import SwiftUI

#if canImport(AppKit)
typealias ViewRepresentable = NSViewRepresentable
typealias RepresentableContext = NSViewRepresentableContext
typealias PlatformColor = NSColor
#elseif canImport(UIKit)
typealias ViewRepresentable = UIViewRepresentable
typealias RepresentableContext = UIViewRepresentableContext
typealias PlatformColor = UIColor
#endif

enum TextAttributeConverter {
    static func convertingAttributes(
        in attributedString: AttributedString,
        configuration: TextViewRenderConfiguration,
        reuseConvertedAttributes: Bool = false
    ) -> AttributedString {
        var result = attributedString
        #if canImport(UIKit)
        // This lookup lives only for this conversion with one fixed configuration.
        var convertedByInput: [AttributeContainer: AttributeContainer] = [:]
        #endif
        for run in attributedString.runs {
            var attributes = run.attributes
            #if canImport(UIKit)
            // Attachment equality may describe an ID rather than object identity.
            let canReuse = reuseConvertedAttributes && attributes.inlineHostingAttachment == nil
                && attributes.uiKit.attachment == nil
            if canReuse, let converted = convertedByInput[attributes] {
                result[run.range].setAttributes(converted)
                continue
            }
            #endif
            mergeEnvironmentValues(into: &attributes, configuration: configuration)
            mergeSwiftUIAttributes(into: &attributes, configuration: configuration)
            resolveInlinePresentationIntent(in: &attributes)
            #if canImport(UIKit)
            if canReuse {
                if let paragraphStyle = attributes.uiKit.paragraphStyle {
                    attributes.uiKit.paragraphStyle = paragraphStyle.copy() as! NSParagraphStyle
                }
                convertedByInput[run.attributes] = attributes
            }
            #endif
            result[run.range].setAttributes(attributes)
        }
        return result
    }

    private static func mergeEnvironmentValues(
        into attributes: inout AttributeContainer,
        configuration: TextViewRenderConfiguration
    ) {
        if let defaultFont = configuration.defaultFont {
            attributes.merge(AttributeContainer([.font : defaultFont]), mergePolicy: .keepCurrent)
        }

        attributes.mergeParagraphStyle(mergePolicy: .keepNew) { paragraphStyle in
            paragraphStyle.alignment = NSTextAlignment(
                configuration.multilineTextAlignment,
                layoutDirection: configuration.layoutDirection
            )
            paragraphStyle.lineSpacing = configuration.lineSpacing
            paragraphStyle.allowsDefaultTighteningForTruncation = configuration.allowsTightening
            paragraphStyle.baseWritingDirection = NSWritingDirection(configuration.layoutDirection)
            paragraphStyle.lineBreakMode = NSLineBreakMode(
                configuration.truncationMode,
                lineLimit: configuration.lineLimit
            )
            if let lineHeightSetting = configuration.lineHeightSetting {
                paragraphStyle.minimumLineHeight = lineHeightSetting.minimum
                paragraphStyle.maximumLineHeight = lineHeightSetting.maximum
                paragraphStyle.lineHeightMultiple = lineHeightSetting.multiple
            }
            if configuration.minimumLineHeight > 0 {
                paragraphStyle.minimumLineHeight = configuration.minimumLineHeight
            }
        }

    }

    private static func mergeSwiftUIAttributes(
        into attributes: inout AttributeContainer,
        configuration: TextViewRenderConfiguration
    ) {
        let swiftUIAttributes = attributes.swiftUI
        var convertedAttributes: [NSAttributedString.Key : Any] = [:]

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *),
           let font = swiftUIAttributes.font {
            let platformFont = font
                .resolve(in: configuration.fontResolutionContext)
                .ctFont as PlatformFont
            convertedAttributes[.font] = platformFont
        }

        if let underlineStyle = swiftUIAttributes.underlineStyle {
            convertedAttributes[.underlineStyle] = NSNumber(
                value: NSUnderlineStyle(underlineStyle).rawValue
            )
            convertedAttributes[.underlineColor] = underlineStyle.color.map(PlatformColor.init(_:))
        }
        if let strikethroughStyle = swiftUIAttributes.strikethroughStyle {
            convertedAttributes[.strikethroughStyle] = NSNumber(
                value: NSUnderlineStyle(strikethroughStyle).rawValue
            )
            convertedAttributes[.strikethroughColor] = strikethroughStyle.color.map(PlatformColor.init(_:))
        }
        convertedAttributes[.foregroundColor] = swiftUIAttributes.foregroundColor.map(PlatformColor.init(_:))
        convertedAttributes[.backgroundColor] = swiftUIAttributes.backgroundColor.map(PlatformColor.init(_:))
        convertedAttributes[.kern] = swiftUIAttributes.kern
        convertedAttributes[.tracking] = swiftUIAttributes.tracking
        convertedAttributes[.baselineOffset] = swiftUIAttributes.baselineOffset

        attributes.merge(
            AttributeContainer(convertedAttributes)
        )
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *),
           let lineHeight = swiftUIAttributes.lineHeight {
            let lineHeightSetting = lineHeight._richTextLineHeightSetting(
                font: convertedAttributes[.font] as? PlatformFont
            )
            attributes.mergeParagraphStyle(mergePolicy: .keepCurrent) { paragraphStyle in
                paragraphStyle.minimumLineHeight = lineHeightSetting.minimum
                paragraphStyle.maximumLineHeight = lineHeightSetting.maximum
                paragraphStyle.lineHeightMultiple = lineHeightSetting.multiple
            }
        }

    }

    private static func resolveInlinePresentationIntent(
        in attributes: inout AttributeContainer
    ) {
        let intent = attributes.inlinePresentationIntent
        guard let intent else { return }

        var resolvedAttributes = AttributeContainer()
        if intent.contains(.strikethrough) {
            #if canImport(AppKit)
            resolvedAttributes.appKit.strikethroughStyle = .single
            #elseif canImport(UIKit)
            resolvedAttributes.uiKit.strikethroughStyle = .single
            #endif
        }

        #if canImport(UIKit)
        if let font = attributes.uiKit.font {
            let ctFont: CTFont = font
            resolvedAttributes.uiKit.font = ctFont.applyingInlinePresentationIntent(intent)
        }
        #endif

        attributes.merge(resolvedAttributes)
    }

    @MainActor
    static func mergeRenderConfigurationIntoTextView(
        _ textView: PlatformTextView,
        configuration: TextViewRenderConfiguration
    ) {
        #if canImport(AppKit)
        textView.baseWritingDirection = NSWritingDirection(configuration.layoutDirection)
        textView.alignment = NSTextAlignment(
            configuration.multilineTextAlignment,
            layoutDirection: configuration.layoutDirection
        )
        textView.isAutomaticSpellingCorrectionEnabled = !configuration.isAutocorrectionDisabled
        #elseif canImport(UIKit)
        /* UITextView does not respect to any properties set to that view since its backed storage is an `AttributedString` */
        #endif

        let textContainer: NSTextContainer? = textView.textContainer
        if let textContainer {
            if updateTextContainer(textContainer, configuration: configuration) {
                (textView as? InlineAttachmentTextView)?._invalidateTextLayout()
            }
        }
    }

    private static func updateTextContainer(
        _ textContainer: NSTextContainer,
        configuration: TextViewRenderConfiguration
    ) -> Bool {
        let lineLimit = configuration.lineLimit ?? 0
        let lineBreakMode = NSLineBreakMode(
            configuration.truncationMode,
            lineLimit: lineLimit
        )
        let changed = textContainer.maximumNumberOfLines != lineLimit
            || textContainer.lineBreakMode != lineBreakMode
        if textContainer.maximumNumberOfLines != lineLimit {
            textContainer.maximumNumberOfLines = lineLimit
        }
        if textContainer.lineBreakMode != lineBreakMode {
            textContainer.lineBreakMode = lineBreakMode
        }
        return changed
    }
}

// MARK: - Auxiliary

fileprivate extension CTFont {
    func applyingInlinePresentationIntent(_ intent: InlinePresentationIntent) -> CTFont {
        var symbolicTraits: [CTFontSymbolicTraits] = []

        if intent.contains(.code) {
            symbolicTraits.append(.traitMonoSpace)
        }
        if intent.contains(.stronglyEmphasized) {
            symbolicTraits.append(.traitBold)
        }
        if intent.contains(.emphasized) {
            symbolicTraits.append(.traitItalic)
        }

        var resolvedFont = CTFontCreateCopyWithAttributes(
            self,
            0, // keep size
            nil, // no transform
            nil // same descriptor
        )
        for trait in symbolicTraits {
            let existingTraits = CTFontGetSymbolicTraits(resolvedFont)
            guard !existingTraits.contains(trait) else { continue }

            guard let updatedFont = CTFontCreateCopyWithSymbolicTraits(
                resolvedFont,
                0,
                nil,
                existingTraits.union(trait),
                trait
            ) else {
                continue
            }

            resolvedFont = updatedFont
        }

        return resolvedFont
    }
}
