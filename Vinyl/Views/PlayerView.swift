import SwiftUI
import AppKit
import Combine

// MARK: - Spinning CD
// Reads angleDegrees from VinylSpinner.shared — the single source of truth —
// so the popover CD and the menu bar icon are always at the same orientation.

struct SpinningCDView: View {
    let image: NSImage?
    let diameter: CGFloat
    let theme: AppTheme

    @ObservedObject private var spinner = VinylSpinner.shared

    var body: some View {
        Group {
            switch theme {
            case .apple: appleCD
            case .pixel:  pixelCD
            }
        }
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

    private var pixelCD: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: diameter * 0.62, height: diameter * 0.62).clipShape(Circle())
            }
            if let frame = NSImage(named: "pixel_cd_frame") {
                Image(nsImage: frame).interpolation(.none).resizable()
                    .frame(width: diameter, height: diameter)
            } else {
                Circle().strokeBorder(PixelTheme.accentColor, lineWidth: 5)
            }
        }
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
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Color(white: 1, opacity: 0.55))
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
        HStack(spacing: 24) {
            pixelButton("pixel_btn_prev",  fallback: "backward.fill") { onPrevTap(); AppleScriptBridge.previousTrack() }
            pixelButton(playerState.isPlaying ? "pixel_btn_pause" : "pixel_btn_play",
                        fallback: playerState.isPlaying ? "pause.fill" : "play.fill") {
                PlayerState.shared.isPlaying.toggle(); AppleScriptBridge.playPause()
            }
            pixelButton("pixel_btn_next",  fallback: "forward.fill") { onNextTap(); AppleScriptBridge.nextTrack() }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pixelButton(_ named: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let img = NSImage(named: named) {
                Image(nsImage: img).interpolation(.none).resizable()
                    .frame(width: PixelTheme.controlButtonSize, height: PixelTheme.controlButtonSize)
            } else {
                Image(systemName: fallback).font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PixelTheme.primaryTextColor)
            }
        }
        .buttonStyle(.plain)
    }
}
