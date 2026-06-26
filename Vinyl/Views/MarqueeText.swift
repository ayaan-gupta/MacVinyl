import SwiftUI

/// Continuous marquee driven by TimelineView (display-link cadence, never throttled).
/// - Scrolls without any built-in pause — the cycle wraps seamlessly.
/// - Pauses on hover, resumes from the exact same position when cursor leaves.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var naturalWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    /// The reference point for elapsed time. Shifted forward whenever hover ends
    /// so the resume position matches the freeze position exactly.
    @State private var cycleStart: Date = .now
    @State private var isHovering = false
    @State private var hoverStart: Date? = nil

    private let gap: CGFloat = 30      // space between the two text copies
    private let speed: CGFloat = 44    // points per second

    private var needsScroll: Bool {
        naturalWidth > 0 && containerWidth > 0 && naturalWidth > containerWidth
    }

    private var scrollDist: CGFloat { naturalWidth + gap }

    /// Pure time → x mapping. Called every display-link frame by TimelineView.
    private func xOffset(at date: Date) -> CGFloat {
        guard needsScroll, naturalWidth > 0 else { return 0 }
        // When hovering, freeze elapsed at the moment hover started.
        let effectiveDate = isHovering ? (hoverStart ?? date) : date
        let elapsed = max(effectiveDate.timeIntervalSince(cycleStart), 0)
        let cycleDuration = Double(scrollDist) / Double(speed)
        let phase = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return -CGFloat(phase) * scrollDist
    }

    var body: some View {
        // Color.clear is the layout anchor — its width is always exactly the
        // container width regardless of how wide the HStack overlay is.
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 20)
            .overlay(alignment: .leading) {
                if needsScroll {
                    TimelineView(.animation) { ctx in
                        HStack(spacing: gap) { label; label }
                            .fixedSize()
                            .offset(x: xOffset(at: ctx.date))
                    }
                    .onHover { hovering in
                        if hovering, !isHovering {
                            // Freeze: record where we paused
                            hoverStart = Date()
                            isHovering = true
                        } else if !hovering, isHovering {
                            // Resume: shift cycleStart forward by the duration of the pause
                            // so xOffset(at:) continues from the frozen position
                            if let start = hoverStart {
                                cycleStart = cycleStart.addingTimeInterval(
                                    Date().timeIntervalSince(start)
                                )
                            }
                            hoverStart = nil
                            isHovering = false
                        }
                    }
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .clipped()
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { containerWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in containerWidth = w }
                }
            )
            .background(
                Text(text).font(font).lineLimit(1).fixedSize().opacity(0)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { naturalWidth = g.size.width }
                            .onChange(of: g.size.width) { _, w in naturalWidth = w }
                    })
            )
            .onChange(of: text) { _, _ in
                naturalWidth = 0
                cycleStart = .now
                isHovering = false
                hoverStart = nil
            }
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}
