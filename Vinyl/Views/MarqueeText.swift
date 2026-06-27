import SwiftUI
import AppKit

/// Continuous, seamless marquee text driven by TimelineView (display-link cadence).
/// - Scrolls without any pause between passes — wraps are visually seamless because
///   the HStack contains two identical copies of the text.
/// - Freezes in place while the cursor hovers, resumes from the exact same position.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    /// When set, used instead of GeometryReader measurement (more reliable in nested layouts).
    var width: CGFloat? = nil
    /// AppKit font for width measurement. Required for custom fonts where SwiftUI
    /// GeometryReader sizing is constrained to the clipped container width.
    var measurementFont: NSFont? = nil

    @State private var naturalWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var cycleStart: Date = .now
    @State private var isHovering = false
    @State private var hoverStart: Date? = nil

    private let gap: CGFloat = 30
    private let speed: CGFloat = 44   // points per second

    private var effectiveContainerWidth: CGFloat { width ?? containerWidth }

    private var needsScroll: Bool {
        naturalWidth > 0 && effectiveContainerWidth > 0 && naturalWidth > effectiveContainerWidth
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
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 20)
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
            // Measure container width (skipped when an explicit width is provided).
            .background {
                if width == nil {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { containerWidth = g.size.width }
                            .onChange(of: g.size.width) { _, w in containerWidth = w }
                    }
                }
            }
            // Measure natural text width — AppKit sizing for custom fonts, otherwise
            // an invisible SwiftUI copy (works for system fonts in unconstrained layouts).
            .background {
                if measurementFont == nil {
                    Text(text).font(font).lineLimit(1).fixedSize().opacity(0)
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { applyNaturalWidth(g.size.width) }
                                .onChange(of: g.size.width) { _, w in applyNaturalWidth(w) }
                        })
                }
            }
            .onAppear { refreshMeasuredWidth() }
            .onChange(of: text) { _, _ in
                refreshMeasuredWidth()
                cycleStart = .now
                isHovering = false
                hoverStart = nil
            }
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    private func refreshMeasuredWidth() {
        guard let measurementFont else { return }
        let w = ceil((text as NSString).size(withAttributes: [.font: measurementFont]).width)
        applyNaturalWidth(w)
    }

    private func applyNaturalWidth(_ w: CGFloat) {
        guard w > 0 else { return }
        naturalWidth = w
        cycleStart = .now
    }
}
