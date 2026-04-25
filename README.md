![CI](https://github.com/tttol/nix-codex/actions/workflows/update.yaml/badge.svg)
![codex version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Ftttol%2Fnix-codex%2Fmain%2Fversions.json&query=%24.version&label=codex&color=blue)
# nix-codex
Nix flake for [OpenAI Codex CLI](https://github.com/openai/codex). macOS only.

## Why nix-codex?

- **Always up-to-date** — `versions.json` is updated automatically every day via GitHub Actions, so you always have access to the latest release.
- **Easy rollback** — every version is tagged, so switching to a previous version is a single command if a new release has a bug.

```bash
# Switch to a previous version instantly
nix run github:tttol/nix-codex/0.121.0
```

## Usage

```bash
# Run without installing
nix run github:tttol/nix-codex

# Run without installing and always fetch the latest flake
nix run github:tttol/nix-codex --refresh

# Install to user profile
nix profile install github:tttol/nix-codex

# Run a specific version
nix run github:tttol/nix-codex/0.122.0
```

## Update

A GitHub Actions workflow runs daily at **06:00 UTC** and performs the following steps:

1. Fetch the latest release from the [openai/codex](https://github.com/openai/codex/releases) GitHub Releases API
2. Compare with the current version in `versions.json`
3. If a new version is found, compute the SHA-256 hash of each macOS binary and overwrite `versions.json`
4. Commit and push the change with a version tag (e.g. `0.123.0`)

If the version is already up to date, the workflow exits without making any changes.

