# Security Policy

## Reporting a vulnerability

If you find a security issue, please open a [GitHub Security Advisory](https://github.com/ayaan-gupta/Vinyl/security/advisories/new) or email the maintainer privately. Do not post credentials or exploit details in public issues.

## Secrets

- **Never commit** `Secrets.xcconfig`, API keys, or OAuth tokens.
- Vinyl uses **PKCE** — only a Spotify **Client ID** is needed at build time. There is no client secret in the app.
- User OAuth tokens are stored locally in the macOS Keychain.

## If credentials were exposed in git history

If Spotify credentials were ever pushed to GitHub:

1. **Rotate immediately** — delete or reset the old Spotify Developer app credentials in the [Spotify Dashboard](https://developer.spotify.com/dashboard).
2. **Scrub git history** before making the repository public:

```bash
# Install: brew install git-filter-repo
git filter-repo --replace-text <(echo 'OLD_CLIENT_SECRET==>REDACTED') --force
git filter-repo --replace-text <(echo 'OLD_CLIENT_ID==>REDACTED') --force
git push --force origin main
```

Replace `OLD_CLIENT_ID` and `OLD_CLIENT_SECRET` with the actual values that were committed. After scrubbing, the old keys in history are useless — but you must still rotate them on Spotify's side since they may have been copied while the repo was accessible.

## Release builds

GitHub Actions release builds read `SPOTIFY_CLIENT_ID` from repository **Secrets** (Settings → Secrets and variables → Actions). This embeds your public Client ID into the app at build time. That is expected and safe with PKCE.
