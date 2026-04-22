#!/usr/bin/env nix
# shellcheck shell=bash
#! nix shell --inputs-from . nixpkgs#jq -c bash

set -euo pipefail

readonly RELEASES_API="https://api.github.com/repos/openai/codex/releases/latest"
readonly DOWNLOAD_BASE="https://github.com/openai/codex/releases/download"

curl_args=(-fsSL -H "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

tag=$(curl "${curl_args[@]}" "$RELEASES_API" | jq -r '.tag_name')
version="${tag#rust-v}"

current_version=$(jq -r '.version' versions.json 2>/dev/null || true)
echo "latest codex version=$version, current version=$current_version"
if [[ "$version" == "$current_version" ]]; then
    echo "The codex version is already latest."
    exit 0
fi

readonly x86_url="${DOWNLOAD_BASE}/${tag}/codex-x86_64-apple-darwin.tar.gz"
readonly aarch64_url="${DOWNLOAD_BASE}/${tag}/codex-aarch64-apple-darwin.tar.gz"

x86_hash=$(nix store prefetch-file --json "$x86_url" | jq -r '.hash')
aarch64_hash=$(nix store prefetch-file --json "$aarch64_url" | jq -r '.hash')

jq -n \
    --arg version      "$version" \
    --arg x86_url      "$x86_url" \
    --arg x86_hash     "$x86_hash" \
    --arg aarch64_url  "$aarch64_url" \
    --arg aarch64_hash "$aarch64_hash" \
    '{
        version: $version,
        "x86_64-darwin":  { url: $x86_url,     hash: $x86_hash },
        "aarch64-darwin": { url: $aarch64_url,  hash: $aarch64_hash }
    }' > versions.json

echo "$version"
