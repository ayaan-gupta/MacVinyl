<p align="center">
  <img src="assets/sir.png" alt="Vinyl" width="720">
</p>

<p align="center">
  <a href="https://github.com/ayaan-gupta/Vinyl"><img src="https://img.shields.io/badge/Open%20Source-%E2%9D%A4-2ea594?style=for-the-badge&labelColor=555555" alt="Open Source"></a>
  <a href="https://github.com/ayaan-gupta/Vinyl/releases"><img src="https://img.shields.io/badge/downloads-Releases-brightgreen?style=for-the-badge&labelColor=555555" alt="downloads"></a>
</p>

<p align="center">
  A macOS menu bar app that controls Spotify with a vinyl turntable UI.<br>
  Pixel and Apple themes, queue view, album art, and playback controls.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center">
  <img src="assets/preview.png" alt="Vinyl pixel theme" width="420">
</p>

<p align="center"><em>Pixel theme</em></p>

## Download (recommended)

1. Go to [Releases](https://github.com/ayaan-gupta/Vinyl/releases) and download `Vinyl.zip` for the latest version.
2. Unzip and drag **Vinyl.app** to Applications.
3. **First launch:** macOS will block the app because it is not signed with an Apple Developer certificate. Either:
   - **Right-click** Vinyl.app → **Open** → **Open** again in the dialog, or
   - Run in Terminal:
     ```bash
     xattr -cr /Applications/Vinyl.app
     open /Applications/Vinyl.app
     ```
4. Install and open the **Spotify desktop app** (Premium recommended for queue features).
5. Click the Vinyl menu bar icon → **Settings** → **Connect to Spotify**.
6. Grant permissions when prompted:
   - **Automation**: control Spotify playback
   - **Accessibility**: optional, for global media key interception

> **Why the extra step?** Apple requires a paid Developer Program membership ($99/year) to sign and notarize apps so they open with a double-click and no warning. Vinyl is distributed unsigned to avoid that cost. You only need to approve it once.

## Requirements

- macOS 14.0 or later
- [Spotify desktop app](https://www.spotify.com/download/mac/)
- Spotify Premium (recommended for queue and Web API playback features)

## Permissions

| Permission | Purpose |
|------------|---------|
| Automation (Apple Events) | Play/pause, skip, read track info from Spotify |

## Building from source

For developers who want to modify Vinyl or build locally.

### 1. Clone the repo

```bash
git clone https://github.com/ayaan-gupta/Vinyl.git
cd Vinyl
```

### 2. Spotify Developer setup

Vinyl uses Spotify OAuth with **PKCE**. You only need a **Client ID**, not a client secret.

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and log in.
2. **Create app** → name it (e.g. "Vinyl Local").
3. Open the app → **Settings**:
   - Under **Redirect URIs**, add: `vinyl://callback`
   - Save.
4. Copy the **Client ID**.

### 3. Configure secrets

```bash
cp Secrets.xcconfig.example Secrets.xcconfig
```

Edit `Secrets.xcconfig` and replace the placeholder with your Client ID:

```
SPOTIFY_CLIENT_ID = your_client_id_here
```

`Secrets.xcconfig` is gitignored and never committed.

### 4. Build and run

Open `Vinyl.xcodeproj` in Xcode 15+ and press **Run** (⌘R).

Or from the command line:

```bash
xcodebuild -scheme Vinyl -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Vinyl.app
```

## Publishing releases (maintainers)

Releases are built automatically when you push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Before the first release, add a GitHub Actions secret:

1. Repo → **Settings** → **Secrets and variables** → **Actions**
2. New secret: `SPOTIFY_CLIENT_ID` = your Spotify app's Client ID (the same one used for end-user OAuth)

The workflow builds Vinyl, embeds the Client ID, zips the app, and attaches it to the GitHub Release. End users who download the release do **not** need their own Spotify Developer app.

### Optional: Apple Developer signing

If you join the [Apple Developer Program](https://developer.apple.com/programs/), you can sign and notarize releases so users don't need the right-click → Open workaround. That requires adding signing certificates to GitHub Actions and is not set up by default.

## Project structure

```
Vinyl/
├── assets/                 # README cover art and screenshots
├── Vinyl/                  # App source
│   ├── SpotifyBridge/      # AppleScript + Web API + OAuth
│   ├── Views/              # SwiftUI views
│   ├── Services/           # Polling, album art, spinner
│   └── Theme/              # Apple + Pixel themes
├── Config/Vinyl.xcconfig   # Build config (includes Secrets)
├── Secrets.xcconfig.example
└── .github/workflows/      # CI + release automation
```

## Third-party assets

- **Pixelify Sans** font: [SIL Open Font License 1.1](Vinyl/Fonts/OFL.txt)
- Spotify integration subject to [Spotify Developer Terms](https://developer.spotify.com/terms). Vinyl is not affiliated with Spotify.

## License

MIT. See [LICENSE](LICENSE).
