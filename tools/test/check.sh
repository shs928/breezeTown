#!/usr/bin/env bash
# 微风小镇统一检查入口（QA-01）。
# 不依赖开发者绝对路径：引擎路径由 docs/build/engine-lock.json 或 GODOT 环境变量决定。
#
# 用法：
#   tools/test/check.sh              # 跑全部可用检查
#   tools/test/check.sh contracts    # 只跑契约测试
#   tools/test/check.sh save-spike   # 只跑存档实验
#   tools/test/check.sh net-spike    # 只跑网络实验
#   tools/test/check.sh boot         # 只跑四模式启动
#   tools/test/check.sh probe        # 跑通过/失败探针自检
#
# 退出码：0=全部通过；1=至少一项失败；2=环境缺失（引擎不可用）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

resolve_godot() {
  if [ -n "${GODOT:-}" ] && [ -x "$GODOT" ]; then echo "$GODOT"; return 0; fi
  local lock="$ROOT/docs/build/engine-lock.json"
  local rel key
  # 平台优先键：macOS 用 *_macos，其余（Windows/Linux）用 *_windows 或默认键。
  case "$(uname -s)" in
    Darwin) key="local_engine_path_macos" ;;
    *)      key="local_engine_path_windows" ;;
  esac
  # 优先用 python 解析锁文件；不可用时退回按行 grep（Windows 常无 python3）。
  if command -v python3 >/dev/null 2>&1; then
    rel="$(python3 -c "import json;d=json.load(open('$lock'))['engine'];print(d.get('$key') or d.get('local_engine_path',''))" 2>/dev/null)"
  fi
  if [ -z "${rel:-}" ]; then
    rel="$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$lock" 2>/dev/null | sed 's/.*:[[:space:]]*"//; s/"$//')"
  fi
  if [ -z "${rel:-}" ]; then
    rel="$(grep -o '"local_engine_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$lock" 2>/dev/null | sed 's/.*:[[:space:]]*"//; s/"$//')"
  fi
  if [ -n "${rel:-}" ] && [ -x "$ROOT/$rel" ]; then
    echo "$ROOT/$rel"; return 0
  fi
  # 兜底：仓库内已解压的引擎（macOS 与 Windows 命名不同）。
  local cand
  for cand in \
    "$ROOT/tools/engine/Godot-4.7.2-stable/Godot.app/Contents/MacOS/Godot" \
    "$ROOT/tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe" \
    "$ROOT/tools/engine/Godot-4.7.2-stable/Godot_v4.7.2-stable_win64.exe"; do
    if [ -x "$cand" ]; then echo "$cand"; return 0; fi
  done
  return 1
}

GODOT_BIN="$(resolve_godot)" || {
  echo "FATAL: Godot engine not found. Run tools/engine/fetch-godot.sh or set GODOT=/path/to/Godot" >&2
  exit 2
}

TARGET="${1:-all}"
PASS=0
FAIL=0
declare -a RESULTS

run_check() {
  local name="$1"; shift
  local log="$ROOT/work/check-$name.log"
  mkdir -p "$ROOT/work"
  echo "=== [$name] ==="
  if "$@" >"$log" 2>&1; then
    echo "PASS  $name  (log: work/check-$name.log)"
    RESULTS+=("PASS $name")
    PASS=$((PASS+1))
  else
    echo "FAIL  $name  (log: work/check-$name.log)"
    tail -5 "$log" | sed 's/^/      /'
    RESULTS+=("FAIL $name")
    FAIL=$((FAIL+1))
  fi
}

check_boot() {
  local m
  for m in solo listen_host client dedicated; do
    "$GODOT_BIN" --headless --path game -- --mode="$m" >/dev/null 2>&1 || return 1
  done
  # 非法模式必须非零退出
  "$GODOT_BIN" --headless --path game -- --mode=invalid >/dev/null 2>&1 && return 1
  return 0
}

check_contracts() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/contracts/test_runner.gd 2>&1)"; [ "${out##*CONTRACTS_OK}" != "$out" ]
}

check_save_spike() {
  local out; out="$("$GODOT_BIN" --headless --path work/save-spike --script res://test_runner.gd 2>&1)"; [ "${out##*SAVE_SPIKE_OK}" != "$out" ]
}

check_net_spike() {
  local out; out="$("$GODOT_BIN" --headless --path work/net-spike --script res://spike_orchestrator.gd 2>&1)"; [ "${out##*NET_SPIKE_OK}" != "$out" ]
}

check_probe() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/qa_probe/probe.gd 2>&1)"; [ "${out##*PROBE_OK}" != "$out" ]
}

check_sim() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/simulation/test_runner.gd 2>&1)"; [ "${out##*SIM_OK}" != "$out" ]
}

check_sim02() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/simulation/sim02_test_runner.gd 2>&1)"; [ "${out##*SIM02_OK}" != "$out" ]
}

check_econ() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/economy/test_runner.gd 2>&1)"; [ "${out##*ECON_OK}" != "$out" ]
}

check_farm() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/farming/test_runner.gd 2>&1)"; [ "${out##*FARM_OK}" != "$out" ]
}

check_data() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/data/test_runner.gd 2>&1)"; [ "${out##*DATA_OK}" != "$out" ]
}

check_data02() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/data/data02_test_runner.gd 2>&1)"; [ "${out##*DATA02_OK}" != "$out" ]
}

check_data03() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/data/data03_test_runner.gd 2>&1)"; [ "${out##*DATA03_OK}" != "$out" ]
}

check_data04() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/data/data04_test_runner.gd 2>&1)"; [ "${out##*DATA04_OK}" != "$out" ]
}

check_data05() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/data05_test_runner.gd 2>&1)"; [ "${out##*DATA05_OK}" != "$out" ]
}

check_stats() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/economy/stats_test_runner.gd 2>&1)"; [ "${out##*STATS_OK}" != "$out" ]
}

check_m3() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/unit/economy/m3_test_runner.gd 2>&1)"; [ "${out##*M3_OK}" != "$out" ]
}

check_net00() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/network/test_runner.gd 2>&1)"; [ "${out##*NET00_OK}" != "$out" ]
}

check_int01() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/test_runner.gd 2>&1)"; [ "${out##*INT01_OK}" != "$out" ]
}

check_net02() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/net02_test_runner.gd 2>&1)"; [ "${out##*NET02_OK}" != "$out" ]
}

check_m2e2e() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/m2_e2e_test_runner.gd 2>&1)"; [ "${out##*M2E2E_OK}" != "$out" ]
}

check_net03() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/net03_test_runner.gd 2>&1)"; [ "${out##*NET03_OK}" != "$out" ]
}

check_net04() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/net04_test_runner.gd 2>&1)"; [ "${out##*NET04_OK}" != "$out" ]
}

check_int02() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/int02_test_runner.gd 2>&1)"; [ "${out##*INT02_OK}" != "$out" ]
}

check_net05() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/net05_test_runner.gd 2>&1)"; [ "${out##*NET05_OK}" != "$out" ]
}

check_int03() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/int03_test_runner.gd 2>&1)"; [ "${out##*INT03_OK}" != "$out" ]
}

check_sec01() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/sec01_test_runner.gd 2>&1)"; [ "${out##*SEC01_OK}" != "$out" ]
}

check_m5() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/m5_test_runner.gd 2>&1)"; [ "${out##*M5_OK}" != "$out" ]
}

check_assets() {
  local out; out="$("$GODOT_BIN" --headless --path game --script res://tests/integration/assets_test_runner.gd 2>&1)"; [ "${out##*ASSETS_OK}" != "$out" ]
}

case "$TARGET" in
  boot)       run_check boot check_boot ;;
  contracts)  run_check contracts check_contracts ;;
  save-spike) run_check save-spike check_save_spike ;;
  net-spike)  run_check net-spike check_net_spike ;;
  probe)      run_check probe check_probe ;;
  sim)        run_check sim check_sim ;;
  sim02)      run_check sim02 check_sim02 ;;
  econ)       run_check econ check_econ ;;
  farm)       run_check farm check_farm ;;
  data)       run_check data check_data ;;
  data02)     run_check data02 check_data02 ;;
  data03)     run_check data03 check_data03 ;;
  data04)     run_check data04 check_data04 ;;
  data05)     run_check data05 check_data05 ;;
  stats)      run_check stats check_stats ;;
  m3)         run_check m3 check_m3 ;;
  net00)      run_check net00 check_net00 ;;
  int01)      run_check int01 check_int01 ;;
  net02)      run_check net02 check_net02 ;;
  m2e2e)      run_check m2e2e check_m2e2e ;;
  net03)      run_check net03 check_net03 ;;
  net04)      run_check net04 check_net04 ;;
  int02)      run_check int02 check_int02 ;;
  net05)      run_check net05 check_net05 ;;
  int03)      run_check int03 check_int03 ;;
  sec01)      run_check sec01 check_sec01 ;;
  m5)         run_check m5 check_m5 ;;
  all)
    run_check boot check_boot
    run_check contracts check_contracts
    run_check save-spike check_save_spike
    run_check net-spike check_net_spike
    run_check sim check_sim
    run_check sim02 check_sim02
    run_check econ check_econ
    run_check farm check_farm
    run_check data check_data
    run_check data02 check_data02
    run_check data03 check_data03
    run_check data04 check_data04
    run_check data05 check_data05
    run_check stats check_stats
    run_check m3 check_m3
    run_check net00 check_net00
    run_check int01 check_int01
    run_check net02 check_net02
    run_check m2e2e check_m2e2e
    run_check net03 check_net03
    run_check net04 check_net04
    run_check int02 check_int02
    run_check net05 check_net05
    run_check int03 check_int03
    run_check sec01 check_sec01
    run_check m5 check_m5
    run_check probe check_probe
    ;;
  *)
    echo "unknown target: $TARGET" >&2
    exit 2
    ;;
esac

echo ""
echo "--- summary ---"
printf '%s\n' "${RESULTS[@]}"
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
