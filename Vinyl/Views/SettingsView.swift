import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var themeSettings: ThemeSettings
    @ObservedObject var playerState: PlayerState
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
                        } else if !SpotifyConfig.isConfigured {
                            Text("Spotify connection is unavailable in this build.")
                                .font(.footnote).foregroundStyle(.secondary)
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
        .frame(minHeight: 280)
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
