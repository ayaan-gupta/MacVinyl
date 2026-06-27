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

@MainActor
final class MenuBarIconCoordinator: NSObject {
    let hostView: SpinningMenuBarView
    private var cancellables = Set<AnyCancellable>()

    init(size: CGFloat) {
        hostView = SpinningMenuBarView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        super.init()

        // Album art — only show when it matches the current track
        Publishers.CombineLatest3(
            PlayerState.shared.$albumArtImage,
            PlayerState.shared.$albumArtTrackID,
            PlayerState.shared.$currentTrack
        )
        .receive(on: DispatchQueue.main)
        .map { img, artID, track in artID == track.id ? img : nil }
        .sink { [weak self] img in self?.hostView.updateImage(img) }
        .store(in: &cancellables)

        // Angle — driven by VinylSpinner.shared so it's identical to the popover CD
        VinylSpinner.shared.$angleDegrees
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deg in self?.hostView.applyAngle(deg) }
            .store(in: &cancellables)
    }

    func sync() {
        let state = PlayerState.shared
        let img = state.albumArtTrackID == state.currentTrack.id ? state.albumArtImage : nil
        hostView.updateImage(img)
        hostView.applyAngle(VinylSpinner.shared.angleDegrees)
    }
}

extension Notification.Name {
    static let playerStateDidChange = Notification.Name("playerStateDidChange")
}
