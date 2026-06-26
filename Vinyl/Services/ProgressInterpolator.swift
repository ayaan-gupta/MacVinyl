import Foundation

final class ProgressInterpolator {
    static let shared = ProgressInterpolator()

    // Set true while the user is dragging the scrub handle.
    // Guards both the 16ms tick and position syncs from polling so they
    // don't fight the scrub position.
    var isScrubbing = false

    private var timer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(16))
        t.setEventHandler {
            DispatchQueue.main.async {
                guard !ProgressInterpolator.shared.isScrubbing else { return }
                let state = PlayerState.shared
                guard state.isPlaying else { return }
                let next = state.progress + 0.016
                if next <= state.currentTrack.duration { state.progress = next }
            }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func sync(to position: TimeInterval) {
        DispatchQueue.main.async {
            guard !ProgressInterpolator.shared.isScrubbing else { return }
            PlayerState.shared.progress = position
        }
    }
}
