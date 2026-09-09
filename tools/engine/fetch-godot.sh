#!/usr/bin/env bash
# 微风小镇：获取并安装 FND-01 锁定的 Godot 引擎与导出模板。
# 幂等：已存在且校验通过时跳过下载。仅供本仓库复现环境；二进制是下载缓存，不入库。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE_DIR="$REPO_ROOT/tools/engine/Godot-4.7.2-stable"
CACHE_DIR="$REPO_ROOT/work/engine-dl"
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"

VERSION="4.7.2-stable"
ZIP_URL="https://github.com/godotengine/godot/releases/download/${VERSION}/Godot_v${VERSION}_macos.universal.zip"
ZIP_SHA256="c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e"
TPZ_URL="https://github.com/godotengine/godot/releases/download/${VERSION}/Godot_v${VERSION}_export_templates.tpz"
TPZ_SHA256="f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"

mkdir -p "$CACHE_DIR"

need_zip=1
if [ -x "$ENGINE_DIR/Godot.app/Contents/MacOS/Godot" ]; then
  need_zip=0
  echo "[fetch-godot] engine already installed: $ENGINE_DIR"
fi

if [ "$need_zip" = "1" ]; then
  zip_path="$CACHE_DIR/Godot_v${VERSION}_macos.universal.zip"
  if [ ! -f "$zip_path" ]; then
    echo "[fetch-godot] downloading $ZIP_URL"
    curl -sL --retry 3 -o "$zip_path" "$ZIP_URL"
  fi
  actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
  if [ "$actual" != "$ZIP_SHA256" ]; then
    echo "[fetch-godot] FATAL: zip sha256 mismatch: $actual" >&2
    exit 1
  fi
  rm -rf "$ENGINE_DIR"
  mkdir -p "$ENGINE_DIR"
  unzip -q "$zip_path" -d "$ENGINE_DIR"
  xattr -dr com.apple.quarantine "$ENGINE_DIR/Godot.app" 2>/dev/null || true
  echo "[fetch-godot] engine installed: $ENGINE_DIR/Godot.app"
fi

if [ ! -d "$TEMPLATES_DIR" ]; then
  tpz_path="$CACHE_DIR/Godot_v${VERSION}_export_templates.tpz"
  if [ ! -f "$tpz_path" ]; then
    echo "[fetch-godot] downloading $TPZ_URL"
    curl -sL --retry 3 -o "$tpz_path" "$TPZ_URL"
  fi
  actual="$(shasum -a 256 "$tpz_path" | awk '{print $1}')"
  if [ "$TPZ_SHA256" != "__TEMPLATES_SHA256__" ]; then
    if [ "$actual" != "$TPZ_SHA256" ]; then
      echo "[fetch-godot] FATAL: templates sha256 mismatch: $actual" >&2
      exit 1
    fi
  else
    echo "[fetch-godot] WARNING: templates sha256 not locked yet; got $actual"
  fi
  extract_dir="$(mktemp -d)"
  unzip -q "$tpz_path" -d "$extract_dir"
  mkdir -p "$(dirname "$TEMPLATES_DIR")"
  rm -rf "$TEMPLATES_DIR"
  cp -R "$extract_dir/templates" "$TEMPLATES_DIR"
  rm -rf "$extract_dir"
  echo "[fetch-godot] templates installed: $TEMPLATES_DIR"
else
  echo "[fetch-godot] templates already installed: $TEMPLATES_DIR"
fi

"$ENGINE_DIR/Godot.app/Contents/MacOS/Godot" --version
