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
}
