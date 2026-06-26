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
        let v = NSVisualEffectView(); v.material = material
        v.blendingMode = blendingMode; v.state = .active; return v
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
        .background(GeometryReader { geo in
            Color.clear.preference(key: SizePreferenceKey.self, value: geo.size)
        })
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
                    Image(nsImage: img).resizable().scaledToFill()
                        .blur(radius: 48, opaque: true)
                        .overlay(Color.black.opacity(0.42))
                } else {
                    LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                                   startPoint: .top, endPoint: .bottom)
                }
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).opacity(0.13)
            }
            .animation(.easeInOut(duration: 0.9), value: playerState.albumArtImage != nil)
        case .pixel:
            if let bg = NSImage(named: "pixel_background") {
                Image(nsImage: bg).interpolation(.none).resizable().scaledToFill()
            } else {
                Color(red: 0.12, green: 0.09, blue: 0.06, alpha: 1)
            }
        }
    }
}

// MARK: - Player content with slide transitions

struct PlayerContentView: View {
    @ObservedObject var playerState: PlayerState
    @EnvironmentObject var themeSettings: ThemeSettings
    let onShowSettings: () -> Void

    // ── Displayed (what the user sees) ────────────────────────────────────
    @State private var displayedTrack: Track
    @State private var displayedImage: NSImage?

    // ── Transition state ──────────────────────────────────────────────────
    @State private var outgoingX: CGFloat   = 0
    @State private var incomingX: CGFloat   = 0
    @State private var incomingTrack: Track = .empty
    @State private var incomingImage: NSImage? = nil
    @State private var showIncoming: Bool   = false

    /// 1 = next (current slides left, new arrives from right)
    /// -1 = previous (current slides right, new arrives from left)
    @State private var pendingDirection: CGFloat = 1

    @State private var showQueue = false

    init(playerState: PlayerState, onShowSettings: @escaping () -> Void) {
        self.playerState = playerState
        self.onShowSettings = onShowSettings
        _displayedTrack = State(initialValue: playerState.currentTrack)
        _displayedImage = State(initialValue: playerState.albumArtImage)
    }

    // ── Computed ───────────────────────────────────────────────────────────

    private var isApple: Bool { themeSettings.active == .apple }

    private var contentWidth: CGFloat {
        isApple ? AppleTheme.popoverWidth : PixelTheme.popoverWidth
    }

    private var slideWidth: CGFloat { contentWidth + 40 }

    private var nearingEnd: Bool {
        let remaining = displayedTrack.duration - playerState.progress
        return remaining > 0 && remaining < 2.5
    }

    private var targetSpinnerSpeed: Double {
        guard playerState.isPlaying else { return 0 }
        // Only freeze spinner during the Apple-theme CD slide; pixel record keeps spinning
        // because PixelTurntableView manages its own record transition independently.
        if isApple && showIncoming { return 0 }
        return nearingEnd ? 0 : 120
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)

            if isApple {
                // ── Apple theme: CD + info slide together ─────────────────
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
            } else {
                // ── Pixel theme: turntable handles record slide internally ─
                PixelTurntableView(
                    pendingDirection: pendingDirection,
                    width: PixelTheme.popoverWidth - 10
                )
                .padding(.top, 4)
                .padding(.bottom, 6)

                // Track info slides independently (text only)
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
                .padding(.bottom, 4)
            }

            ProgressBarView(playerState: playerState,
                            accentColor: Color(playerState.accentColor),
                            theme: themeSettings.active)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            ControlsView(playerState: playerState,
                         accentColor: Color(playerState.accentColor),
                         theme: themeSettings.active,
                         onNextTap: { pendingDirection =  1 },
                         onPrevTap: { pendingDirection = -1 })
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            if showQueue {
                Rectangle().fill(Color(white: 1, opacity: 0.1)).frame(height: 1).padding(.horizontal, 10)
                QueueView(queue: playerState.queue, theme: themeSettings.active)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showQueue)
        // ── React to state changes ───────────────────────────────────────
        .onChange(of: playerState.isPlaying) { _, _ in syncSpinner() }
        .onChange(of: playerState.progress)  { _, _ in syncSpinner() }
        .onAppear { syncSpinner() }
        .onChange(of: playerState.currentTrack) { _, newTrack in
            guard newTrack.id != displayedTrack.id else { return }
            if showIncoming {
                incomingTrack = newTrack
                incomingImage = playerState.albumArtImage
            } else {
                triggerTransition(to: newTrack, image: playerState.albumArtImage)
            }
        }
        .onChange(of: playerState.albumArtImage) { _, img in
            if showIncoming { incomingImage = img }
            else            { displayedImage = img }
        }
    }

    private func syncSpinner() {
        VinylSpinner.shared.targetDegreesPerSecond = targetSpinnerSpeed
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
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pixelTopBarButton(_ named: String, fallback: String,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let img = NSImage(named: named) {
                let aspect = img.size.width / max(img.size.height, 1)
                let h: CGFloat = 20
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
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private func cdAndInfo(track: Track, image: NSImage?) -> some View {
        VStack(spacing: 0) {
            SpinningCDView(image: image, diameter: AppleTheme.cdDiameter)
                .padding(.bottom, 14)

            VStack(spacing: 3) {
                MarqueeText(
                    text: track.title,
                    font: .system(size: 14, weight: .semibold),
                    color: .white
                )
                .textSelection(.enabled)

                MarqueeText(
                    text: track.artist,
                    font: .system(size: 12),
                    color: Color(white: 1, opacity: 0.6)
                )
                .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: contentWidth)
    }

    private func pixelTrackInfo(track: Track) -> some View {
        VStack(spacing: 3) {
            MarqueeText(
                text: track.title,
                font: PixelTheme.titleFont,
                color: PixelTheme.primaryTextColor
            )
            .textSelection(.enabled)

            MarqueeText(
                text: track.artist,
                font: PixelTheme.artistFont,
                color: PixelTheme.secondaryTextColor
            )
            .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .frame(width: contentWidth)
    }

    // MARK: - Transition engine

    private func triggerTransition(to newTrack: Track, image: NSImage?) {
        let dir = pendingDirection

        incomingTrack = newTrack
        incomingImage = image

        if isApple {
            // Apple theme: slide the whole CD + info block
            incomingX    = dir * slideWidth
            showIncoming = true

            VinylSpinner.shared.targetDegreesPerSecond = 0

            withAnimation(.easeIn(duration: 0.28)) { outgoingX = -dir * slideWidth }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) { incomingX = 0 }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                displayedTrack   = incomingTrack
                displayedImage   = incomingImage
                outgoingX        = 0
                showIncoming     = false
                pendingDirection = 1
                syncSpinner()
            }
        } else {
            // Pixel theme: PixelTurntableView handles the record slide internally.
            // Only slide the track info text here.
            incomingX    = dir * slideWidth
            showIncoming = true

            withAnimation(.easeIn(duration: 0.28)) { outgoingX = -dir * slideWidth }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) { incomingX = 0 }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                displayedTrack   = incomingTrack
                displayedImage   = incomingImage
                outgoingX        = 0
                showIncoming     = false
                pendingDirection = 1
            }
        }
    }
}
