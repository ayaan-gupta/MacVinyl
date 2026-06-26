import SwiftUI
import AppKit
import Combine
import CoreImage

// MARK: - Spinning CD (Apple theme only)
// Reads angleDegrees from VinylSpinner.shared — the single source of truth —
// so the popover CD and the menu bar icon are always at the same orientation.

struct SpinningCDView: View {
    let image: NSImage?
    let diameter: CGFloat

    @ObservedObject private var spinner = VinylSpinner.shared

    var body: some View {
        appleCD
            .rotationEffect(.degrees(spinner.angleDegrees))
            .frame(width: diameter, height: diameter)
    }

    private var appleCD: some View {
        ZStack {
            Circle().fill(Color(white: 0.15))

            if let img = image {
                Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
                    .frame(width: diameter, height: diameter)
            }

            ForEach([0.82, 0.70, 0.58] as [Double], id: \.self) { scale in
                Circle().strokeBorder(Color(white: 0, opacity: 0.18), lineWidth: 1)
                    .frame(width: diameter * scale)
            }

            Circle().fill(Color(white: 0.88)).frame(width: diameter * 0.08)
                .shadow(color: .black.opacity(0.5), radius: 2)
            Circle().fill(Color(white: 0.1)).frame(width: diameter * 0.035)
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Pixel Turntable (Pixel theme)
// Layer order: turntable (static) → record (spins + slides) → tonearm (pivots)

struct PixelTurntableView: View {
    /// Direction hint from parent: 1 = next track (record exits left), -1 = prev
    let pendingDirection: CGFloat
    /// Display width of the whole turntable widget
    let width: CGFloat

    @ObservedObject private var playerState = PlayerState.shared
    @ObservedObject private var spinner     = VinylSpinner.shared

    // ── Record transition state ────────────────────────────────────────────
    @State private var displayedArt:    NSImage?
    @State private var incomingArt:     NSImage?
    @State private var outgoingOffsetX: CGFloat = 0
    @State private var incomingOffsetX: CGFloat = 0
    @State private var showIncoming:    Bool    = false
    @State private var lastTrackID:     String  = ""

    // ── Tonearm state ──────────────────────────────────────────────────────
    @State private var tonearmDegrees: Double = TonearmAngles.off

    // FINE-TUNE: adjust these angles to match your pixel art exactly.
    // Positive = clockwise (arm rests to the right of the record).
    // Negative = counterclockwise (arm swings left, onto the record).
    private enum TonearmAngles {
        static let on:  Double = -42   // arm on record (playing)
        static let off: Double = -12   // arm resting (paused)
    }

    // ── Layout geometry ────────────────────────────────────────────────────
    // FINE-TUNE: adjust these fractions to match your pixel_turntable.png layout.
    private var ttHeight:   CGFloat { width * (659.0 / 869.0) }   // turntable aspect ratio
    private var recordDiam: CGFloat { width * 0.57 }              // record diameter
    private var artDiam:    CGFloat { recordDiam * 0.37 }         // album-art hole diameter
    private var tonearmH:   CGFloat { ttHeight * 0.65 }           // tonearm display height
    private var tonearmW:   CGFloat { tonearmH * (169.0 / 566.0) } // keep aspect ratio

    // Tonearm pivot position relative to ZStack center (= turntable center).
    // FINE-TUNE: move these until the pivot dot aligns with the physical pivot
    // in pixel_turntable.png.
    private var pivotX: CGFloat { width * 0.31 }
    private var pivotY: CGFloat { -ttHeight * 0.33 }

    // Record center offset from turntable center.
    // FINE-TUNE: adjust until record sits cleanly on the platter.
    private var recordOffX: CGFloat { -width * 0.04 }
    private var recordOffY: CGFloat {  ttHeight * 0.01 }

    // ── Body ───────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            // Layer 1 — Turntable body (static)
            turntableImage

            // Layer 2 — Spinning record with album art (clips to circular platter)
            ZStack {
                recordView(art: displayedArt, spinning: true)
                    .offset(x: outgoingOffsetX)

                if showIncoming {
                    recordView(art: incomingArt, spinning: false)
                        .offset(x: incomingOffsetX)
                }
            }
            .frame(width: recordDiam, height: recordDiam)
            .clipShape(Circle())
            .offset(x: recordOffX, y: recordOffY)

            // Layer 3 — Tonearm overlay (always on top of record)
            tonearmView
        }
        .frame(width: width, height: ttHeight)
        .onAppear {
            displayedArt   = playerState.albumArtImage
            lastTrackID    = playerState.currentTrack.id
            tonearmDegrees = playerState.isPlaying ? TonearmAngles.on : TonearmAngles.off
        }
        // Tonearm follows play/pause state
        .onChange(of: playerState.isPlaying) { _, playing in
            withAnimation(.easeInOut(duration: 0.7)) {
                tonearmDegrees = playing ? TonearmAngles.on : TonearmAngles.off
            }
        }
        // New track → slide record out, new one in
        .onChange(of: playerState.currentTrack) { _, newTrack in
            guard newTrack.id != lastTrackID else { return }
            lastTrackID = newTrack.id
            triggerRecordSlide(to: playerState.albumArtImage)
        }
        // Art update during or after transition
        .onChange(of: playerState.albumArtImage) { _, newArt in
            if showIncoming {
                incomingArt = newArt
            } else {
                displayedArt = newArt
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var turntableImage: some View {
        if let tt = NSImage(named: "pixel_turntable") {
            Image(nsImage: tt)
                .interpolation(.none)
                .resizable()
                .frame(width: width, height: ttHeight)
        } else {
            Rectangle()
                .fill(Color(red: 0.15, green: 0.13, blue: 0.10, alpha: 1))
                .frame(width: width, height: ttHeight)
        }
    }

    @ViewBuilder
    private func recordView(art: NSImage?, spinning: Bool) -> some View {
        ZStack {
            // Album art in the transparent center hole (pixelated)
            if let art = art {
                Image(nsImage: pixelateArt(art))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
                    .frame(width: artDiam, height: artDiam)
                    .clipShape(Circle())
            }
            // Record frame overlay — transparent center reveals art beneath
            if let rec = NSImage(named: "pixel_record") {
                Image(nsImage: rec)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: recordDiam, height: recordDiam)
            } else {
                Circle()
                    .strokeBorder(Color(white: 0.85), lineWidth: 3)
                    .frame(width: recordDiam, height: recordDiam)
            }
        }
        .frame(width: recordDiam, height: recordDiam)
        .rotationEffect(spinning ? .degrees(spinner.angleDegrees) : .zero)
    }

    @ViewBuilder
    private var tonearmView: some View {
        if let ta = NSImage(named: "pixel_tonearm") {
            Image(nsImage: ta)
                .interpolation(.none)
                .resizable()
                .frame(width: tonearmW, height: tonearmH)
                // Rotate around the top-centre of the image (the physical pivot)
                .rotationEffect(.degrees(tonearmDegrees), anchor: .top)
                // offset so the pivot (top of image) lands at (pivotX, pivotY)
                // In a ZStack the child's centre is at (0,0), so pivot top = (0, -tonearmH/2).
                // We shift by (pivotX, pivotY + tonearmH/2) to land the top at the target.
                .offset(x: pivotX, y: pivotY + tonearmH / 2)
        }
    }

    // MARK: - Record slide transition

    private func triggerRecordSlide(to newArt: NSImage?) {
        guard !showIncoming else {
            incomingArt = newArt
            return
        }
        let dir = pendingDirection   // 1 = next (outgoing exits left), -1 = prev
        incomingArt     = newArt
        incomingOffsetX = dir * recordDiam * 2.2
        showIncoming    = true

        withAnimation(.easeIn(duration: 0.30)) {
            outgoingOffsetX = -dir * recordDiam * 2.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                incomingOffsetX = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
            displayedArt    = newArt
            outgoingOffsetX = 0
            showIncoming    = false
        }
    }

    // MARK: - Album art pixelation

    /// Applies a CIPixellate filter so the art looks appropriately 8-bit inside the
    /// record hole while remaining recognisable. Adjust `targetPixelCount` to taste.
    private func pixelateArt(_ image: NSImage) -> NSImage {
        guard let cgSrc = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let ciInput = CIImage(cgImage: cgSrc)
        guard let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        // Scale so there are ~28 visible "pixels" across the image width.
        let targetPixelCount: Double = 28
        let scale = max(2.0, Double(cgSrc.width) / targetPixelCount)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return image }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        // Crop to original extent to avoid the half-pixel border CIPixellate adds
        guard let cgOut = ctx.createCGImage(output, from: ciInput.extent) else { return image }
        return NSImage(cgImage: cgOut, size: NSSize(width: cgSrc.width, height: cgSrc.height))
    }
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    @ObservedObject var playerState: PlayerState
    let accentColor: Color
    let theme: AppTheme

    @State private var barWidth: CGFloat = 0
    @State private var isHovering = false
    @State private var isDragging = false

    private var duration: TimeInterval { playerState.currentTrack.duration }
    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(playerState.progress / duration, 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 1, opacity: 0.2)).frame(height: 4)
                if barWidth > 0 {
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: max(barWidth * fraction, 0), height: 4)
                }
                if isHovering || isDragging {
                    Circle().fill(Color.white).frame(width: 12, height: 12)
                        .offset(x: max(barWidth * fraction - 6, 0))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 16)
            .contentShape(Rectangle())
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { barWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in barWidth = w }
            })
            .onHover { isHovering = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    isDragging = true
                    ProgressInterpolator.shared.isScrubbing = true
                    playerState.progress = min(max(v.location.x / max(barWidth, 1), 0), 1) * duration
                }
                .onEnded { v in
                    isDragging = false
                    AppleScriptBridge.seek(to: min(max(v.location.x / max(barWidth, 1), 0), 1) * duration)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        ProgressInterpolator.shared.isScrubbing = false
                    }
                })

            HStack {
                Text(formatTime(playerState.progress))
                Spacer()
                Text(formatTime(duration))
            }
            .font(theme == .apple ? AppleTheme.timestampFont : PixelTheme.timestampFont)
            .foregroundStyle(theme == .apple
                             ? Color(white: 1, opacity: 0.55)
                             : PixelTheme.secondaryTextColor)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && t > 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Controls

struct ControlsView: View {
    @ObservedObject var playerState: PlayerState
    let accentColor: Color
    let theme: AppTheme
    var onNextTap: () -> Void = {}
    var onPrevTap: () -> Void = {}

    var body: some View {
        switch theme {
        case .apple: appleControls
        case .pixel: pixelControls
        }
    }

    private var appleControls: some View {
        HStack(spacing: 28) {
            controlButton("backward.fill", size: 21) { onPrevTap(); AppleScriptBridge.previousTrack() }
            controlButton(playerState.isPlaying ? "pause.fill" : "play.fill", size: 30) {
                PlayerState.shared.isPlaying.toggle()
                AppleScriptBridge.playPause()
            }
            controlButton("forward.fill", size: 21) { onNextTap(); AppleScriptBridge.nextTrack() }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pixelControls: some View {
        HStack(spacing: 20) {
            pixelButton("pixel_backwards", fallback: "backward.fill",
                        height: PixelTheme.controlButtonSize) {
                onPrevTap(); AppleScriptBridge.previousTrack()
            }
            pixelButton(playerState.isPlaying ? "pixel_paused" : "pixel_playing",
                        fallback: playerState.isPlaying ? "pause.fill" : "play.fill",
                        height: PixelTheme.playButtonSize) {
                PlayerState.shared.isPlaying.toggle()
                AppleScriptBridge.playPause()
            }
            pixelButton("pixel_forward", fallback: "forward.fill",
                        height: PixelTheme.controlButtonSize) {
                onNextTap(); AppleScriptBridge.nextTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pixelButton(_ named: String, fallback: String,
                             height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let img = NSImage(named: named) {
                let aspect = img.size.width / max(img.size.height, 1)
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: height * aspect, height: height)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: height * 0.65, weight: .medium))
                    .foregroundStyle(PixelTheme.primaryTextColor)
            }
        }
        .buttonStyle(.plain)
    }
}
