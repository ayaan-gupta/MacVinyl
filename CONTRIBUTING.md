# Contributing

Thanks for your interest in Vinyl!

## Setup

1. Fork and clone the repo.
2. Copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and add your Spotify Client ID (see [README](README.md)).
3. Open `Vinyl.xcodeproj` in Xcode and build.

## Pull requests

- Keep changes focused — one feature or fix per PR.
- Match existing code style (SwiftUI, minimal comments).
- Test on macOS with Spotify running before submitting.

## CI

Pull requests trigger a build check via GitHub Actions. You don't need to run CI locally, but `xcodebuild -scheme Vinyl -configuration Debug build` should succeed.
