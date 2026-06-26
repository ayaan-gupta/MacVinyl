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
    @Published var authState: AuthState = .unauthenticated

    enum AuthState {
        case unauthenticated
        case authenticated
        case needsReauth
    }

    private init() {}
}
