import AppKit

/// Restrained palette: values in the main text color, syntax in gray, one muted accent for results.
/// Sizes and the result color come from `Settings`.
enum Theme {
    private static var settings: Settings { .shared }

    static let horizontalInset: CGFloat = 32

    static var fontSize: CGFloat { CGFloat(settings.fontSize) }
    static var lineHeight: CGFloat { (fontSize * settings.lineSpacing.multiplier).rounded() }
    static var totalSpacing: CGFloat { (lineHeight * 0.4).rounded() }

    static var font: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular) }
    static var variableFont: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold) }
    static var resultFont: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular) }
    static var totalFont: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold) }

    static let text = NSColor.labelColor
    static let syntax = NSColor.secondaryLabelColor
    static let comment = NSColor.tertiaryLabelColor

    static var result: NSColor { settings.resultColor.color }

    static let currentLine = dynamic(
        light: NSColor(white: 0, alpha: 0.045),
        dark: NSColor(white: 1, alpha: 0.045)
    )
    /// Warm tint over the frosted glass; fully opaque when frosted glass is turned off.
    static var tint: NSColor {
        let alpha: CGFloat = settings.frostedGlass ? 0.72 : 1
        return dynamic(
            light: NSColor(srgbRed: 0.976, green: 0.972, blue: 0.96, alpha: alpha),
            dark: NSColor(srgbRed: 0.11, green: 0.105, blue: 0.10, alpha: alpha)
        )
    }
    /// Hairlines (total divider, footer). The system separatorColor nearly vanishes on the dark tint.
    static let divider = dynamic(
        light: NSColor(white: 0, alpha: 0.12),
        dark: NSColor(white: 1, alpha: 0.18)
    )
    static let scrollerKnob = dynamic(
        light: NSColor(white: 0, alpha: 0.22),
        dark: NSColor(white: 1, alpha: 0.24)
    )

    /// Fixed line height with the glyphs centered vertically.
    static func paragraphStyle(spacingBefore: CGFloat = 0, alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        p.paragraphSpacingBefore = spacingBefore
        p.alignment = alignment
        if alignment == .right { p.lineBreakMode = .byTruncatingHead }
        return p
    }

    static var baselineOffset: CGFloat {
        let f = font
        return (lineHeight - (f.ascender - f.descender)) / 2
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
