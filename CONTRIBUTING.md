# Contributing

## Update versions manually

```bash
./update.sh
```

This fetches the latest release from GitHub and overwrites `versions.json` with the new version and hashes. The script exits silently if the version is already up to date.

## Build locally

```bash
nix build
./result/bin/codex --version
```
