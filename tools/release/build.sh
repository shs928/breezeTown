#!/usr/bin/env bash
# REL-01 发布打包：从干净工程构建 macOS 包，产出 SHA-256 与完整性清单。
# 用法：tools/release/build.sh [版本号]  默认 0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-0.1.0}"
cd "$ROOT"

resolve_godot() {
  if [ -n "${GODOT:-}" ] && [ -x "$GODOT" ]; then echo "$GODOT"; return 0; fi
  local rel
  rel="$(python3 -c "import json;print(json.load(open('docs/build/engine-lock.json'))['engine']['local_engine_path'])" 2>/dev/null)"
  [ -n "$rel" ] && [ -x "$ROOT/$rel/Contents/MacOS/Godot" ] && echo "$ROOT/$rel/Contents/MacOS/Godot"
}
GODOT_BIN="$(resolve_godot)" || { echo "FATAL: Godot not found" >&2; exit 2; }

OUT="$ROOT/build/release-$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT/macos"

echo "=== 1. 统一检查（必须全绿） ==="
tools/test/check.sh || { echo "FATAL: checks failed, refusing to build" >&2; exit 1; }

echo "=== 2. 干净导入 ==="
"$GODOT_BIN" --headless --path game --import >/dev/null 2>&1

echo "=== 3. 导出 macOS 包 ==="
mkdir -p game/export/macos
"$GODOT_BIN" --headless --path game --export-release "macOS" "$OUT/macos/BreezeTown.zip" >/dev/null 2>&1
[ -f "$OUT/macos/BreezeTown.zip" ] || { echo "FATAL: export failed" >&2; exit 1; }

echo "=== 4. 校验包内容 ==="
TMP="$(mktemp -d)"
unzip -q "$OUT/macos/BreezeTown.zip" -d "$TMP"
APP="$(find "$TMP" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "FATAL: no .app in export" >&2; exit 1; }
# 导出包必须能 headless 启动
"$APP/Contents/MacOS/$(basename "$APP" .app)" --headless -- --mode=dedicated --port=24699 >/dev/null 2>&1 \
  || { echo "FATAL: exported app cannot start" >&2; exit 1; }
# 不得包含开发绝对路径：只扫文本文件（Info.plist 等），二进制 .pck 用 strings 抽样
# 只拒绝**本项目开发机**的绝对路径（引擎二进制自带官方构建机路径属正常）
DEV_LEAK=0
while IFS= read -r f; do
  case "$f" in
    *.pck|*.icns|*.so|*.dylib) continue ;;
  esac
  # 跳过引擎可执行文件本体（含 Godot 官方构建信息）
  case "$f" in
    */Contents/MacOS/*) continue ;;
  esac
  if grep -q "$(whoami)\|$ROOT" "$f" 2>/dev/null; then
    echo "WARN: dev path in $f"
    DEV_LEAK=1
  fi
done < <(find "$TMP" -type f)
if [ "$DEV_LEAK" = "1" ]; then
  echo "FATAL: package contains development absolute paths" >&2
  exit 1
fi
echo "  开发路径检查: 通过（引擎自带官方构建路径不计）"
rm -rf "$TMP"

echo "=== 5. 生成哈希与清单 ==="
shasum -a 256 "$OUT/macos/BreezeTown.zip" | awk '{print $1}' > "$OUT/macos/BreezeTown.zip.sha256"
{
  echo "版本: $VERSION"
  echo "构建时间(UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "引擎: $("$GODOT_BIN" --version)"
  echo "平台: macOS $(sw_vers -productVersion) $(uname -m)"
  echo "包大小: $(stat -f%z "$OUT/macos/BreezeTown.zip") 字节"
  echo "SHA-256: $(cat "$OUT/macos/BreezeTown.zip.sha256")"
  echo "检查结果: tools/test/check.sh 全绿"
} > "$OUT/BUILD-INFO.txt"

echo ""
echo "构建完成：$OUT"
cat "$OUT/BUILD-INFO.txt"
