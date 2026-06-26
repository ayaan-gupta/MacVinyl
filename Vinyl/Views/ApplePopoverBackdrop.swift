import AppKit
import SwiftUI

// MARK: - SwiftUI hook

/// Installs a full-window backdrop behind all SwiftUI content. Sizing is driven
/// by the popover window, not measured content — so there is no uncovered strip
/// at the top where AppKit chrome used to show through.
struct ApplePopoverWindowBackdrop: NSViewRepresentable {
    let accent: NSColor
    let image: NSImage?

    func makeNSView(context: Context) -> ApplePopoverBackdropInstaller {
        ApplePopoverBackdropInstaller()
    }

    func updateNSView(_ installer: ApplePopoverBackdropInstaller, context: Context) {
        installer.sync(accent: accent, image: image)
    }
}

// MARK: - Installer

final class ApplePopoverBackdropInstaller: NSView {
    private weak var backdrop: ApplePopoverBackdropView?

    private var accent: NSColor = .gray
    private var artImage: NSImage?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installIfNeeded()
        } else {
            teardownBackdrop()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            teardownBackdrop()
        }
    }

    override func layout() {
        super.layout()
        sync(accent: accent, image: artImage)
    }

    func sync(accent: NSColor, image: NSImage?) {
        self.accent = accent
        self.artImage = image
        installIfNeeded()
        backdrop?.update(accent: accent, image: image)
        backdrop?.frame = window?.contentView?.bounds ?? .zero
    }

    private func installIfNeeded() {
        guard let contentView = window?.contentView else { return }
        if backdrop == nil {
            let view = ApplePopoverBackdropView(frame: contentView.bounds)
            view.identifier = NSUserInterfaceItemIdentifier("vinyl.apple.backdrop")
            view.autoresizingMask = [.width, .height]
            contentView.addSubview(view, positioned: .below, relativeTo: nil)
            backdrop = view
        }
        backdrop?.frame = contentView.bounds
    }

    private func teardownBackdrop() {
        backdrop?.removeFromSuperview()
        backdrop = nil
    }
}

// MARK: - Backdrop

final class ApplePopoverBackdropView: NSView {
    private static let ciContext = CIContext(options: nil)
    private static let artQueue = DispatchQueue(label: "vinyl.apple.backdrop.art", qos: .userInitiated)

    private let artLayer = CALayer()
    private let accentGradient = CAGradientLayer()
    private let glowGradient = CAGradientLayer()
    private let scrimLayer = CALayer()
    private let glassView = NSVisualEffectView()

    private var accent: NSColor = .gray
    private var artToken = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = AppleTheme.cornerRadius
        layer?.cornerCurve = .continuous

        artLayer.contentsGravity = .resizeAspectFill
        artLayer.masksToBounds = true
        layer?.addSublayer(artLayer)

        accentGradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        accentGradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        accentGradient.locations = [0, 0.45, 1]
        layer?.addSublayer(accentGradient)

        glowGradient.type = .radial
        glowGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        glowGradient.endPoint = CGPoint(x: 0.5, y: 0.85)
        glowGradient.locations = [0, 0.55, 1]
        layer?.addSublayer(glowGradient)

        scrimLayer.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        layer?.addSublayer(scrimLayer)

        glassView.material = .hudWindow
        glassView.blendingMode = .withinWindow
        glassView.state = .active
        glassView.identifier = NSUserInterfaceItemIdentifier("vinyl.apple.glass")
        glassView.alphaValue = 0.44
        glassView.wantsLayer = true
        glassView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        addSubview(glassView)
    }

    override func layout() {
        super.layout()
        let b = bounds
        artLayer.frame = b
        accentGradient.frame = b
        glowGradient.frame = b
        scrimLayer.frame = b
        glassView.frame = b
    }

    func update(accent: NSColor, image: NSImage?) {
        let accentChanged = !self.accent.isEqual(accent)
        self.accent = accent

        if accentChanged {
            applyAccentGradient()
        }

        let token = UUID()
        artToken = token

        guard let image else {
            artLayer.contents = nil
            artLayer.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
            applyAccentGradient()
            return
        }

        artLayer.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        let accentSnapshot = accent

        Self.artQueue.async { [weak self] in
            let processed = Self.processedArt(from: image)
            DispatchQueue.main.async {
                guard let self, self.artToken == token else { return }
                self.artLayer.contents = processed
                if accentChanged || processed != nil {
                    self.accent = accentSnapshot
                    self.applyAccentGradient()
                }
            }
        }
    }

    private func applyAccentGradient() {
        let stops = AppleTheme.backdropGradientColors(from: accent)
        accentGradient.colors = stops.linear.map(\.cgColor)
        accentGradient.opacity = artLayer.contents == nil ? 0.82 : 0.62

        glowGradient.colors = [
            stops.glow.withAlphaComponent(0.38).cgColor,
            stops.glow.withAlphaComponent(0.14).cgColor,
            NSColor.clear.cgColor
        ]
    }

    private static func processedArt(from image: NSImage) -> CGImage? {
        guard let tiff = image.tiffRepresentation,
              let input = CIImage(data: tiff) else { return nil }

        let extent = input.extent
        var output = input

        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(output.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(AppleTheme.backdropBlurRadius, forKey: kCIInputRadiusKey)
            if let blurred = blur.outputImage?.cropped(to: extent) {
                output = blurred
            }
        }

        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(output, forKey: kCIInputImageKey)
            controls.setValue(AppleTheme.backdropSaturation, forKey: kCIInputSaturationKey)
            controls.setValue(AppleTheme.backdropBrightness, forKey: kCIInputBrightnessKey)
            controls.setValue(AppleTheme.backdropContrast, forKey: kCIInputContrastKey)
            if let adjusted = controls.outputImage {
                output = adjusted
            }
        }

        return ciContext.createCGImage(output, from: extent)
    }
}

// MARK: - Chrome preservation

extension NSView {
    var isVinylOwnedBackdrop: Bool {
        if identifier?.rawValue.hasPrefix("vinyl.") == true { return true }
        var ancestor: NSView? = superview
        while let view = ancestor {
            if view.identifier?.rawValue.hasPrefix("vinyl.") == true { return true }
            ancestor = view.superview
        }
        return false
    }
}
