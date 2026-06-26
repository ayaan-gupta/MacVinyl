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

    private var accessToken: String? {
        get { Keychain.load(forKey: "spotify_access_token") }
        set { if let v = newValue { Keychain.save(v, forKey: "spotify_access_token") } else { Keychain.delete(forKey: "spotify_access_token") } }
    }

    private var refreshToken: String? {
        get { Keychain.load(forKey: "spotify_refresh_token") }
        set { if let v = newValue { Keychain.save(v, forKey: "spotify_refresh_token") } else { Keychain.delete(forKey: "spotify_refresh_token") } }
    }

    private var tokenExpiresAt: Date = .distantPast
    private var proactiveRefreshTask: DispatchWorkItem?

    var isAuthenticated: Bool { accessToken != nil && refreshToken != nil }

    private init() {
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
            URLQueryItem(name: "scope", value: kScopes)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        exchangeCode(code)
    }

    private func exchangeCode(_ code: String) {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(kRedirectURI)&client_id=\(kClientID)&client_secret=\(kClientSecret)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data else { return }
            DispatchQueue.main.async {
                self.handleTokenResponse(data: data)
                PlayerState.shared.authState = .authenticated
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
                self.handleTokenResponse(data: data)
                completion?(true)
            }
        }.resume()
    }

    private func handleTokenResponse(data: Data) {
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else { return }
        accessToken = response.access_token
        if let rt = response.refresh_token { refreshToken = rt }
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))
        UserDefaults.standard.set(tokenExpiresAt, forKey: "spotify_token_expiry")
        scheduleProactiveRefresh(in: TimeInterval(response.expires_in) - 300)
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
        guard let token = accessToken else { completion(nil, nil); return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    DispatchQueue.main.async { self.refreshAccessToken() }
                    return
                }
                guard httpResponse.statusCode == 200, let data else { return }
                guard let parsed = try? JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data),
                      let item = parsed.item else { return }

                let artistName = item.artists.map(\.name).joined(separator: ", ")
                let artURL = item.album.images.sorted(by: { ($0.width ?? 0) > ($1.width ?? 0) }).first.flatMap { URL(string: $0.url) }
                let track = Track(id: item.id, title: item.name, artist: artistName,
                                  albumArtURL: artURL, duration: TimeInterval(item.duration_ms) / 1000)
                DispatchQueue.main.async { completion(track, artURL) }
            }
        }.resume()
    }

    func fetchQueue(expectedTrackID: String, completion: @escaping ([Track]) -> Void) {
        guard let token = accessToken else { completion([]); return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard let data,
                  let parsed = try? JSONDecoder().decode(QueueResponse.self, from: data) else { return }

            if parsed.currently_playing?.id != expectedTrackID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.fetchQueue(expectedTrackID: expectedTrackID, completion: completion)
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
        }.resume()
    }
}
