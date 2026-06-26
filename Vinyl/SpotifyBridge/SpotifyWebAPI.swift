import AppKit
import Foundation
import Combine

// MARK: - Configuration
// Replace with your Spotify Developer app credentials:
// https://developer.spotify.com/dashboard
private let kClientID     = "REDACTED_CLIENT_ID"
private let kClientSecret = "REDACTED_CLIENT_SECRET"
private let kRedirectURI  = "vinyl://callback"
private let kScopes       = "user-read-playback-state user-read-currently-playing user-read-recently-played"

// MARK: - Codable models

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

private struct CurrentlyPlayingResponse: Decodable {
    let item: SpotifyTrackItem?
    let is_playing: Bool?
}

private struct SpotifyTrackItem: Decodable {
    let id: String
    let name: String
    let duration_ms: Int
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
}

private struct SpotifyArtist: Decodable {
    let name: String
}

private struct SpotifyAlbum: Decodable {
    let images: [SpotifyImage]
}

private struct SpotifyImage: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

private struct QueueResponse: Decodable {
    let currently_playing: SpotifyTrackItem?
    let queue: [SpotifyTrackItem]
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
        authorizedRequest(path: "/v1/me/player/currently-playing") { [weak self] data, response in
            guard let self else { return }
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

            let artistName = item.artists.map(\.name).joined(separator: ", ")
            let artURL = item.album.images.sorted(by: { ($0.width ?? 0) > ($1.width ?? 0) }).first.flatMap { URL(string: $0.url) }
            let track = Track(id: item.id, title: item.name, artist: artistName,
                              albumArtURL: artURL, duration: TimeInterval(item.duration_ms) / 1000)
            DispatchQueue.main.async { completion(track, artURL) }
        }
    }

    func fetchQueue(expectedTrackID: String? = nil, retryCount: Int = 0, completion: @escaping ([Track]) -> Void) {
        authorizedRequest(path: "/v1/me/player/queue") { [weak self] data, response in
            guard let self else { return }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            if http.statusCode == 204 || data == nil {
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard http.statusCode == 200,
                  let data,
                  let parsed = try? JSONDecoder().decode(QueueResponse.self, from: data) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            if let expectedTrackID,
               let playingID = parsed.currently_playing?.id,
               playingID != expectedTrackID,
               retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.fetchQueue(expectedTrackID: expectedTrackID, retryCount: retryCount + 1, completion: completion)
                }
                return
            }

            let tracks = parsed.queue.map { item -> Track in
                let artist = item.artists.map(\.name).joined(separator: ", ")
                let art = item.album.images.sorted(by: { ($0.width ?? 0) > ($1.width ?? 0) }).first.flatMap { URL(string: $0.url) }
                return Track(id: item.id, title: item.name, artist: artist,
                             albumArtURL: art, duration: TimeInterval(item.duration_ms) / 1000)
            }
            DispatchQueue.main.async { completion(tracks) }
        }
    }

    private func authorizedRequest(
        path: String,
        retryingAfterRefresh: Bool = false,
        completion: @escaping (Data?, URLResponse?) -> Void
    ) {
        guard let token = accessToken else {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        var request = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            if let http = response as? HTTPURLResponse, http.statusCode == 401, !retryingAfterRefresh {
                self.refreshAccessToken { success in
                    if success {
                        self.authorizedRequest(path: path, retryingAfterRefresh: true, completion: completion)
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
