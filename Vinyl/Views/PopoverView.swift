import SwiftUI
import AppKit

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Measured player heights with and without the queue — drives pixel background clipping.
struct PixelPopoverHeights: Equatable {
    var collapsed: CGFloat = 0
    var expanded: CGFloat = 0
}

struct PixelPopoverHeightsKey: PreferenceKey {
    static let defaultValue = PixelPopoverHeights()
    static func reduce(value: inout PixelPopoverHeights, nextValue: () -> PixelPopoverHeights) {
        let next = nextValue()
        if next.collapsed > 0 { value.collapsed = next.collapsed }
        if next.expanded > 0 { value.expanded = next.expanded }
    }
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
    var onSizeChange: ((CGSize, Bool) -> Void)?

    @State private var showSettings = false
    @State private var showQueue = false
    @State private var pixelHeights = PixelPopoverHeights()
    @State private var queueResizeInProgress = false
    @State private var lastContentHeight: CGFloat = 0

    private var contentWidth: CGFloat {
        themeSettings.active == .pixel ? PixelTheme.popoverWidth : AppleTheme.popoverWidth
    }

    var body: some View {
        ZStack(alignment: .top) {
            BackgroundView(
                playerState: playerState,
                theme: themeSettings.active,
                isSettings: showSettings,
                pixelHeights: pixelHeights
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Group {
                if showSettings {
                    SettingsView(playerState: playerState,
                                 onDismiss: { withAnimation { showSettings = false } })
                        .environmentObject(themeSettings)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.asymmetric(insertion: .move(edge: .trailing),
                                                removal:   .move(edge: .trailing)))
                } else {
                    PlayerContentView(
                        playerState: playerState,
                        showQueue: $showQueue,
                        onShowSettings: { withAnimation { showSettings = true } },
                        onToggleQueue: { toggleQueue() },
                        onMeasured: { handleMeasured($0) }
                    )
                    .environmentObject(themeSettings)
                    .id(themeSettings.active)
                    .transition(.asymmetric(insertion: .move(edge: .leading),
                                            removal:   .move(edge: .leading)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSettings)
            .frame(width: contentWidth, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                if showSettings {
                    GeometryReader { geo in
                        Color.clear.preference(key: SizePreferenceKey.self, value: geo.size)
                    }
                }
            }
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(PixelPopoverHeightsKey.self) { pixelHeights = $0 }
        // SettingsView is the only emitter of SizePreferenceKey (see the conditional
        // background above). Player content is sized via handleMeasured instead.
        .onPreferenceChange(SizePreferenceKey.self) { size in
            guard size.height > 10 else { return }
            guard !queueResizeInProgress else { return }
            lastContentHeight = size.height
            onSizeChange?(CGSize(width: contentWidth, height: size.height), false)
        }
        .onChange(of: themeSettings.active) { _, _ in
            // Collapse the queue and clear any in-flight queue animation so the
            // freshly-rebuilt PlayerContentView measures cleanly. handleMeasured
            // (a direct per-instance callback, immune to the last-writer-wins
            // SizePreferenceKey reduce) will resize the panel to the new theme.
            showQueue = false
            queueResizeInProgress = false
        }
        .onChange(of: showSettings) { _, showing in
            if !showing {
                queueResizeInProgress = false
            }
        }
    }

    /// Resize driven by the live player-content measurement. Runs for every player
    /// size change except while a queue open/close animation owns the panel.
    private func handleMeasured(_ size: CGSize) {
        guard size.height > 10 else { return }
        lastContentHeight = size.height
        guard !queueResizeInProgress else { return }
        onSizeChange?(CGSize(width: contentWidth, height: size.height), false)
    }

    private func toggleQueue() {
        // Set the guard *before* showQueue changes so the content growing/shrinking
        // cannot trigger a non-animated snap before the animated resize runs. This
        // makes open and close symmetric.
        queueResizeInProgress = true
        let open = !showQueue
        showQueue = open
        if open { PollingService.shared.refreshQueueNow() }
        applyQueuePanelSize(open: open)
    }

    private func applyQueuePanelSize(open: Bool) {
        if open {
            // Wait for layout so expanded height is measured before animating.
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    let collapsed = pixelHeights.collapsed > 10 ? pixelHeights.collapsed : lastContentHeight
                    let expanded = pixelHeights.expanded > 10
                        ? pixelHeights.expanded
                        : collapsed + PixelTheme.estimatedQueueSectionHeight
                    guard expanded > 10 else { queueResizeInProgress = false; return }
                    resizePanel(to: expanded, animated: true)
                }
            }
        } else {
            let collapsed = pixelHeights.collapsed > 10 ? pixelHeights.collapsed : lastContentHeight
            guard collapsed > 10 else { queueResizeInProgress = false; return }
            resizePanel(to: collapsed, animated: true)
        }
    }

    private func resizePanel(to height: CGFloat, animated: Bool) {
        guard height > 10 else { return }
        queueResizeInProgress = true
        onSizeChange?(CGSize(width: contentWidth, height: height), animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            queueResizeInProgress = false
        }
    }
}

// MARK: - Background

private struct BackgroundView: View {
    @ObservedObject var playerState: PlayerState
    let theme: AppTheme
    var isSettings: Bool = false
    var pixelHeights: PixelPopoverHeights = PixelPopoverHeights()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            switch theme {
            case .apple:
                AppleAlbumBackground(
                    accent: playerState.accentColor,
                    image: playerState.albumArtImage
                )
                .frame(width: w, height: h)

            case .pixel:
                if isSettings {
                    Color(red: 0.12, green: 0.09, blue: 0.06, alpha: 1)
                        .frame(width: w, height: h)
                } else if let bg = NSImage(named: "pixel_background") {
                    let collapsed = pixelHeights.collapsed > 0 ? pixelHeights.collapsed : h
                    let expanded = pixelHeights.expanded > 0
                        ? pixelHeights.expanded
                        : collapsed + PixelTheme.estimatedQueueSectionHeight

                    Image(nsImage: bg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: expanded)
                        .frame(width: w, height: h, alignment: .top)
                        .clipped()
                        .transaction { $0.animation = nil }
                } else {
                    Color(red: 0.12, green: 0.09, blue: 0.06, alpha: 1)
                        .frame(width: w, height: h)
                }
            }
        }
    }
}

/// Vibrant glass backdrop — one layer behind all content, sized to the popover.
private struct AppleAlbumBackground: View {
    let accent: NSColor
    let image: NSImage?

    var body: some View {
        ZStack {
            Color(white: 0.04)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: AppleTheme.backdropBlurRadius, opaque: true)
                    .saturation(AppleTheme.backdropSaturation)
                    .brightness(AppleTheme.backdropBrightness)
            }

            LinearGradient(
                colors: gradientColors,
                startPoint: .bottom,
                endPoint: .top
            )
            .opacity(image != nil ? 0.58 : 0.78)

            RadialGradient(
                colors: [glowColor.opacity(0.34), glowColor.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 220
            )

            Color.black.opacity(0.14)

            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.36)
        }
        .animation(.easeInOut(duration: 0.9), value: image != nil)
        .animation(.easeInOut(duration: 1.0), value: accent.description)
    }

    private var gradientColors: [Color] {
        AppleTheme.backdropGradientColors(from: accent).linear.map { Color($0) }
    }

    private var glowColor: Color {
        Color(AppleTheme.backdropGradientColors(from: accent).glow)
    }
}

// MARK: - Player content

struct PlayerContentView: View {
    @ObservedObject var playerState: PlayerState
    @Binding var showQueue: Bool
    @EnvironmentObject var themeSettings: ThemeSettings
    let onShowSettings: () -> Void
    let onToggleQueue: () -> Void
    let onMeasured: (CGSize) -> Void

    @State private var displayedTrack: Track
    @State private var displayedImage: NSImage?

    @State private var outgoingX: CGFloat = 0
    @State private var incomingX: CGFloat = 0
    @State private var incomingTrack: Track = .empty
    @State private var incomingImage: NSImage? = nil
    @State private var showIncoming = false
    @State private var isExiting = false
    @State private var lastTrackID: String = ""
    @State private var storedCollapsedHeight: CGFloat = 0
    @State private var storedExpandedHeight: CGFloat = 0

    private enum Transition {
        static let slideOut: Double = 0.09
        static let slideInDelay: Double = 0.04
        static let slideIn: Double = 0.10
        static let settle: Double = 0.15
    }

    init(playerState: PlayerState,
         showQueue: Binding<Bool>,
         onShowSettings: @escaping () -> Void,
         onToggleQueue: @escaping () -> Void,
         onMeasured: @escaping (CGSize) -> Void) {
        self.playerState = playerState
        _showQueue = showQueue
        self.onShowSettings = onShowSettings
        self.onToggleQueue = onToggleQueue
        self.onMeasured = onMeasured
        _displayedTrack = State(initialValue: playerState.currentTrack)
        _displayedImage = State(initialValue: playerState.albumArtImage)
        _lastTrackID = State(initialValue: playerState.currentTrack.id)
    }

    private var isApple: Bool { themeSettings.active == .apple }

    private var contentWidth: CGFloat {
        isApple ? AppleTheme.popoverWidth : PixelTheme.popoverWidth
    }

    /// Inner width for title/artist marquee rows (content width minus horizontal padding).
    private var marqueeWidth: CGFloat { contentWidth - 28 }

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
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
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
                    QueueView(playerState: playerState, theme: themeSettings.active)
                        .padding(.bottom, 6)
                }
            }

            // Floated on the shared background — no separate header container.
            topBar
                .padding(.horizontal, 10)
                .padding(.top, 6)
        }
        .onChange(of: themeSettings.active) { _, _ in
            storedCollapsedHeight = 0
            storedExpandedHeight = 0
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        recordPopoverHeight(geo.size.height)
                        onMeasured(geo.size)
                    }
                    .onChange(of: geo.size) { _, size in
                        recordPopoverHeight(size.height)
                        onMeasured(size)
                    }
                    .preference(
                        key: PixelPopoverHeightsKey.self,
                        value: PixelPopoverHeights(
                            collapsed: showQueue ? storedCollapsedHeight : geo.size.height,
                            expanded: showQueue ? geo.size.height : storedExpandedHeight
                        )
                    )
            }
        }
        .onChange(of: playerState.isPlaying) { _, _ in syncSpinner() }
        .onChange(of: playerState.progress) { _, _ in syncSpinner() }
        .onAppear { syncSpinner() }
        .onChange(of: playerState.skipExitDirection) { _, direction in
            guard let direction else { return }
            beginExit(direction: direction)
        }
        .onChange(of: playerState.currentTrack) { _, newTrack in
            guard newTrack.id != lastTrackID else { return }
            let direction = playerState.skipAnimationDirection(from: lastTrackID, to: newTrack.id)
            lastTrackID = newTrack.id
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

    // MARK: - Popover height measurement

    private func recordPopoverHeight(_ height: CGFloat) {
        if showQueue {
            storedExpandedHeight = height
        } else {
            storedCollapsedHeight = height
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
        .padding(.top, 30)
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
        .padding(.top, PixelTheme.topBarClearance)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            if isApple {
                topBarButton("music.note.list") { toggleQueue() }
                Spacer()
                topBarButton("gearshape") { onShowSettings() }
            } else {
                pixelTopBarButton("pixel_queue", fallback: "music.note.list") { toggleQueue() }
                Spacer()
                pixelTopBarButton("pixel_settings", fallback: "gearshape") { onShowSettings() }
            }
        }
    }

    private func toggleQueue() {
        onToggleQueue()
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
                MarqueeText(text: track.title, font: .system(size: 14, weight: .semibold), color: .white, width: marqueeWidth)
                    .textSelection(.enabled)
                MarqueeText(text: track.artist, font: .system(size: 12), color: Color(white: 1, opacity: 0.6), width: marqueeWidth)
                    .textSelection(.enabled)
            }
            .frame(width: marqueeWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: contentWidth)
    }

    private func pixelTrackInfo(track: Track) -> some View {
        VStack(spacing: 2) {
            MarqueeText(
                text: track.title,
                font: PixelTheme.titleFont,
                color: PixelTheme.primaryTextColor,
                width: marqueeWidth,
                measurementFont: PixelTheme.titleMeasurementFont
            )
                .textSelection(.enabled)
            MarqueeText(
                text: track.artist,
                font: PixelTheme.artistFont,
                color: PixelTheme.secondaryTextColor,
                width: marqueeWidth,
                measurementFont: PixelTheme.artistMeasurementFont
            )
                .textSelection(.enabled)
        }
        .frame(width: marqueeWidth)
        .frame(maxWidth: .infinity)
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
            syncSpinner()
        }
    }
}
