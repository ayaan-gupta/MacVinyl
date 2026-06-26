import SwiftUI

/// Tunable layout for the pixel turntable scene.
/// Edit these values in Xcode to align the record and tonearm — no other files needed.
enum PixelTurntableLayout {

    // MARK: Record

    /// Record diameter as a fraction of turntable width. Increase to make the vinyl bigger.
    static var recordDiameterScale: CGFloat = 0.6175

    /// Horizontal nudge from turntable center, as a fraction of turntable width.
    /// Negative = left, positive = right.
    static var recordOffsetXFraction: CGFloat = -0.10

    /// Vertical nudge from turntable center, as a fraction of turntable height.
    /// Negative = up, positive = down.
    static var recordOffsetYFraction: CGFloat = -0.01025

    /// Album-art hole size as a fraction of record diameter.
    static var artHoleScale: CGFloat = 0.36

    // MARK: Album art pixelation

    /// Number of visible pixel blocks across the album-art width.
    /// Lower = chunkier / more pixelated. Higher = sharper / less pixelated. Try 12–48.
    static var artPixelCount: Double = 38

    // MARK: Tonearm size

    /// Tonearm image height as a fraction of turntable height.
    static var tonearmHeightScale: CGFloat = 0.72

    // MARK: Tonearm pivot position (on the turntable)

    /// Pivot X from turntable center, as a fraction of turntable width.
    /// Positive = right of center.
    static var pivotXFraction: CGFloat = 0.32

    /// Pivot Y from turntable center, as a fraction of turntable height.
    /// Negative = above center, positive = below center.
    static var pivotYFraction: CGFloat = -0.28

    // MARK: Tonearm pivot anchor (on the tonearm image)

    /// Horizontal pivot point on the tonearm PNG (0 = left, 0.5 = center, 1 = right).
    static var tonearmPivotAnchorX: CGFloat = 0.5

    /// Vertical pivot point on the tonearm PNG (0 = top, 1 = bottom).
    static var tonearmPivotAnchorY: CGFloat = 0.2175

    // MARK: Tonearm rotation (degrees)

    /// Arm angle when paused (off the record).
    /// Increase to rotate clockwise; decrease for counter-clockwise.
    static var angleOff: Double = 8

    /// Arm angle when playing (on the record).
    static var angleOn: Double = 40

    // MARK: Tonearm wiggle (while playing)

    /// How many degrees the tonearm rocks back and forth on the record.
    static var wiggleDegrees: Double = 2.0

    /// Seconds for one full ping-pong cycle (there and back).
    static var wigglePeriod: Double = 5.0

    // MARK: Derived helpers (used by PixelTurntableView)

    static func turntableHeight(forWidth width: CGFloat) -> CGFloat {
        width * (659.0 / 869.0)
    }

    static func recordDiameter(forWidth width: CGFloat) -> CGFloat {
        width * recordDiameterScale
    }

    static func recordOffsetX(forWidth width: CGFloat) -> CGFloat {
        width * recordOffsetXFraction
    }

    static func recordOffsetY(forHeight height: CGFloat) -> CGFloat {
        height * recordOffsetYFraction
    }

    static func tonearmSize(forHeight ttHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let h = ttHeight * tonearmHeightScale
        let w = h * (169.0 / 566.0)
        return (w, h)
    }

    static func pivotPosition(width: CGFloat, ttHeight: CGFloat) -> (x: CGFloat, y: CGFloat) {
        (width * pivotXFraction, ttHeight * pivotYFraction)
    }

    static var tonearmPivotAnchor: UnitPoint {
        UnitPoint(x: tonearmPivotAnchorX, y: tonearmPivotAnchorY)
    }

    /// Offset that places the tonearm's pivot anchor at the turntable pivot point.
    static func tonearmOffset(
        tonearmWidth: CGFloat,
        tonearmHeight: CGFloat,
        turntableWidth: CGFloat,
        turntableHeight: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        let pivot = pivotPosition(width: turntableWidth, ttHeight: turntableHeight)
        let offsetX = pivot.x - (tonearmPivotAnchorX - 0.5) * tonearmWidth
        let offsetY = pivot.y - (tonearmPivotAnchorY - 0.5) * tonearmHeight
        return (offsetX, offsetY)
    }
}
