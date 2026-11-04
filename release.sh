#!/bin/bash
# Publishes a new version for the auto-updater.
# Usage: ./release.sh "what changed"
# Bumps VERSION by 0.01 (1.00 -> 1.01 -> 1.02), builds, zips, and creates a GitHub release.
set -e
cd "$(dirname "$0")"

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login"; exit 1; }

REPO=$(tr -d '[:space:]' < UPDATE_REPO)
case "$REPO" in OWNER/*) echo "Edit the UPDATE_REPO file first (your GitHub repo, like yourname/MyBrowser)."; exit 1;; esac

OLD=$(tr -d '[:space:]' < VERSION)
MAJOR=${OLD%%.*}
MINOR=${OLD#*.}
NEW="$MAJOR.$(printf '%02d' $((10#$MINOR + 1)))"
echo "$NEW" > VERSION

./build_app.sh

ZIP="MyBrowser-$NEW.zip"
rm -f "$ZIP"
ditto -c -k --keepParent MyBrowser.app "$ZIP"

gh release create "v$NEW" "$ZIP" --repo "$REPO" --title "MyBrowser $NEW" --notes "${1:-MyBrowser $NEW}"
echo "Released $NEW. Installed copies will offer it next time they check."
