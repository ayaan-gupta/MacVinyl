import AppKit
import Foundation

/// Loads album art with per-track cancellation and in-memory URL cache.
final class AlbumArtLoader {
    static let shared = AlbumArtLoader()

    private let cache = NSCache<NSURL, NSImage>()
    private var activeTrackID: String?
    private var activeTask: URLSessionDataTask?

    private init() {}

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(trackID: String, url: URL) {
        activeTask?.cancel()
        activeTrackID = trackID

        if let cached = cache.object(forKey: url as NSURL) {
            deliver(trackID: trackID, image: cached)
            return
        }

        activeTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard trackID == self.activeTrackID else { return }
            guard let data, let image = NSImage(data: data) else { return }
            self.cache.setObject(image, forKey: url as NSURL)
            self.deliver(trackID: trackID, image: image)
        }
        activeTask?.resume()
    }

    func cancel() {
        activeTask?.cancel()
        activeTrackID = nil
    }

    /// Loads art for queue rows without cancelling the now-playing fetch.
    func loadQueued(url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let data, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    private func deliver(trackID: String, image: NSImage) {
        DispatchQueue.main.async {
            let state = PlayerState.shared
            guard state.currentTrack.id == trackID else { return }
            state.albumArtTrackID = trackID
            state.albumArtImage = image
            ColorExtractor.dominantColor(from: image) { color in
                guard PlayerState.shared.albumArtTrackID == trackID else { return }
                PlayerState.shared.accentColor = color
            }
        }
    }
}
