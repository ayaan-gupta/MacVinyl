import Foundation
import Combine

/// Single source-of-truth for the CD rotation angle.
/// Both the menu bar icon and the popover CD read from here so they're always in sync.
@MainActor
final class VinylSpinner: ObservableObject {
    static let shared = VinylSpinner()

    @Published var angleDegrees: Double = 0

    /// Set this to 120 (playing) or 0 (paused/near-end/transitioning).
    /// CDSpinner approaches it smoothly — setting to 0 causes natural deceleration.
    var targetDegreesPerSecond: Double = 0

    private var currentSpeed: Double = 0
    private let smoothing: Double = 0.07
    private var timer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        var last = DispatchTime.now()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(16))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = DispatchTime.now()
            let dt  = Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000_000
            last    = now
            let target = self.targetDegreesPerSecond
            self.currentSpeed = self.currentSpeed * (1 - self.smoothing) + target * self.smoothing
            let delta = self.currentSpeed * min(dt, 0.05)
            Task { @MainActor [weak self] in self?.angleDegrees += delta }
        }
        t.resume()
        timer = t
    }
}
