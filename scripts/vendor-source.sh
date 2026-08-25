#!/usr/bin/env bash
# Pulls a pinned snapshot of ChannelForge's apps/api + packages into vendor/
# (gitignored — this is a derived artifact, not source of truth).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNELFORGE_REPO="${CHANNELFORGE_REPO:-$ROOT/../channelforge}"
PINNED_COMMIT="$(cat "$ROOT/PINNED_COMMIT")"
DEST="$ROOT/vendor"

if [[ ! -d "$CHANNELFORGE_REPO/.git" ]]; then
  echo "error: CHANNELFORGE_REPO ($CHANNELFORGE_REPO) is not a git checkout" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
git -C "$CHANNELFORGE_REPO" archive "$PINNED_COMMIT" apps/api packages | tar -x -C "$DEST"

echo "Vendored ChannelForge @ ${PINNED_COMMIT:0:12} into $DEST"
