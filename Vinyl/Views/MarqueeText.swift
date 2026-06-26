import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var naturalWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var isScrolling = false
    @State private var scrollTask: Task<Void, Never>?

    private let gap: CGFloat = 28          // space between repetitions (tighter)
    private let speed: CGFloat = 42        // points per second
    private let leadPause: Double = 2.0    // seconds of stillness before each pass

    private var needsScroll: Bool {
        naturalWidth > 0 && containerWidth > 0 && naturalWidth > containerWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if needsScroll {
                HStack(spacing: gap) { label; label }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: xOffset)
            } else {
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
        // Container width — only used for the overflow check; don't trigger reschedule
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { containerWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in containerWidth = w }
            }
        )
        // Natural (unconstrained) text width via invisible overlay
        // Always present regardless of which branch is active
        .overlay(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .opacity(0)
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear {
                                naturalWidth = g.size.width
                                // Start only if not already scrolling
                                if !isScrolling { kickoff() }
                            }
                    }
                ),
            alignment: .leading
        )
        .onAppear { kickoff() }
        .onChange(of: text) { _, _ in
            scrollTask?.cancel()
            scrollTask = nil
            isScrolling = false
            xOffset = 0
            naturalWidth = 0
        }
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    private func kickoff() {
        guard !isScrolling, needsScroll else { return }
        isScrolling = true
        let dist = naturalWidth + gap
        let dur  = Double(dist) / Double(speed)
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(leadPause))
            while !Task.isCancelled {
                withAnimation(.linear(duration: dur)) { xOffset = -dist }
                try? await Task.sleep(for: .seconds(dur))
                guard !Task.isCancelled else { break }
                // Snap back instantly off-screen (already invisible at -dist)
                withAnimation(.none) { xOffset = 0 }
                try? await Task.sleep(for: .seconds(0.05))
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(leadPause))
            }
            isScrolling = false
        }
    }
}
