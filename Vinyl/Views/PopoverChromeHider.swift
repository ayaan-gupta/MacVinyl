import AppKit
import SwiftUI

/// Clears NSPopover window chrome so the SwiftUI background can show through.
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
        hideVisualEffects(in: contentView)
    }

    private static func hideVisualEffects(in view: NSView) {
        for subview in view.subviews {
            if let effect = subview as? NSVisualEffectView {
                effect.isHidden = true
                effect.alphaValue = 0
            } else {
                subview.wantsLayer = true
                subview.layer?.backgroundColor = NSColor.clear.cgColor
                hideVisualEffects(in: subview)
            }
        }
    }
}
