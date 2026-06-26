import SwiftUI
import AppKit

/// Pixel-theme styling only. Do not use these fonts outside `theme == .pixel` branches.
enum PixelTheme {
    static let popoverWidth: CGFloat = 320
    static let cdDiameter: CGFloat = 180
    static let menuBarIconSize: CGFloat = 18
    static let cornerRadius: CGFloat = 0
    static let contentPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12

    static let titleFont: Font = Font.custom("PixelifySans-Regular", size: 12).weight(.bold)
    static let artistFont: Font = Font.custom("PixelifySans-Regular", size: 11)
    static let timestampFont: Font = Font.custom("PixelifySans-Regular", size: 10)
    static let queueRowFont: Font = Font.custom("PixelifySans-Regular", size: 10)

    static let primaryTextColor: Color = Color(red: 0.95, green: 0.88, blue: 0.72, alpha: 1)
    static let secondaryTextColor: Color = Color(red: 0.72, green: 0.65, blue: 0.50, alpha: 1)
    static let progressTrackColor: Color = Color(red: 0.28, green: 0.22, blue: 0.15, alpha: 1)
    static let progressFillColor: Color = Color(red: 0.56, green: 0.78, blue: 0.40, alpha: 1)
    static let accentColor: Color = Color(red: 0.56, green: 0.78, blue: 0.40, alpha: 1)
    static let rowBackgroundColor: Color = Color(red: 0.20, green: 0.16, blue: 0.10, alpha: 0.6)

    static let controlButtonSize: CGFloat = 40
    static let playButtonSize: CGFloat = 52
    static let topBarIconHeight: CGFloat = 22

    /// Vertical space reserved for the floated queue/settings icons above the turntable.
    static let topBarClearance: CGFloat = 38

    /// Fallback queue strip height until the open layout is measured once.
    static let estimatedQueueSectionHeight: CGFloat = 120
}

extension Color {
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(NSColor(red: red, green: green, blue: blue, alpha: alpha))
    }
}
