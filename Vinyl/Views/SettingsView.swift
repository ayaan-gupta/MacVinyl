import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themeSettings: ThemeSettings
    @ObservedObject var playerState: PlayerState
    @ObservedObject private var hotkeyConfig = HotkeyConfig.shared
    var onDismiss: () -> Void

    private var contentWidth: CGFloat {
        themeSettings.active == .pixel ? PixelTheme.popoverWidth : AppleTheme.popoverWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 12)).hidden()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Theme ─────────────────────────────────────────
                    sectionHeader("Theme", icon: "paintpalette")

                    HStack(spacing: 10) {
                        ForEach(AppTheme.allCases) { theme in
                            ThemeCard(theme: theme, isSelected: themeSettings.active == theme) {
                                themeSettings.active = theme
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)

                    Divider()

                    // ── Keyboard Shortcuts ────────────────────────────
                    sectionHeader("Keyboard Shortcuts", icon: "keyboard")

                    VStack(spacing: 6) {
                        ForEach(HotkeyAction.allCases) { action in
                            HotkeyRow(action: action, config: hotkeyConfig)
                        }
                    }
                    .padding(.horizontal, 14)

                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            hotkeyConfig.resetToDefaults()
                            HotkeyService.shared.installCustomMonitor()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 16)

                    Divider()

                    // ── Spotify ───────────────────────────────────────
                    sectionHeader("Spotify", icon: "music.note")

                    Group {
                        if playerState.authState == .authenticated {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("Connected").font(.footnote)
                                Spacer()
                                Button("Disconnect") {
                                    SpotifyWebAPI.shared.signOut()
                                }
                                .font(.footnote).foregroundStyle(.red).buttonStyle(.plain)
                            }
                        } else if playerState.authState == .needsReauth {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Session expired — reconnect to restore queue and album art.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Button("Reconnect to Spotify") { SpotifyWebAPI.shared.startOAuthFlow() }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Connect to unlock album art queue.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Button("Connect to Spotify") { SpotifyWebAPI.shared.startOAuthFlow() }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: contentWidth)
        .frame(minHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}

// MARK: - Hotkey row with live recorder

struct HotkeyRow: View {
    let action: HotkeyAction
    @ObservedObject var config: HotkeyConfig

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack {
            Text(action.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press keys…" : config.binding(for: action).displayString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(
                                        isRecording ? Color.accentColor : Color(NSColor.separatorColor),
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isRecording)
        }
        .padding(.vertical, 3)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { self.stopRecording(); return nil }  // Esc = cancel
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !mods.isEmpty else { return event }
            let binding = HotkeyBinding(keyCode: event.keyCode, modifierRaw: mods.rawValue)
            self.config.set(binding, for: self.action)
            HotkeyService.shared.installCustomMonitor()
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}

// MARK: - Theme card

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme == .apple
                          ? Color(NSColor.windowBackgroundColor).opacity(0.6)
                          : Color(red: 0.16, green: 0.12, blue: 0.08, alpha: 1))
                    .frame(width: 80, height: 50)
                    .overlay(
                        Group {
                            if theme == .apple {
                                Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(.primary)
                            } else {
                                Text("♪").font(.system(size: 20))
                                    .foregroundStyle(Color(red: 0.56, green: 0.78, blue: 0.40, alpha: 1))
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                Text(theme.displayName).font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
