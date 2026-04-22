![CI](https://github.com/tttol/nix-codex/actions/workflows/update.yaml/badge.svg)
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

`versions.json` is updated automatically every day via GitHub Actions.
