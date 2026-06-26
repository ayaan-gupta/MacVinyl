import AppKit
import Foundation

final class PollingService {
    static let shared = PollingService()

    private var pollTimer: DispatchSourceTimer?
    private var tickCount = 0
    private var lastTrackKey: String = ""
    private var pendingQueueFetch: DispatchWorkItem?
    private var skipPollGeneration = 0
    private var isQueueFetchInFlight = false
    private var lastQueueFetchAt: Date = .distantPast

    private init() {}

    func start() {
        guard pollTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        pollTimer = t
        ProgressInterpolator.shared.start()
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        ProgressInterpolator.shared.stop()
    }

    func refreshNow() {
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.fetchFullState() }
    }

    func refreshQueueNow() {
        performQueueFetch(force: true)
    }

    /// Rapidly polls Spotify until the track identity changes (after skip).
    func pollUntilTrackChanges(from previousKey: String) {
        skipPollGeneration += 1
        let generation = skipPollGeneration
        attemptTrackChange(excluding: previousKey, generation: generation, attempt: 0)
    }

    private func attemptTrackChange(excluding previousKey: String, generation: Int, attempt: Int) {
        guard generation == skipPollGeneration, attempt < 40 else { return }

        AppleScriptBridge.fetchTrackInfo { [weak self] info in
            guard let self, generation == self.skipPollGeneration else { return }
            guard let info else { return }

            let key = "\(info.title)|\(info.artist)"
            if key != previousKey {
                self.lastTrackKey = key
                self.publishTrackInfo(info, key: key, trackChanged: true)
                return
            }

            let delay = attempt < 8 ? 0.05 : 0.1
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                self.attemptTrackChange(excluding: previousKey, generation: generation, attempt: attempt + 1)
            }
        }
    }

    private func tick() {
        tickCount += 1
        fetchPosition()
        if tickCount % 3 == 0 { fetchFullState() }
        if tickCount % 16 == 0, SpotifyWebAPI.shared.isAuthenticated {
            performQueueFetch(force: false)
        }
    }

    private func fetchPosition() {
        AppleScriptBridge.fetchPosition { pos in
            guard let pos else { return }
            ProgressInterpolator.shared.sync(to: pos)
        }
    }

    private func fetchFullState() {
        AppleScriptBridge.fetchPlayerState { state in
            DispatchQueue.main.async {
                switch state {
                case .playing:  PlayerState.shared.applyPlaybackStateFromPoll(true)
                default:        PlayerState.shared.applyPlaybackStateFromPoll(false)
                }
            }
        }

        AppleScriptBridge.fetchTrackInfo { [weak self] info in
            guard let self, let info else { return }
            let key = "\(info.title)|\(info.artist)"
            let trackChanged = key != self.lastTrackKey
            self.lastTrackKey = key
            self.publishTrackInfo(info, key: key, trackChanged: trackChanged)
        }
    }

    private func publishTrackInfo(_ info: AppleScriptBridge.TrackInfo, key: String, trackChanged: Bool) {
        DispatchQueue.main.async {
            let state = PlayerState.shared

            let updated = Track(
                id: key,
                title: info.title,
                artist: info.artist,
                albumArtURL: info.artworkURL ?? (trackChanged ? nil : state.currentTrack.albumArtURL),
                duration: info.durationSeconds
            )
            if state.currentTrack != updated {
                state.currentTrack = updated
            }

            if trackChanged {
                state.progress = 0

                if let artURL = info.artworkURL {
                    if let cached = AlbumArtLoader.shared.image(for: artURL) {
                        state.albumArtTrackID = key
                        state.albumArtImage = cached
                    }
                    AlbumArtLoader.shared.load(trackID: key, url: artURL)
                }

                if SpotifyWebAPI.shared.isAuthenticated {
                    self.performQueueFetch(force: true)
                }
            }

            if SpotifyWebAPI.shared.isAuthenticated {
                self.refreshTrackMetadataFromAPI(fallbackTrackKey: key, trackChanged: trackChanged)
            }
        }
    }

    private func refreshTrackMetadataFromAPI(fallbackTrackKey: String, trackChanged: Bool) {
        SpotifyWebAPI.shared.fetchCurrentlyPlaying { track, artURL in
            let state = PlayerState.shared
            if trackChanged, let track {
                let merged = Track(
                    id: fallbackTrackKey,
                    title: track.title,
                    artist: track.artist,
                    albumArtURL: track.albumArtURL ?? state.currentTrack.albumArtURL,
                    duration: track.duration
                )
                if state.currentTrack != merged { state.currentTrack = merged }
            }
            if let artURL {
                AlbumArtLoader.shared.load(trackID: fallbackTrackKey, url: artURL)
            }
        }
    }

    private func performQueueFetch(force: Bool) {
        guard SpotifyWebAPI.shared.isAuthenticated else { return }
        guard !isQueueFetchInFlight else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastQueueFetchAt) < 3 { return }

        isQueueFetchInFlight = true
        SpotifyWebAPI.shared.fetchQueue { tracks in
            DispatchQueue.main.async {
                PlayerState.shared.queue = tracks
                self.isQueueFetchInFlight = false
                self.lastQueueFetchAt = Date()
            }
        }
    }
}
