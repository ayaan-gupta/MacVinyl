import SwiftUI
import AppKit

extension View {
    /// Shows the macOS pointing-hand cursor while the pointer is over this view.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
