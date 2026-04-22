# Plan: nix-codex の作成

## Context

OpenAI の Codex CLI（Rust 製）を Nix でパッケージングする。
macOS（x86_64 / aarch64）のみをサポートし、バージョン情報は単一の `versions.json` で管理する。

---

## プラットフォームマッピング

| Nix system | GitHub アセット名 |
|---|---|
| `x86_64-darwin` | `codex-x86_64-apple-darwin.tar.gz` |
| `aarch64-darwin` | `codex-aarch64-apple-darwin.tar.gz` |

URL パターン: `https://github.com/openai/codex/releases/download/rust-v{version}/codex-{triple}.tar.gz`

---

## ファイル構成

```
nix-codex/
├── .gitignore
├── LICENSE
├── README.md
├── flake.lock
├── flake.nix
├── update.sh
├── versions.json
└── .github/
    └── workflows/
        ├── check.yaml
        └── update.yaml
```

---

## versions.json スキーマ

```json
{
    "version": "0.122.0",
    "x86_64-darwin":  { "url": "...", "hash": "sha256-..." },
    "aarch64-darwin": { "url": "...", "hash": "sha256-..." }
}
```

ハッシュは `nix store prefetch-file --unpack --json` で取得した NAR ハッシュ。

---

## 各ファイルの実装内容

### update.sh

```bash
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
if [[ "$version" == "$current_version" ]]; then
    exit 0
fi

readonly x86_url="${DOWNLOAD_BASE}/${tag}/codex-x86_64-apple-darwin.tar.gz"
readonly aarch64_url="${DOWNLOAD_BASE}/${tag}/codex-aarch64-apple-darwin.tar.gz"

x86_hash=$(nix store prefetch-file --unpack --json "$x86_url" | jq -r '.hash')
aarch64_hash=$(nix store prefetch-file --unpack --json "$aarch64_url" | jq -r '.hash')

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
```

重要点：
- `curl` は macOS 標準で利用可能。`jq` は nix shebang で自動取得
- `GITHUB_TOKEN` を使って匿名レート制限（60req/時）を回避
- `--unpack` なしでアーカイブファイル自体のハッシュを取得（`fetchurl` 用）

### flake.nix

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sources = builtins.fromJSON (builtins.readFile ./versions.json);
          source = sources.${system};
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "codex";
            inherit (sources) version;

            src = pkgs.fetchurl { inherit (source) url hash; };

            nativeBuildInputs = [ pkgs.makeWrapper ];

            dontUnpack = true;

            installPhase = ''
              tar xzf $src
              install -Dm755 codex-* $out/bin/codex
            '';

            postFixup = ''
              wrapProgram $out/bin/codex \
                --argv0 codex \
                --set CODEX_DISABLE_AUTO_UPDATE 1
            '';

            dontStrip = true;

            meta = with pkgs.lib; {
              description = "OpenAI Codex CLI — an agentic coding assistant in your terminal";
              homepage = "https://github.com/openai/codex";
              license = licenses.asl20;
              mainProgram = "codex";
              platforms = systems;
            };
          };
        });
    };
}
```

### .github/workflows/update.yaml

```yaml
on:
  schedule:
    - cron: '0 6 * * *'   # 毎日 06:00 UTC
  workflow_dispatch:

jobs:
  update-sources:
    runs-on: macos-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@...
      - uses: cachix/install-nix-action@...
        with:
          github_access_token: ${{ github.token }}
      - id: update
        run: VERSION=$(bash update.sh | tail -1) && echo "version=$VERSION" >> "$GITHUB_OUTPUT"
        env:
          GITHUB_TOKEN: ${{ github.token }}
      - run: git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
      - run: git config user.name "github-actions[bot]"
      - run: git add versions.json
      - run: |
          if ! git diff --staged --quiet; then
            git commit -m "chore: update codex to ${{ steps.update.outputs.version }}"
            git tag "${{ steps.update.outputs.version }}"
            git push origin main "${{ steps.update.outputs.version }}"
          fi
```

### .github/workflows/check.yaml

```yaml
on:
  pull_request:
  push:
    branches: [main]

jobs:
  fmt-check:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@...
      - uses: cachix/install-nix-action@...
        with:
          github_access_token: ${{ github.token }}
      - run: nix run nixpkgs#nixfmt-rfc-style -- --check flake.nix

  build-and-test:
    strategy:
      matrix:
        os: [macos-latest, macos-13]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@...
      - uses: cachix/install-nix-action@...
        with:
          github_access_token: ${{ github.token }}
      - run: nix build -L
      - run: |
          version=$(./result/bin/codex --version 2>&1 | head -1)
          echo "$version" | grep -qF "$(jq -r .version versions.json)" \
            || { echo "Version check failed: $version"; exit 1; }
```

---

## 検証手順

```bash
# 1. update.sh を実行して versions.json を初期化
bash update.sh

# 2. デフォルトパッケージをビルド
nix build

# 3. バージョン確認
./result/bin/codex --version
```

---

## 注意事項

- `nix store prefetch-file --unpack` が使える Nix バージョンかを事前確認すること
- `CODEX_DISABLE_AUTO_UPDATE` の環境変数名は Codex ソースで要確認（存在しない場合は省略）
