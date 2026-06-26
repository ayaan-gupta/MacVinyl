import AppKit
import Foundation
import Combine

// MARK: - Configuration
// Replace with your Spotify Developer app credentials:
// https://developer.spotify.com/dashboard
private let kClientID     = "REDACTED_CLIENT_ID"
private let kClientSecret = "REDACTED_CLIENT_SECRET"
private let kRedirectURI  = "vinyl://callback"
private let kScopes       = "user-read-playback-state user-read-currently-playing user-read-recently-played user-modify-playback-state"

// MARK: - Codable models

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

private struct CurrentlyPlayingResponse: Decodable {
    let item: PlayableItem?
    let is_playing: Bool?
}

private struct QueueResponse: Decodable {
    let currently_playing: PlayableItem?
    let queue: [PlayableItem]
}

private struct PlayableItem: Decodable {
    let id: String
    let name: String
    let duration_ms: Int
    let artists: [SpotifyArtist]?
    let album: SpotifyAlbum?
    let images: [SpotifyImage]?
    let show: SpotifyShow?

    func toTrack() -> Track {
        let artistName: String
        if let artists, !artists.isEmpty {
            artistName = artists.map(\.name).joined(separator: ", ")
        } else if let showName = show?.name, !showName.isEmpty {
            artistName = showName
        } else {
            artistName = ""
        }

        let artURL = Self.bestArtURL(albumImages: album?.images, itemImages: images)
        return Track(
            id: id,
            title: name,
            artist: artistName,
            albumArtURL: artURL,
            duration: TimeInterval(duration_ms) / 1000
        )
    }

    private static func bestArtURL(albumImages: [SpotifyImage]?, itemImages: [SpotifyImage]?) -> URL? {
        let images = albumImages ?? itemImages ?? []
        return images
            .sorted { ($0.width ?? 0) > ($1.width ?? 0) }
            .first
            .flatMap { URL(string: $0.url) }
    }
}

private struct SpotifyShow: Decodable {
    let name: String?
}

private struct DevicesResponse: Decodable {
    let devices: [SpotifyDevice]
}

private struct SpotifyDevice: Decodable {
    let id: String
    let is_active: Bool
    let is_restricted: Bool
    let name: String
    let type: String
}

private struct SpotifyArtist: Decodable {
    let name: String
}

private struct SpotifyAlbum: Decodable {
    let images: [SpotifyImage]?
}

private struct SpotifyImage: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

// MARK: - Token manager

@MainActor
final class SpotifyWebAPI: ObservableObject {
    static let shared = SpotifyWebAPI()

    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?

    private var accessToken: String? {
        get { cachedAccessToken }
        set {
            cachedAccessToken = newValue
            if let v = newValue { Keychain.save(v, forKey: "spotify_access_token") }
            else { Keychain.delete(forKey: "spotify_access_token") }
        }
    }

    private var refreshToken: String? {
        get { cachedRefreshToken }
        set {
            cachedRefreshToken = newValue
            if let v = newValue { Keychain.save(v, forKey: "spotify_refresh_token") }
            else { Keychain.delete(forKey: "spotify_refresh_token") }
        }
    }

    private var tokenExpiresAt: Date = .distantPast
    private var proactiveRefreshTask: DispatchWorkItem?

    var isAuthenticated: Bool { cachedAccessToken != nil && cachedRefreshToken != nil }

    func signOut() {
        proactiveRefreshTask?.cancel()
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = .distantPast
        UserDefaults.standard.removeObject(forKey: "spotify_token_expiry")
        PlayerState.shared.authState = .unauthenticated
        PlayerState.shared.queue = []
    }

    private init() {
        cachedAccessToken = Keychain.load(forKey: "spotify_access_token")
        cachedRefreshToken = Keychain.load(forKey: "spotify_refresh_token")
        // Re-save with accessibility attributes so macOS stops prompting on every read.
        if let token = cachedAccessToken { Keychain.save(token, forKey: "spotify_access_token") }
        if let token = cachedRefreshToken { Keychain.save(token, forKey: "spotify_refresh_token") }
        if let storedExpiry = UserDefaults.standard.object(forKey: "spotify_token_expiry") as? Date {
            tokenExpiresAt = storedExpiry
        }
    }

    // MARK: - OAuth

    func startOAuthFlow() {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: kClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: kRedirectURI),
            URLQueryItem(name: "scope", value: kScopes),
            URLQueryItem(name: "show_dialog", value: "true"),
        ]
        guard let url = components.url else { return }
        NSApp.activate(ignoringOtherApps: true)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config)
    }

    func handleCallback(url: URL) {
        guard url.scheme == "vinyl" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            print("[Spotify] OAuth error: \(error)")
            PlayerState.shared.authState = .needsReauth
            return
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        exchangeCode(code)
    }

    private func exchangeCode(_ code: String) {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(kRedirectURI)&client_id=\(kClientID)&client_secret=\(kClientSecret)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let data, self.handleTokenResponse(data: data) else {
                    PlayerState.shared.authState = .needsReauth
                    return
                }
                PlayerState.shared.authState = .authenticated
                PollingService.shared.refreshNow()
                PollingService.shared.refreshQueueNow()
            }
        }.resume()
    }

    /// Confirms stored tokens still work; refreshes or marks session invalid on failure.
    func validateSession(completion: ((Bool) -> Void)? = nil) {
        guard isAuthenticated, let token = accessToken else {
            PlayerState.shared.authState = .unauthenticated
            completion?(false)
            return
        }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self else { completion?(false); return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    PlayerState.shared.authState = .authenticated
                    completion?(true)
                    return
                }
                self.refreshAccessToken { success in
                    DispatchQueue.main.async {
                        PlayerState.shared.authState = success ? .authenticated : .needsReauth
                        completion?(success)
                    }
                }
            }
        }.resume()
    }

    func refreshAccessToken(completion: ((Bool) -> Void)? = nil) {
        guard let token = refreshToken else { completion?(false); return }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(token)&client_id=\(kClientID)&client_secret=\(kClientSecret)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { completion?(false); return }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 {
                DispatchQueue.main.async {
                    self.accessToken = nil
                    self.refreshToken = nil
                    PlayerState.shared.authState = .needsReauth
                    completion?(false)
                }
                return
            }
            guard let data else { completion?(false); return }
            DispatchQueue.main.async {
                completion?(self.handleTokenResponse(data: data))
            }
        }.resume()
    }

    @discardableResult
    private func handleTokenResponse(data: Data) -> Bool {
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else { return false }
        accessToken = response.access_token
        if let rt = response.refresh_token { refreshToken = rt }
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))
        UserDefaults.standard.set(tokenExpiresAt, forKey: "spotify_token_expiry")
        scheduleProactiveRefresh(in: TimeInterval(response.expires_in) - 300)
        return true
    }

    private func scheduleProactiveRefresh(in interval: TimeInterval) {
        proactiveRefreshTask?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshAccessToken()
        }
        proactiveRefreshTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(interval, 60), execute: item)
    }

    func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            guard tokenExpiresAt.timeIntervalSinceNow < 5 * 60 else { return }
            refreshAccessToken { [weak self] success in
                guard !success else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.refreshAccessToken { success in
                        if !success { self?.startOAuthFlow() }
                    }
                }
            }
        }
    }

    // MARK: - API calls

    func fetchCurrentlyPlaying(completion: @escaping (Track?, URL?) -> Void) {
        withActiveDevice {
            self.authorizedRequest(path: "/v1/me/player/currently-playing") { data, response in
                guard let http = response as? HTTPURLResponse else {
                    DispatchQueue.main.async { completion(nil, nil) }
                    return
                }
                if http.statusCode == 204 || data == nil {
                    DispatchQueue.main.async { completion(nil, nil) }
                    return
                }
                guard http.statusCode == 200,
                      let data,
                      let parsed = try? JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data),
                      let item = parsed.item else {
                    DispatchQueue.main.async { completion(nil, nil) }
                    return
                }

                let track = item.toTrack()
                DispatchQueue.main.async { completion(track, track.albumArtURL) }
            }
        }
    }

    func fetchQueue(
        expectedTrackID: String? = nil,
        retryCount: Int = 0,
        completion: @escaping ([Track]) -> Void
    ) {
        withActiveDevice {
            self.authorizedRequest(path: "/v1/me/player/queue") { data, response in
                guard let http = response as? HTTPURLResponse else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                if http.statusCode == 403 {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                if http.statusCode == 204 || data == nil {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                guard http.statusCode == 200, let data else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }

                let parsed = Self.parseQueueResponse(data)

                if let expectedTrackID,
                   let playingID = parsed.currentlyPlayingID,
                   playingID != expectedTrackID,
                   retryCount < 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.fetchQueue(
                            expectedTrackID: expectedTrackID,
                            retryCount: retryCount + 1,
                            completion: completion
                        )
                    }
                    return
                }

                DispatchQueue.main.async { completion(parsed.tracks) }
            }
        }
    }

    /// Ensures Spotify Connect sees this Mac as the active device, then fetches queue.
    func refreshQueue(completion: (([Track]) -> Void)? = nil) {
        fetchQueue { tracks in
            PlayerState.shared.queue = tracks
            completion?(tracks)
        }
    }

    private static func parseQueueResponse(_ data: Data) -> (tracks: [Track], currentlyPlayingID: String?) {
        if let decoded = try? JSONDecoder().decode(QueueResponse.self, from: data) {
            return (decoded.queue.map(\.toTrack), decoded.currently_playing?.id)
        }
        return parseQueueResponseLeniently(data)
    }

    /// Fallback when strict decoding fails (episodes, local files, etc.).
    private static func parseQueueResponseLeniently(_ data: Data) -> (tracks: [Track], currentlyPlayingID: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }

        let currentlyPlayingID = (json["currently_playing"] as? [String: Any])?["id"] as? String
        let queueArray = json["queue"] as? [[String: Any]] ?? []
        let tracks = queueArray.compactMap { parseMediaDictionary($0) }
        return (tracks, currentlyPlayingID)
    }

    private static func parseMediaDictionary(_ dict: [String: Any]) -> Track? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String else { return nil }

        let durationMs = dict["duration_ms"] as? Int ?? 0

        var artist = ""
        if let artists = dict["artists"] as? [[String: Any]] {
            artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
        } else if let show = dict["show"] as? [String: Any],
                  let showName = show["name"] as? String {
            artist = showName
        }

        var artURL: URL?
        if let album = dict["album"] as? [String: Any],
           let images = album["images"] as? [[String: Any]] {
            artURL = bestImageURL(from: images)
        } else if let images = dict["images"] as? [[String: Any]] {
            artURL = bestImageURL(from: images)
        }

        return Track(
            id: id,
            title: name,
            artist: artist,
            albumArtURL: artURL,
            duration: TimeInterval(durationMs) / 1000
        )
    }

    private static func bestImageURL(from images: [[String: Any]]) -> URL? {
        let sorted = images.sorted {
            (($0["width"] as? Int) ?? 0) > (($1["width"] as? Int) ?? 0)
        }
        guard let urlString = sorted.first?["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    private func withActiveDevice(_ work: @escaping () -> Void) {
        ensureActiveDevice { _ in work() }
    }

    private func ensureActiveDevice(completion: @escaping (Bool) -> Void) {
        authorizedRequest(path: "/v1/me/player/devices") { data, response in
            guard let data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let parsed = try? JSONDecoder().decode(DevicesResponse.self, from: data) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if parsed.devices.contains(where: { $0.is_active && !$0.is_restricted }) {
                DispatchQueue.main.async { completion(true) }
                return
            }

            let candidate = parsed.devices.first(where: { $0.type == "Computer" && !$0.is_restricted })
                ?? parsed.devices.first(where: { !$0.is_restricted })

            guard let device = candidate else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.authorizedJSONRequest(
                method: "PUT",
                path: "/v1/me/player",
                json: ["device_ids": [device.id], "play": false]
            ) { response in
                let ok = (response as? HTTPURLResponse)?.statusCode == 204
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    /// Plays the given tracks in order, discarding anything before the first URI.
    func playTracks(trackIDs: [String], positionMs: Int? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !trackIDs.isEmpty else {
            DispatchQueue.main.async { completion?(false) }
            return
        }

        var payload: [String: Any] = ["uris": trackIDs.map { "spotify:track:\($0)" }]
        if let positionMs { payload["position_ms"] = positionMs }

        authorizedJSONRequest(method: "PUT", path: "/v1/me/player/play", json: payload) { response in
            let ok = (response as? HTTPURLResponse)?.statusCode == 204
            DispatchQueue.main.async {
                if ok { PollingService.shared.refreshNow() }
                completion?(ok)
            }
        }
    }

    /// Keeps the current track playing but replaces the upcoming queue order.
    func syncUpcomingQueue(trackIDs: [String], resumePositionMs: Int, completion: ((Bool) -> Void)? = nil) {
        fetchCurrentlyPlaying { current, _ in
            guard let currentID = current?.id else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            self.playTracks(trackIDs: [currentID] + trackIDs, positionMs: resumePositionMs, completion: completion)
        }
    }

    private func authorizedRequest(
        path: String,
        retryingAfterRefresh: Bool = false,
        completion: @escaping (Data?, URLResponse?) -> Void
    ) {
        authorizedDataRequest(
            method: "GET",
            path: path,
            body: nil,
            retryingAfterRefresh: retryingAfterRefresh,
            completion: completion
        )
    }

    private func authorizedJSONRequest(
        method: String,
        path: String,
        json: [String: Any],
        retryingAfterRefresh: Bool = false,
        completion: @escaping (URLResponse?) -> Void
    ) {
        guard let body = try? JSONSerialization.data(withJSONObject: json) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        authorizedDataRequest(
            method: method,
            path: path,
            body: body,
            retryingAfterRefresh: retryingAfterRefresh
        ) { _, response in
            completion(response)
        }
    }

    private func authorizedDataRequest(
        method: String,
        path: String,
        body: Data?,
        retryingAfterRefresh: Bool = false,
        completion: @escaping (Data?, URLResponse?) -> Void
    ) {
        guard let token = accessToken else {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        var request = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            if let http = response as? HTTPURLResponse, http.statusCode == 401, !retryingAfterRefresh {
                self.refreshAccessToken { success in
                    if success {
                        self.authorizedDataRequest(
                            method: method,
                            path: path,
                            body: body,
                            retryingAfterRefresh: true,
                            completion: completion
                        )
                    } else {
                        DispatchQueue.main.async { completion(nil, response) }
                    }
                }
                return
            }
            completion(data, response)
        }.resume()
    }
}
