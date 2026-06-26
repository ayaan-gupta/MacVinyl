import AppKit
import SwiftUI

/// Clears default NSPopover window chrome so the SwiftUI background shows through.
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
        clearChrome(in: contentView)
    }

    private static func clearChrome(in view: NSView) {
        for subview in view.subviews {
            if let effect = subview as? NSVisualEffectView {
                if effect.containsSwiftUIHosting {
                    effect.isHidden = false
                    effect.alphaValue = 1
                    effect.material = .underWindowBackground
                    effect.blendingMode = .behindWindow
                    effect.wantsLayer = true
                    effect.layer?.backgroundColor = NSColor.clear.cgColor
                } else {
                    effect.isHidden = true
                    effect.alphaValue = 0
                }
                continue
            }

            let name = String(describing: type(of: subview))
            if name.contains("Popover") || name.contains("Frame") || name.contains("Border") {
                subview.wantsLayer = true
                subview.layer?.backgroundColor = NSColor.clear.cgColor
            }
            clearChrome(in: subview)
        }
    }
}

private extension NSView {
    var containsSwiftUIHosting: Bool {
        if String(describing: type(of: self)).contains("Hosting") { return true }
        return subviews.contains { $0.containsSwiftUIHosting }
    }
}
