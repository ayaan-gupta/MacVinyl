import SwiftUI

struct QueueView: View {
    let queue: [Track]
    let theme: AppTheme

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
                Text("Queue empty — connect Spotify to see Up Next")
                    .font(theme == .apple ? .system(size: 11) : PixelTheme.timestampFont)
                    .foregroundStyle(theme == .apple
                                     ? Color(white: 1, opacity: 0.35)
                                     : PixelTheme.secondaryTextColor.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queue.prefix(20), id: \.id) { track in
                            QueueRowView(track: track, theme: theme)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }
}

private struct QueueRowView: View {
    let track: Track
    let theme: AppTheme

    var body: some View {
        switch theme {
        case .apple:  appleRow
        case .pixel:  pixelRow
        }
    }

    private var appleRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 1, opacity: 0.85))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 1, opacity: 0.45))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Color(white: 1, opacity: 0.07))
                .frame(height: 1)
                .padding(.leading, 16)
        }
    }

    private var pixelRow: some View {
        ZStack {
            if let bg = NSImage(named: "pixel_queue_row_bg") {
                Image(nsImage: bg).interpolation(.none).resizable(resizingMode: .stretch)
            } else {
                PixelTheme.rowBackgroundColor
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(PixelTheme.queueRowFont).foregroundStyle(PixelTheme.primaryTextColor).lineLimit(1)
                    Text(track.artist)
                        .font(PixelTheme.queueRowFont).foregroundStyle(PixelTheme.secondaryTextColor).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}
