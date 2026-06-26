import SwiftUI
import AppKit

enum AppleTheme {
    static let popoverWidth: CGFloat = 272
    static let cdDiameter: CGFloat = 180
    static let menuBarIconSize: CGFloat = 18
    static let controlButtonSize: CGFloat = 22
    static let playButtonSize: CGFloat = 28
    static let progressBarHeight: CGFloat = 4
    static let scrubHandleSize: CGFloat = 10
    static let cornerRadius: CGFloat = 14
    static let pillCornerRadius: CGFloat = 20

    static let titleFont: Font = .headline
    static let artistFont: Font = .subheadline
    static let timestampFont: Font = .caption.monospacedDigit()
    static let queueRowFont: Font = .footnote

    static let primaryColor: Color = .primary
    static let secondaryColor: Color = .secondary
    static let progressTrackColor: Color = Color(NSColor.quaternaryLabelColor)
    static let controlBackgroundMaterial: Material = .ultraThin

    static let cdShadowRadius: CGFloat = 12
    static let cdShadowOpacity: CGFloat = 0.4

    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14

    // Window-level Apple backdrop tuning
    static let backdropBlurRadius: CGFloat = 44
    static let backdropSaturation: CGFloat = 1.72
    static let backdropBrightness: CGFloat = 0.06
    static let backdropContrast: CGFloat = 1.08

    struct BackdropGradientStops {
        let linear: [NSColor]
        let glow: NSColor
    }

    static func backdropGradientColors(from color: NSColor) -> BackdropGradientStops {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if s < 0.06 {
            let top = NSColor(white: 0.34, alpha: 1)
            let mid = NSColor(white: 0.22, alpha: 1)
            let bottom = NSColor(white: 0.12, alpha: 1)
            return BackdropGradientStops(linear: [bottom, mid, top], glow: NSColor(white: 0.55, alpha: 1))
        }

        let top = NSColor(
            hue: h,
            saturation: min(s * 1.22, 0.96),
            brightness: min(max(b * 0.78, 0.58), 0.78),
            alpha: 1
        )
        let mid = NSColor(
            hue: h,
            saturation: min(s * 1.05, 0.90),
            brightness: min(max(b * 0.56, 0.42), 0.58),
            alpha: 1
        )
        let bottom = NSColor(
            hue: h,
            saturation: min(s * 0.88, 0.82),
            brightness: min(max(b * 0.38, 0.26), 0.42),
            alpha: 1
        )
        let glow = NSColor(
            hue: h,
            saturation: min(s * 1.15, 0.94),
            brightness: min(max(b * 0.92, 0.72), 0.92),
            alpha: 1
        )
        return BackdropGradientStops(linear: [bottom, mid, top], glow: glow)
    }
}
