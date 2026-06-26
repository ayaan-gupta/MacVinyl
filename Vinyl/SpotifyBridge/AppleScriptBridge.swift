import AppKit
import Foundation

enum AppleScriptBridge {
    private static let queue = DispatchQueue(label: "com.ayaangupta.Vinyl.applescript", qos: .userInitiated)

    struct TrackInfo {
        let title: String
        let artist: String
        let durationSeconds: TimeInterval
        let artworkURL: URL?
    }

    enum PlayerState {
        case playing, paused, stopped, notRunning
    }

    static func fetchTrackInfo(completion: @escaping (TrackInfo?) -> Void) {
        queue.async {
            let source = """
            tell application "Spotify"
                if it is not running then return "NOT_RUNNING"
                set t to current track
                set artURL to ""
                try
                    set artURL to artwork url of t
                end try
                return (name of t) & "|" & (artist of t) & "|" & ((duration of t) / 1000 as string) & "|" & artURL
            end tell
            """
            guard let result = run(source), result != "NOT_RUNNING" else {
                completion(nil); return
            }
            let parts = result.components(separatedBy: "|")
            guard parts.count >= 3 else { completion(nil); return }
            let duration = TimeInterval(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let artString = parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespaces) : ""
            let artURL = artString.isEmpty ? nil : URL(string: artString)
            completion(TrackInfo(title: parts[0], artist: parts[1], durationSeconds: duration, artworkURL: artURL))
        }
    }

    static func fetchPlayerState(completion: @escaping (PlayerState) -> Void) {
        queue.async {
            let source = """
            tell application "Spotify"
                if it is not running then return "NOT_RUNNING"
                return player state as string
            end tell
            """
            guard let result = run(source) else { completion(.notRunning); return }
            switch result.trimmingCharacters(in: .whitespaces) {
            case "playing":  completion(.playing)
            case "paused":   completion(.paused)
            case "stopped":  completion(.stopped)
            default:         completion(.notRunning)
            }
        }
    }

    static func fetchPosition(completion: @escaping (TimeInterval?) -> Void) {
        queue.async {
            let source = """
            tell application "Spotify"
                if it is not running then return "-1"
                return player position as string
            end tell
            """
            guard let result = run(source),
                  let pos = TimeInterval(result.trimmingCharacters(in: .whitespaces)),
                  pos >= 0 else {
                completion(nil); return
            }
            completion(pos)
        }
    }

    static func playPause() {
        queue.async { run("tell application \"Spotify\" to playpause") }
    }

    static func nextTrack() {
        queue.async { run("tell application \"Spotify\" to next track") }
    }

    static func previousTrack() {
        queue.async { run("tell application \"Spotify\" to previous track") }
    }

    static func seek(to position: TimeInterval) {
        queue.async {
            run("tell application \"Spotify\" to set player position to \(position)")
        }
    }

    @discardableResult
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        if let error { print("[AppleScript] Error: \(error)") }
        return result?.stringValue
    }
}
