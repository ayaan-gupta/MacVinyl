import Foundation

enum SpotifyConfig {
    static let redirectURI = "vinyl://callback"
    static let scopes = "user-read-playback-state user-read-currently-playing user-read-recently-played user-modify-playback-state"

    /// Public Spotify Client ID from Secrets.xcconfig (PKCE — no client secret).
    static var clientID: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String else {
            return ""
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("YOUR_"),
              trimmed != "ci_build_placeholder",
              !trimmed.contains("REDACTED") else { return "" }
        return trimmed
    }

    static var isConfigured: Bool { !clientID.isEmpty }
}
