import AppKit
import Combine

@MainActor
final class PlayerState: ObservableObject {
    static let shared = PlayerState()

    @Published var currentTrack: Track = .empty
    @Published var isPlaying: Bool = false
    @Published var progress: TimeInterval = 0
    @Published var queue: [Track] = []
    @Published var accentColor: NSColor = NSColor(red: 0.4, green: 0.3, blue: 0.8, alpha: 1)
    @Published var albumArtImage: NSImage? = nil
    /// The track id (`title|artist`) that `albumArtImage` belongs to.
    @Published var albumArtTrackID: String = ""
    @Published var authState: AuthState = .unauthenticated
    /// Set when the user skips; consumed when a new track is detected. 1 = next, -1 = prev.
    @Published var skipDirection: CGFloat? = nil
    /// Triggers an immediate slide-out animation when the user presses skip.
    @Published var skipExitDirection: CGFloat? = nil

    /// Spotify restarts the current track when previous is pressed after this many seconds.
    static let skipRestartThreshold: TimeInterval = 3

    /// Ignores contradictory Spotify poll updates briefly after local play/pause.
    private var playbackPollGraceUntil: Date?

    enum AuthState {
        case unauthenticated
        case authenticated
        case needsReauth
    }

    private init() {}

    func togglePlayingOptimistically() {
        isPlaying.toggle()
        playbackPollGraceUntil = Date().addingTimeInterval(1.5)
    }

    func applyPlaybackStateFromPoll(_ playing: Bool) {
        if let until = playbackPollGraceUntil, Date() < until, playing != isPlaying {
            return
        }
        if playing == isPlaying {
            playbackPollGraceUntil = nil
        }
        isPlaying = playing
    }

    func playQueueTrack(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let trackIDs = queue[index...].map(\.id)
        SpotifyWebAPI.shared.playTracks(trackIDs: Array(trackIDs))
    }

    func reorderQueue(draggedID: String, beforeID: String) {
        guard let from = queue.firstIndex(where: { $0.id == draggedID }),
              let to = queue.firstIndex(where: { $0.id == beforeID }),
              from != to else { return }

        var updated = queue
        let item = updated.remove(at: from)
        let destination = to > from ? to - 1 : to
        updated.insert(item, at: destination)
        queue = updated

        let resumeMs = Int(progress * 1000)
        SpotifyWebAPI.shared.syncUpcomingQueue(trackIDs: updated.map(\.id), resumePositionMs: resumeMs)
    }

    func requestSkip(direction: CGFloat) {
        if direction < 0 && progress > Self.skipRestartThreshold {
            AppleScriptBridge.previousTrack()
            PollingService.shared.refreshNow()
            return
        }
        let previousKey = currentTrack.id
        skipDirection = direction
        skipExitDirection = direction
        if direction > 0 { AppleScriptBridge.nextTrack() }
        else { AppleScriptBridge.previousTrack() }
        PollingService.shared.pollUntilTrackChanges(from: previousKey)
    }
}
