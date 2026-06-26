import SwiftUI
import AppKit

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    init(material: NSVisualEffectView.Material,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material; self.blendingMode = blendingMode
    }
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material; v.blendingMode = blendingMode
    }
}

// MARK: - Root

struct PopoverView: View {
    @EnvironmentObject var themeSettings: ThemeSettings
    @ObservedObject var playerState: PlayerState
    var onSizeChange: ((CGSize) -> Void)?

    @State private var showSettings = false

    private var contentWidth: CGFloat {
        themeSettings.active == .pixel ? PixelTheme.popoverWidth : AppleTheme.popoverWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(playerState: playerState,
                             onDismiss: { withAnimation { showSettings = false } })
                    .environmentObject(themeSettings)
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal:   .move(edge: .trailing)))
            } else {
                PlayerContentView(
                    playerState: playerState,
                    onShowSettings: { withAnimation { showSettings = true } }
                )
                .environmentObject(themeSettings)
                .transition(.asymmetric(insertion: .move(edge: .leading),
                                        removal:   .move(edge: .leading)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSettings)
        .frame(width: contentWidth)
        .background(BackgroundView(playerState: playerState, theme: themeSettings.active))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SizePreferenceKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { onSizeChange?($0) }
    }
}

// MARK: - Background

private struct BackgroundView: View {
    @ObservedObject var playerState: PlayerState
    let theme: AppTheme

    var body: some View {
        switch theme {
        case .apple:
            ZStack {
                Color.black
                if let img = playerState.albumArtImage {
                    // Large blur radius makes the color distribution more uniform top-to-bottom.
                    // The gradient overlay darkens the top and bottom so the top-bar area
                    // blends into the colorful CD region without a visible band.
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 70, opaque: true)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.62),
                                    Color.black.opacity(0.36),
                                    Color.black.opacity(0.50)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .transition(.opacity)
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(white: 0.06)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .animation(.easeInOut(duration: 1.0), value: playerState.albumArtImage != nil)

        case .pixel:
            if let bg = NSImage(named: "pixel_background") {
                GeometryReader { geo in
                    let imageHeight = geo.size.width * (bg.size.height / max(bg.size.width, 1))
                    Image(nsImage: bg)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: geo.size.width, height: imageHeight)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                }
            } else {
                Color(red: 0.12, green: 0.09, blue: 0.06, alpha: 1)
            }
        }
    }
}

// MARK: - Player content

struct PlayerContentView: View {
    @ObservedObject var playerState: PlayerState
    @EnvironmentObject var themeSettings: ThemeSettings
    let onShowSettings: () -> Void

    @State private var displayedTrack: Track
    @State private var displayedImage: NSImage?

    @State private var outgoingX: CGFloat = 0
    @State private var incomingX: CGFloat = 0
    @State private var incomingTrack: Track = .empty
    @State private var incomingImage: NSImage? = nil
    @State private var showIncoming = false
    @State private var isExiting = false
    @State private var showQueue = false

    private enum Transition {
        static let slideOut: Double = 0.09
        static let slideInDelay: Double = 0.04
        static let slideIn: Double = 0.10
        static let settle: Double = 0.15
    }

    init(playerState: PlayerState, onShowSettings: @escaping () -> Void) {
        self.playerState = playerState
        self.onShowSettings = onShowSettings
        _displayedTrack = State(initialValue: playerState.currentTrack)
        _displayedImage = State(initialValue: playerState.albumArtImage)
    }

    private var isApple: Bool { themeSettings.active == .apple }

    private var contentWidth: CGFloat {
        isApple ? AppleTheme.popoverWidth : PixelTheme.popoverWidth
    }

    private var slideWidth: CGFloat { contentWidth + 30 }

    private var nearingEnd: Bool {
        let remaining = displayedTrack.duration - playerState.progress
        return remaining > 0 && remaining < 2.5
    }

    private var targetSpinnerSpeed: Double {
        guard playerState.isPlaying else { return 0 }
        if isApple && (isExiting || showIncoming) { return 0 }
        return nearingEnd ? 0 : 120
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, isApple ? 2 : 0)

            if isApple {
                appleMainSection
            } else {
                pixelMainSection
            }

            ProgressBarView(playerState: playerState,
                            accentColor: Color(playerState.accentColor),
                            theme: themeSettings.active)
                .padding(.horizontal, 14)
                .padding(.top, isApple ? 0 : 2)
                .padding(.bottom, isApple ? 6 : 2)

            ControlsView(
                playerState: playerState,
                accentColor: Color(playerState.accentColor),
                theme: themeSettings.active,
                onNextTap: { playerState.requestSkip(direction: 1) },
                onPrevTap: { playerState.requestSkip(direction: -1) }
            )
            .padding(.horizontal, isApple ? 14 : 10)
            .padding(.bottom, isApple ? 12 : 8)

            if showQueue {
                Rectangle().fill(Color(white: 1, opacity: 0.1)).frame(height: 1).padding(.horizontal, 10)
                QueueView(queue: playerState.queue, theme: themeSettings.active)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showQueue)
        .onChange(of: playerState.isPlaying) { _, _ in syncSpinner() }
        .onChange(of: playerState.progress) { _, _ in syncSpinner() }
        .onAppear { syncSpinner() }
        .onChange(of: playerState.skipExitDirection) { _, direction in
            guard let direction else { return }
            beginExit(direction: direction)
        }
        .onChange(of: playerState.currentTrack) { _, newTrack in
            guard newTrack.id != displayedTrack.id else { return }
            let direction = playerState.skipDirection ?? 1
            let art = artForTrack(newTrack)
            if isExiting {
                enterWith(newTrack, image: art, direction: direction)
            } else {
                runTransition(to: newTrack, image: art, direction: direction)
            }
        }
        .onChange(of: playerState.albumArtImage) { _, img in
            guard playerState.albumArtTrackID == playerState.currentTrack.id else { return }
            if showIncoming, playerState.albumArtTrackID == incomingTrack.id {
                incomingImage = img
            } else if !showIncoming, playerState.albumArtTrackID == displayedTrack.id {
                displayedImage = img
            }
        }
    }

    // MARK: - Apple layout

    private var appleMainSection: some View {
        ZStack {
            cdAndInfo(track: displayedTrack, image: displayedImage)
                .id("out-\(displayedTrack.id)")
                .offset(x: outgoingX)

            if showIncoming {
                cdAndInfo(track: incomingTrack, image: incomingImage)
                    .id("in-\(incomingTrack.id)")
                    .offset(x: incomingX)
            }
        }
        .frame(width: contentWidth)
        .clipped()
    }

    // MARK: - Pixel layout

    private var pixelMainSection: some View {
        VStack(spacing: 4) {
            PixelTurntableView(width: contentWidth - 6)

            ZStack {
                pixelTrackInfo(track: displayedTrack)
                    .offset(x: outgoingX)

                if showIncoming {
                    pixelTrackInfo(track: incomingTrack)
                        .offset(x: incomingX)
                }
            }
            .frame(width: contentWidth)
            .clipped()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            if isApple {
                topBarButton("music.note.list") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { showQueue.toggle() }
                }
                Spacer()
                topBarButton("gearshape") { onShowSettings() }
            } else {
                pixelTopBarButton("pixel_queue", fallback: "music.note.list") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { showQueue.toggle() }
                }
                Spacer()
                pixelTopBarButton("pixel_settings", fallback: "gearshape") { onShowSettings() }
            }
        }
    }

    private func topBarButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 1, opacity: 0.65))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pixelTopBarButton(_ named: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let img = NSImage(named: named) {
                let aspect = img.size.width / max(img.size.height, 1)
                let h = PixelTheme.topBarIconHeight
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: h * aspect, height: h)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PixelTheme.primaryTextColor)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private func cdAndInfo(track: Track, image: NSImage?) -> some View {
        VStack(spacing: 0) {
            SpinningCDView(image: image, diameter: AppleTheme.cdDiameter)
                .padding(.bottom, 14)

            VStack(spacing: 3) {
                MarqueeText(text: track.title, font: .system(size: 14, weight: .semibold), color: .white)
                    .textSelection(.enabled)
                MarqueeText(text: track.artist, font: .system(size: 12), color: Color(white: 1, opacity: 0.6))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: contentWidth)
    }

    private func pixelTrackInfo(track: Track) -> some View {
        VStack(spacing: 2) {
            MarqueeText(text: track.title, font: PixelTheme.titleFont, color: PixelTheme.primaryTextColor)
                .textSelection(.enabled)
            MarqueeText(text: track.artist, font: PixelTheme.artistFont, color: PixelTheme.secondaryTextColor)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .frame(width: contentWidth)
    }

    // MARK: - Spinner

    private func syncSpinner() {
        VinylSpinner.shared.targetDegreesPerSecond = targetSpinnerSpeed
    }

    // MARK: - Transitions

    private func artForTrack(_ track: Track) -> NSImage? {
        if playerState.albumArtTrackID == track.id { return playerState.albumArtImage }
        return track.albumArtURL.flatMap { AlbumArtLoader.shared.image(for: $0) }
    }

    private func beginExit(direction: CGFloat) {
        guard !isExiting && !showIncoming else { return }
        playerState.skipExitDirection = nil
        isExiting = true
        if isApple { VinylSpinner.shared.targetDegreesPerSecond = 0 }
        withAnimation(.easeOut(duration: Transition.slideOut)) {
            outgoingX = -direction * slideWidth
        }
    }

    private func enterWith(_ newTrack: Track, image: NSImage?, direction: CGFloat) {
        incomingTrack = newTrack
        incomingImage = image
        incomingX = direction * slideWidth
        showIncoming = true
        isExiting = false
        withAnimation(.easeOut(duration: Transition.slideIn).delay(Transition.slideInDelay)) {
            incomingX = 0
        }
        finalise(after: Transition.settle)
    }

    private func runTransition(to newTrack: Track, image: NSImage?, direction: CGFloat) {
        guard !showIncoming else {
            incomingTrack = newTrack
            incomingImage = image
            return
        }

        incomingTrack = newTrack
        incomingImage = image
        incomingX = direction * slideWidth
        showIncoming = true
        if isApple { VinylSpinner.shared.targetDegreesPerSecond = 0 }

        withAnimation(.easeOut(duration: Transition.slideOut)) {
            outgoingX = -direction * slideWidth
        }
        withAnimation(.easeOut(duration: Transition.slideIn).delay(Transition.slideInDelay)) {
            incomingX = 0
        }
        finalise(after: Transition.settle)
    }

    private func finalise(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            displayedTrack = incomingTrack
            displayedImage = incomingImage ?? artForTrack(incomingTrack)
            outgoingX = 0
            showIncoming = false
            isExiting = false
            playerState.skipDirection = nil
            syncSpinner()
        }
    }
}
