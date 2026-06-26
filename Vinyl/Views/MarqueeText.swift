import SwiftUI

/// Continuous, seamless marquee text driven by TimelineView (display-link cadence).
/// - Scrolls without any pause between passes — wraps are visually seamless because
///   the HStack contains two identical copies of the text.
/// - Freezes in place while the cursor hovers, resumes from the exact same position.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var naturalWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var cycleStart: Date = .now
    @State private var isHovering = false
    @State private var hoverStart: Date? = nil

    private let gap: CGFloat = 30
    private let speed: CGFloat = 44   // points per second

    private var needsScroll: Bool {
        naturalWidth > 0 && containerWidth > 0 && naturalWidth > containerWidth
    }

    private var scrollDist: CGFloat { naturalWidth + gap }

    // Called every display-link frame — pure math, no state mutation.
    private func xOffset(at date: Date) -> CGFloat {
        guard needsScroll, naturalWidth > 0 else { return 0 }
        let effectiveDate = isHovering ? (hoverStart ?? date) : date
        let elapsed  = max(effectiveDate.timeIntervalSince(cycleStart), 0)
        let cycleDur = Double(scrollDist) / Double(speed)
        let phase    = elapsed.truncatingRemainder(dividingBy: cycleDur) / cycleDur
        return -CGFloat(phase) * scrollDist
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 20)
            // Hover detection on the clipped container so the hit-test area
            // matches exactly what the user sees — not the wider HStack.
            .onHover { hovering in
                guard needsScroll else { return }
                if hovering, !isHovering {
                    hoverStart = Date()
                    isHovering = true
                } else if !hovering, isHovering {
                    // Advance cycleStart by the pause duration so the
                    // scroll resumes from exactly where it was frozen.
                    if let start = hoverStart {
                        cycleStart = cycleStart.addingTimeInterval(
                            Date().timeIntervalSince(start)
                        )
                    }
                    hoverStart = nil
                    isHovering = false
                }
            }
            .overlay(alignment: .leading) {
                if needsScroll {
                    TimelineView(.animation) { ctx in
                        HStack(spacing: gap) { label; label }
                            .fixedSize()
                            .offset(x: xOffset(at: ctx.date))
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
            // Measure container width
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { containerWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in containerWidth = w }
                }
            )
            // Measure natural (unconstrained) text width via an invisible copy.
            // Reset cycleStart here so the scroll always begins at position 0.
            .background(
                Text(text).font(font).lineLimit(1).fixedSize().opacity(0)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear {
                                naturalWidth = g.size.width
                                cycleStart = .now   // start from x=0 once measured
                            }
                            .onChange(of: g.size.width) { _, w in
                                naturalWidth = w
                                cycleStart = .now
                            }
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
