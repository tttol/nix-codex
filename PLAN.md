# Plan: nix-codex の作成

## Context

nix-claude-code と同じパターンで、OpenAI の Codex CLI（Rust 製）を Nix でパッケージングする新リポジトリ `nix-codex` を作成する。
バージョン管理を `versions/*.json` で行い、GitHub Actions により毎日自動更新する。

---

## nix-claude-code との主な違い

| 項目 | nix-claude-code | nix-codex |
|---|---|---|
| バイナリ配布 | GCS バケット（裸のバイナリ） | GitHub Releases（`.tar.gz`） |
| バージョン取得 | npm registry | GitHub Releases API (`rust-v*` タグ) |
| 事前チェックサム | あり（manifest.json の SHA256 hex） | **なし**（各アセットをダウンロードしてハッシュ計算） |
| ハッシュ計算 | `nix hash to-sri --type sha256 <hex>` | `nix store prefetch-file --unpack --json <url>` |
| Nix fetcher | `fetchurl` + `dontUnpack = true` | `fetchzip`（tar.gz を自動展開） |
| Linux バイナリ | glibc dynamic（`autoPatchelfHook` 必要） | musl static（patchelf 不要） |
| ライセンス | Unfree（`allowUnfreePredicate` 必要） | Apache-2.0（特別許可不要） |
| 更新頻度 | 毎時 | **毎日** |
| バリアント | claude + claude-minimal | codex のみ |

---

## 作成ディレクトリ

`/Users/tttol/Documents/workspace/nix-codex`（nix-claude-code のサブリポジトリ）

---

## ファイル構成

```
nix-codex/
├── .envrc
├── .gitignore
├── .gitleaks.toml
├── .oxfmtrc.jsonc
├── CLAUDE.md
├── LICENSE
├── README.md
├── flake.lock
├── flake.nix
├── default.nix
├── package.nix
├── update.ts
├── versions/            # 1バージョン = 1 JSON ファイル
├── dev/
│   ├── flake.lock
│   └── flake.nix
└── .github/
    ├── FUNDING.yml
    ├── renovate.json5
    ├── actions/setup-nix/action.yaml
    └── workflows/
        ├── check.yaml
        └── update.yaml
```

---

## プラットフォームマッピング

| Nix system | GitHub アセット名 |
|---|---|
| `x86_64-linux` | `codex-x86_64-unknown-linux-musl.tar.gz` |
| `aarch64-linux` | `codex-aarch64-unknown-linux-musl.tar.gz` |
| `x86_64-darwin` | `codex-x86_64-apple-darwin.tar.gz` |
| `aarch64-darwin` | `codex-aarch64-apple-darwin.tar.gz` |

URL パターン: `https://github.com/openai/codex/releases/download/rust-v{version}/codex-{triple}.tar.gz`

---

## versions/<version>.json スキーマ

```json
{
    "version": "0.122.0",
    "platforms": {
        "x86_64-linux": {
            "url": "https://github.com/openai/codex/releases/download/rust-v0.122.0/codex-x86_64-unknown-linux-musl.tar.gz",
            "hash": "sha256-<NAR hash>"
        },
        "aarch64-linux": { "url": "...", "hash": "sha256-..." },
        "x86_64-darwin":  { "url": "...", "hash": "sha256-..." },
        "aarch64-darwin": { "url": "...", "hash": "sha256-..." }
    }
}
```

ハッシュは `fetchzip` 用の NAR ハッシュ（`--unpack` フラグで取得）。

---

## 各ファイルの実装内容

### update.ts

```typescript
#!/usr/bin/env nix
/*
#! nix shell --inputs-from . nixpkgs#bun nixpkgs#oxfmt -c bun
*/

import { $, Glob, semver } from 'bun';
import { join } from 'node:path';

const GITHUB_RELEASES_API = 'https://api.github.com/repos/openai/codex/releases';
const GITHUB_DOWNLOAD_BASE = 'https://github.com/openai/codex/releases/download';
const TAG_PREFIX = 'rust-v';

const platforms = {
    'x86_64-linux':   'x86_64-unknown-linux-musl',
    'aarch64-linux':  'aarch64-unknown-linux-musl',
    'x86_64-darwin':  'x86_64-apple-darwin',
    'aarch64-darwin': 'aarch64-apple-darwin',
} as const;

type NixPlatform = keyof typeof platforms;

// GitHub Releases API を全ページ取得（100件/ページ）
// GITHUB_TOKEN 環境変数があれば Bearer トークンを付与してレート制限回避
async function fetchAllGitHubReleases(): Promise<...> { ... }

// rust-v* タグから版番号を抽出。4プラットフォーム全アセットが揃っているものだけ返す
function extractVersions(releases): string[] { ... }

// nix store prefetch-file --unpack --json で NAR ハッシュ取得
async function prefetchHash(url: string): Promise<string> {
    const result = await $`nix store prefetch-file --unpack --json ${url}`.json();
    return result.hash;
}

// 既存の versions/*.json を読んで Set を返す
async function getExistingVersions(): Promise<{ versions: Set<string>; latest: string | null }> { ... }

// 1バージョン分の全プラットフォームをダウンロード→ハッシュ→JSON書き込み
async function processVersion(version: string): Promise<boolean> { ... }

// main: 差分のみ処理し、oxfmt でフォーマット後、最新バージョンを stdout 最終行に出力
```

重要点：
- GitHub API はページネーション必須（100件/page）
- `GITHUB_TOKEN` を使って匿名レート制限（60req/時）を回避
- 既存バージョンより古いものはバックフィルしない（nix-claude-code と同様）
- `--unpack` フラグで fetchzip 互換の NAR ハッシュを生成

### package.nix

```nix
{
  lib, stdenv, fetchzip, makeWrapper,
  additionalPaths ? [],
  sourcesFile,
}:
let
  sourcesData = lib.importJSON sourcesFile;
  source = sourcesData.platforms.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "codex";
  inherit (sourcesData) version;

  src = fetchzip { inherit (source) url hash; };

  nativeBuildInputs = [ makeWrapper ];
  # Linux musl static binary なので autoPatchelfHook / buildInputs 不要

  installPhase = ''
    install -Dm755 $src/codex $out/bin/codex
  '';

  postFixup = ''
    wrapProgram $out/bin/codex \
      --argv0 codex \
      --set CODEX_DISABLE_AUTO_UPDATE 1
  '';

  dontStrip = true;

  doInstallCheck = true;
  installCheckPhase = ''
    version=$($out/bin/codex --version 2>&1 | head -1)
    echo "$version" | grep -qF "${sourcesData.version}" \
      || { echo "Version check failed: $version"; exit 1; }
  '';

  meta = with lib; {
    description = "OpenAI Codex CLI — an agentic coding assistant in your terminal";
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    mainProgram = "codex";
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
```

### flake.nix

- 単一 input: `nixpkgs`（flake.lock を最小に保つ）
- `versions/*.json` を eval 時に読み込み、semver 比較で latestVersion を決定
- `packages.<system>.codex` / `default` を公開
- `overlays.default` → `pkgs.codex-cli`
- Unfree 許可不要（Apache-2.0）

### dev/flake.nix

nix-claude-code とほぼ同一。treefmt（nixfmt, deadnix, statix, typos, oxfmt）+ git-hooks + devShell。

### .github/workflows/update.yaml

```yaml
on:
  schedule:
    - cron: '0 6 * * *'   # 毎日 06:00 UTC（daily）
  workflow_dispatch:
```

- `GITHUB_TOKEN` を update.ts に渡す（GitHub API レート制限対策）
- 差分があれば `chore: update codex to <VERSION>` でコミット

### .github/workflows/check.yaml

- gitleaks / fmt-check / build-and-test の 3 ジョブ
- build-and-test: `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest` のマトリクス
- バージョン確認: `codex --version` を直接実行（Rust バイナリはサンドボックス内で問題なし）

---

## 検証手順

```bash
# 1. update.ts を実行して versions/ を初期化
./update.ts

# 2. デフォルトパッケージをビルド
nix build

# 3. バージョン確認
./result/bin/codex --version

# 4. dev チェック（フォーマット・lint）
nix fmt ./dev
nix flake check ./dev

# 5. CI 相当の確認
nix build -L
```

---

## 注意事項

- `nix store prefetch-file --unpack` フラグが使える Nix バージョンかを事前確認すること
- Cachix キャッシュ名のプレースホルダーは実装時に確認して設定
- `CODEX_DISABLE_AUTO_UPDATE` の環境変数名は Codex ソースで要確認（存在しない場合は省略）
