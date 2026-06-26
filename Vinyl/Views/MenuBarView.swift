import AppKit
import Combine

final class SpinningMenuBarView: NSView {
    // Root layer never transforms — only cdLayer rotates to avoid the orbit bug.
    private let cdLayer    = CALayer()
    private let imageLayer = CALayer()
    private let holeLayer  = CALayer()

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let root = layer, cdLayer.superlayer == nil else { return }

        root.masksToBounds = false

        cdLayer.frame        = bounds
        cdLayer.anchorPoint  = CGPoint(x: 0.5, y: 0.5)
        cdLayer.masksToBounds = true
        cdLayer.cornerRadius  = bounds.width / 2
        root.addSublayer(cdLayer)

        imageLayer.frame           = cdLayer.bounds
        imageLayer.cornerRadius    = cdLayer.cornerRadius
        imageLayer.masksToBounds   = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        cdLayer.addSublayer(imageLayer)

        let h: CGFloat = 3.5
        holeLayer.frame           = CGRect(x: bounds.midX - h/2, y: bounds.midY - h/2, width: h, height: h)
        holeLayer.cornerRadius    = h / 2
        holeLayer.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        cdLayer.addSublayer(holeLayer)
    }

    override func layout() {
        super.layout()
        guard cdLayer.superlayer != nil else { return }
        let r = bounds.width / 2
        cdLayer.frame        = bounds
        cdLayer.cornerRadius = r
        imageLayer.frame     = cdLayer.bounds
        imageLayer.cornerRadius = r
        let h: CGFloat = 3.5
        holeLayer.frame = CGRect(x: bounds.midX - h/2, y: bounds.midY - h/2, width: h, height: h)
    }

    func updateImage(_ image: NSImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.backgroundColor = (image == nil ? NSColor.tertiaryLabelColor : .clear).cgColor
        CATransaction.commit()
    }

    /// Apply a rotation angle (degrees) from VinylSpinner.shared.
    func applyAngle(_ degrees: Double) {
        let rad = degrees * .pi / 180.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Negative to spin clockwise (macOS CG coordinate system has y-axis up)
        cdLayer.transform = CATransform3DMakeRotation(-rad, 0, 0, 1)
        CATransaction.commit()
    }
}

// MARK: - Coordinator

final class MenuBarIconCoordinator: NSObject {
    let hostView: SpinningMenuBarView
    private var cancellables = Set<AnyCancellable>()

    init(size: CGFloat) {
        hostView = SpinningMenuBarView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        super.init()

        // Album art
        PlayerState.shared.$albumArtImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] img in self?.hostView.updateImage(img) }
            .store(in: &cancellables)

        // Angle — driven by VinylSpinner.shared so it's identical to the popover CD
        VinylSpinner.shared.$angleDegrees
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deg in self?.hostView.applyAngle(deg) }
            .store(in: &cancellables)
    }

    func sync() {
        hostView.updateImage(PlayerState.shared.albumArtImage)
        hostView.applyAngle(VinylSpinner.shared.angleDegrees)
    }
}

extension Notification.Name {
    static let playerStateDidChange = Notification.Name("playerStateDidChange")
}
