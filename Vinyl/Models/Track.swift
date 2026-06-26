import Foundation

struct Track: Equatable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: URL?
    let duration: TimeInterval

    static let empty = Track(id: "", title: "Not Playing", artist: "—", albumArtURL: nil, duration: 0)

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}
