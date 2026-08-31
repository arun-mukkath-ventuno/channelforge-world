#!/usr/bin/env bash
# Pulls pinned snapshots of the three ecosystem repos into vendor/ (gitignored — these are
# derived artifacts, not source of truth):
#
#   vendor/apps/api, vendor/packages   ChannelForge, from ../channelforge (unchanged layout —
#                                      existing task-01 and world/app/Dockerfile COPY these paths
#                                      directly, so ChannelForge keeps its original top-level spot)
#   vendor/ssaiadserver/               packages + docker + migrations, from ../ssaiadserver
#   vendor/fastworldtv/                src + public, from ../fast-world-tv
#
# Each is pinned by its own PINNED_COMMIT_<SERVICE> file and pulled with `git archive` — never a
# moving branch. Override the source checkout path per repo with CHANNELFORGE_REPO /
# SSAIADSERVER_REPO / FASTWORLDTV_REPO.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

vendor_repo() {
  local name="$1" repo_var="$2" default_repo="$3" pinned_file="$4" dest="$5"
  shift 5
  local paths=("$@")

  local repo="${!repo_var:-$default_repo}"
  local pinned_commit
  pinned_commit="$(cat "$ROOT/$pinned_file")"

  if [[ ! -d "$repo/.git" ]]; then
    echo "error: $repo_var ($repo) is not a git checkout" >&2
    exit 1
  fi

  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$repo" archive "$pinned_commit" "${paths[@]}" | tar -x -C "$dest"
  echo "Vendored $name @ ${pinned_commit:0:12} into $dest"
}

vendor_repo "ChannelForge" CHANNELFORGE_REPO "$ROOT/../channelforge" \
  PINNED_COMMIT_CHANNELFORGE "$ROOT/vendor" apps/api packages

vendor_repo "ssaiadserver" SSAIADSERVER_REPO "$ROOT/../ssaiadserver" \
  PINNED_COMMIT_SSAIADSERVER "$ROOT/vendor/ssaiadserver" packages docker migrations package.json package-lock.json tsconfig.json tsconfig.base.json

vendor_repo "fast-world-tv" FASTWORLDTV_REPO "$ROOT/../fast-world-tv" \
  PINNED_COMMIT_FASTWORLDTV "$ROOT/vendor/fastworldtv" src public package.json pnpm-lock.yaml tsconfig.json next.config.ts postcss.config.mjs eslint.config.mjs
