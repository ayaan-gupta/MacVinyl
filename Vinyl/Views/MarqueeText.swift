import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var naturalWidth: CGFloat = 0   // full unconstrained text width
    @State private var containerWidth: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?

    private let gap: CGFloat = 50
    private let speed: CGFloat = 40        // points / second
    private let pause: Double  = 1.8       // seconds before each scroll pass

    private var needsScroll: Bool {
        naturalWidth > 0 && containerWidth > 0 && naturalWidth > containerWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if needsScroll {
                // Two copies side-by-side, animated left
                HStack(spacing: gap) {
                    singleLabel
                    singleLabel
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: xOffset)
            } else {
                // Fits — center and let the OS truncate normally
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .clipped()
        // ── Measure container width ──────────────────────────────────────
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { containerWidth = g.size.width; reschedule() }
                    .onChange(of: g.size.width) { _, w in containerWidth = w; reschedule() }
            }
        )
        // ── Measure natural (unconstrained) text width ───────────────────
        // An invisible, fixed-size copy sits in an overlay so its geometry
        // is always reported regardless of which branch is currently shown.
        .overlay(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .opacity(0)
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { naturalWidth = g.size.width; reschedule() }
                            .onChange(of: g.size.width) { _, w in naturalWidth = w; reschedule() }
                    }
                ),
            alignment: .leading
        )
        .onChange(of: text) { _, _ in
            naturalWidth = 0
            xOffset = 0
            reschedule()
        }
    }

    private var singleLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private func reschedule() {
        scrollTask?.cancel()
        xOffset = 0
        guard needsScroll else { return }
        let dist = naturalWidth + gap
        let dur  = Double(dist) / Double(speed)
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(pause))
            while !Task.isCancelled {
                withAnimation(.linear(duration: dur)) { xOffset = -dist }
                try? await Task.sleep(for: .seconds(dur))
                guard !Task.isCancelled else { break }
                withAnimation(.none) { xOffset = 0 }
                try? await Task.sleep(for: .seconds(pause))
            }
        }
    }
}
