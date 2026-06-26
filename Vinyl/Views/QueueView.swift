import SwiftUI

struct QueueView: View {
    @ObservedObject var playerState: PlayerState
    let theme: AppTheme

    private var queue: [Track] { playerState.queue }
    private var authState: PlayerState.AuthState { playerState.authState }

    private var emptyMessage: String {
        switch authState {
        case .authenticated:
            return "Nothing up next — add songs to your Spotify queue"
        case .needsReauth:
            return "Reconnect Spotify in Settings to see Up Next"
        case .unauthenticated:
            return "Connect Spotify in Settings to see Up Next"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Up Next")
                .font(theme == .apple
                      ? .system(size: 11, weight: .semibold)
                      : PixelTheme.timestampFont)
                .foregroundStyle(theme == .apple
                                 ? AnyShapeStyle(Color(white: 1, opacity: 0.5))
                                 : AnyShapeStyle(PixelTheme.secondaryTextColor))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if queue.isEmpty {
                Text(emptyMessage)
                    .font(theme == .apple ? .system(size: 11) : PixelTheme.timestampFont)
                    .foregroundStyle(theme == .apple
                                     ? Color(white: 1, opacity: 0.35)
                                     : PixelTheme.secondaryTextColor.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(queue.prefix(20).enumerated()), id: \.element.id) { index, track in
                            QueueRowView(
                                track: track,
                                theme: theme,
                                onPlay: { playerState.playQueueTrack(at: index) },
                                onDropDraggedID: { draggedID in
                                    playerState.reorderQueue(draggedID: draggedID, beforeID: track.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 220)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Row

private struct QueueRowView: View {
    let track: Track
    let theme: AppTheme
    let onPlay: () -> Void
    let onDropDraggedID: (String) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    QueueAlbumArtView(url: track.albumArtURL, theme: theme)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(theme == .apple
                                  ? .system(size: 12)
                                  : PixelTheme.queueRowFont)
                            .foregroundStyle(theme == .apple
                                             ? Color(white: 1, opacity: 0.85)
                                             : PixelTheme.primaryTextColor)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(theme == .apple
                                  ? .system(size: 11)
                                  : PixelTheme.queueRowFont)
                            .foregroundStyle(theme == .apple
                                             ? Color(white: 1, opacity: 0.45)
                                             : PixelTheme.secondaryTextColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            dragHandle
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTargeted ? Color.white.opacity(theme == .apple ? 0.08 : 0.05) : .clear)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.first, draggedID != track.id else { return false }
            onDropDraggedID(draggedID)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme == .apple
                             ? Color(white: 1, opacity: 0.35)
                             : PixelTheme.secondaryTextColor.opacity(0.8))
            .frame(width: 20, height: 32)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .draggable(track.id) {
                dragPreview
            }
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            QueueAlbumArtView(url: track.albumArtURL, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Album art

private struct QueueAlbumArtView: View {
    let url: URL?
    let theme: AppTheme

    @State private var image: NSImage?
    @State private var pixelatedImage: NSImage?

    private let size: CGFloat = 36

    private var cornerRadius: CGFloat { theme == .apple ? 4 : 3 }

    var body: some View {
        Group {
            if let displayImage {
                Image(nsImage: displayImage)
                    .interpolation(theme == .pixel ? .none : .medium)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear { loadArt() }
        .onChange(of: url) { _, _ in loadArt() }
    }

    private var displayImage: NSImage? {
        theme == .pixel ? (pixelatedImage ?? image) : image
    }

    @ViewBuilder
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(theme == .apple
                  ? Color(white: 1, opacity: 0.08)
                  : PixelTheme.progressTrackColor.opacity(0.6))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(theme == .apple
                                     ? Color(white: 1, opacity: 0.25)
                                     : PixelTheme.secondaryTextColor.opacity(0.5))
            }
    }

    private func loadArt() {
        image = nil
        pixelatedImage = nil
        guard let url else { return }

        if let cached = AlbumArtLoader.shared.image(for: url) {
            applyImage(cached)
            return
        }

        AlbumArtLoader.shared.loadQueued(url: url) { loaded in
            guard let loaded else { return }
            applyImage(loaded)
        }
    }

    private func applyImage(_ loaded: NSImage) {
        image = loaded
        guard theme == .pixel else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let pixelated = AlbumArtPixelator.pixelate(
                loaded,
                pixelCount: PixelTurntableLayout.queueArtPixelCount
            )
            DispatchQueue.main.async { pixelatedImage = pixelated }
        }
    }
}
