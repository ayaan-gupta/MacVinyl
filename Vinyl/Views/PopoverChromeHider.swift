import AppKit
import SwiftUI

/// Clears default NSPopover chrome so our window-level backdrop shows through.
/// Preserves Vinyl-owned backdrop views (glass layer included).
struct PopoverChromeHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.stripChrome(startingFrom: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.stripChrome(startingFrom: nsView) }
    }

    private static func stripChrome(startingFrom view: NSView) {
        guard let window = view.window else { return }

        window.isOpaque = false
        window.backgroundColor = .clear

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hidePopoverChrome(in: contentView)
    }

    private static func hidePopoverChrome(in view: NSView) {
        for subview in view.subviews {
            if subview.isVinylOwnedBackdrop { continue }

            if let effect = subview as? NSVisualEffectView {
                effect.isHidden = true
                effect.alphaValue = 0
            } else {
                let name = String(describing: type(of: subview))
                if name.contains("Popover") || name.contains("Frame") || name.contains("Border") {
                    subview.wantsLayer = true
                    subview.layer?.backgroundColor = NSColor.clear.cgColor
                }
                hidePopoverChrome(in: subview)
            }
        }
    }
}
