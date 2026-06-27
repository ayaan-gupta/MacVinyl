#!/usr/bin/env bash
# Removes exposed Spotify credentials from git history.
# Run ONCE before making the repo public, after rotating credentials on Spotify.
set -euo pipefail

echo "This script rewrites git history to redact old Spotify credentials."
echo "You MUST rotate/delete the old keys on Spotify's dashboard first."
echo ""
read -r -p "Have you rotated your Spotify credentials? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborting. Rotate credentials first, then re-run."
  exit 1
fi

if ! command -v git-filter-repo &>/dev/null; then
  echo "Install git-filter-repo: brew install git-filter-repo"
  exit 1
fi

read -r -p "Old Client ID to redact: " OLD_ID
read -r -p "Old Client Secret to redact (if any): " OLD_SECRET

REPLACEMENTS="$(mktemp)"
echo "${OLD_ID}==>REDACTED_CLIENT_ID" >> "$REPLACEMENTS"
if [[ -n "$OLD_SECRET" ]]; then
  echo "${OLD_SECRET}==>REDACTED_CLIENT_SECRET" >> "$REPLACEMENTS"
fi

git filter-repo --replace-text "$REPLACEMENTS" --force
rm "$REPLACEMENTS"

# git-filter-repo removes remotes by design — restore origin for push.
REMOTE_URL="${VINYL_ORIGIN_URL:-https://github.com/ayaan-gupta/Vinyl.git}"
if ! git remote get-url origin &>/dev/null; then
  git remote add origin "$REMOTE_URL"
  echo "Re-added origin remote: $REMOTE_URL"
fi

echo ""
echo "History rewritten. Force-push to update GitHub:"
echo "  git push --force origin main"
echo ""
echo "If the repo was ever public, the old keys are still compromised — keep them deleted on Spotify."
