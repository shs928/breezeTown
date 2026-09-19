#!/usr/bin/env bash
# BUILD-01：Windows 正式包构建链——烘焙世界进包 → 导出单文件 exe。
# 产物在 build/（不入库）。导出模板需已安装到 Godot 用户目录（见 fetch-godot.sh）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$REPO_ROOT/tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe"
OUT="$REPO_ROOT/build/BreezeTown.exe"

mkdir -p "$REPO_ROOT/build"

echo "[1/2] 烘焙世界 → game/prebuilt/（指纹不变时跳过）"
timeout 600 "$GODOT" --headless --path "$REPO_ROOT/game" --script res://scripts/bake_world.gd

echo "[2/2] 导出 Windows Desktop → build/BreezeTown.exe"
timeout 900 "$GODOT" --headless --path "$REPO_ROOT/game" --export-debug "Windows Desktop" "$OUT"

echo "BUILD OK → $OUT"
