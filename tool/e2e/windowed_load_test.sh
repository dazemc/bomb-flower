#!/usr/bin/env bash
# windowed_load_test.sh — one deterministic windowed OoT load test.
#
# Loads a template-cloned save in the real window, waits for the menu, presses
# A, asserts the load reached play, and captures window-only screenshots with
# hard size and non-uniformity checks. No improvisation, no loops, no guessing:
# every step either passes or exits with a numbered reason.
#
# Exit codes: 0 pass; 1 usage; 2 preflight or save build; 3 menu/dialog;
#             4 load; 5 assertion.
#
# See tool/e2e/README.md for the contract and the known limits.
set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# HOST-SPECIFIC EXAMPLES: the literal /home/daze/... values below are paths
# from one developer machine, not defaults this tool depends on. Override
# E2E_ROOT, GAME_DIR, CTL or LONGSHOT_REPO for your own checkout; preflight
# names the variable to set instead of failing silently.
E2E_ROOT=${E2E_ROOT:-/home/daze/longshot-e2e}
GAME_DIR=${GAME_DIR:-$E2E_ROOT/game}
CTL=${CTL:-$E2E_ROOT/ctl/longshot_ctl.py}
LONGSHOT_REPO=${LONGSHOT_REPO:-/home/daze/GitHub/Longshot}
SAVE_UID=5a3c9e1f0b7d24680000000000000001

# Non-uniformity thresholds. Pillow path measures luma stddev; the ffmpeg
# fallback measures the YMAX-YMIN spread. Both are stated in the README.
STDDEV_MIN=8.0
SPREAD_MIN=32

TEMPLATE_SLOT=""
OUT=""
LIFE=12
SCENE=""
BRIDGE_TIMEOUT=300

MARKER=.windowed_load_test

usage() {
  cat <<'USAGE'
Usage: windowed_load_test.sh --template-slot <dir> --out <run-dir>
                             [--life N] [--scene S] [--timeout 300]

  --template-slot <dir>  A save slot the game accepts (progress.sav + caption.sav).
  --out <run-dir>        Where the run goes; a fresh directory, or a previous
                         run of this script (it is replaced).
  --life N               PlayerStatus.Life in quarter hearts (default 12).
  --scene S              Caption scene name override (default: template's own).
  --timeout 300          Seconds for the bridge to answer at launch.
USAGE
}

die_usage() { printf 'windowed_load_test: %s\n\n' "$1" >&2; usage >&2; exit 1; }

while [ $# -gt 0 ]; do
  case $1 in
    --template-slot) TEMPLATE_SLOT=${2-}; [ -n "$TEMPLATE_SLOT" ] || die_usage "--template-slot needs a directory"; shift 2 ;;
    --template-slot=*) TEMPLATE_SLOT=${1#*=}; shift ;;
    --out) OUT=${2-}; [ -n "$OUT" ] || die_usage "--out needs a directory"; shift 2 ;;
    --out=*) OUT=${1#*=}; shift ;;
    --life) LIFE=${2-}; [ -n "$LIFE" ] || die_usage "--life needs a number"; shift 2 ;;
    --life=*) LIFE=${1#*=}; shift ;;
    --scene) SCENE=${2-}; [ -n "$SCENE" ] || die_usage "--scene needs a name"; shift 2 ;;
    --scene=*) SCENE=${1#*=}; shift ;;
    --timeout) BRIDGE_TIMEOUT=${2-}; [ -n "$BRIDGE_TIMEOUT" ] || die_usage "--timeout needs seconds"; shift 2 ;;
    --timeout=*) BRIDGE_TIMEOUT=${1#*=}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$TEMPLATE_SLOT" ] || die_usage "--template-slot is required"
[ -n "$OUT" ] || die_usage "--out is required"
case $LIFE in ''|*[!0-9]*) die_usage "--life must be a positive integer" ;; esac

OUT=$(printf '%s' "$OUT" | sed 's:/*$::')
case $OUT in
  /*) ;;
  *) OUT=$PWD/$OUT ;;
esac
if ! TEMPLATE_SLOT=$(cd -- "$TEMPLATE_SLOT" 2>/dev/null && pwd); then
  printf 'PREFLIGHT FAIL: template slot not found\n' >&2
  exit 2
fi
TEMPLATE_PARENT=$(dirname -- "$TEMPLATE_SLOT")

RUN_DIR=$OUT/run
USER_DIR=$OUT/user
SLOT_DIR=$USER_DIR/save/$SAVE_UID/slot_00
SHOTS_DIR=$OUT/shots
LOG_FILE=$OUT/windowed_load_test.log
SAVEGEN=$OUT/savegen

EXIT_CODE=0
REASON=""
RESULT=""
LAUNCHED=0
FINALIZED=0
CLEANED=0
TEARDOWN=""
WINDOW_LEFT=""
PORCELAIN=""
SCENE_SEEN=""
MAX_LIFE="null"
SHOT_NAMES=()
SHOT_PATHS=()
SHOT_LINES=()
EXPECT_W=0
EXPECT_H=0
WX=0
WY=0
WW=0
WH=0
WSCALE=1

say() { printf '%s\n' "$*"; printf '%s\n' "$*" >>"$LOG_FILE"; }

ctl() { python3 -I "$CTL" --run "$RUN_DIR" "$@"; }

# ---------------------------------------------------------------- finalise ---

emit_json() {
  local shots_meta="{}"
  local i
  if [ ${#SHOT_NAMES[@]} -gt 0 ]; then
    local args=()
    for i in "${!SHOT_NAMES[@]}"; do args+=("${SHOT_NAMES[$i]}=${SHOT_LINES[$i]}"); done
    shots_meta=$(python3 -c '
import json, sys
meta = {}
for item in sys.argv[1:]:
    name, _, rest = item.partition("=")
    parts = rest.split()
    if len(parts) >= 5:
        entry = {"width": int(parts[0]), "height": int(parts[1]),
                 "mode": parts[2], "mean": float(parts[3]),
                 "non_uniformity": float(parts[4])}
        if len(parts) >= 7:
            entry["client_width"] = int(parts[5])
            entry["client_height"] = int(parts[6])
        meta[name] = entry
print(json.dumps(meta))' "${args[@]}")
  fi
  python3 - "$RESULT" "$SCENE_SEEN" "$LIFE" "$MAX_LIFE" "$EXIT_CODE" "$REASON" "$shots_meta" "$TEARDOWN" "$WINDOW_LEFT" "$PORCELAIN" ${SHOT_NAMES[@]+"${SHOT_NAMES[@]}"} <<'PY'
import json
import sys

args = sys.argv[1:]
(result, scene, life, max_life, code, reason, meta, teardown, window_left,
 porcelain) = args[:10]
names = args[10:]

shots = {}
for name in names:
    if name:
        shots[name] = name + ".png"

def number(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None

doc = {
    "result": result or "fail",
    "scene": scene or None,
    "life": number(life),
    "max_life": number(max_life),
    "shots": shots,
    "shots_meta": json.loads(meta) if meta else {},
    "exit": number(code) or 0,
}
if reason:
    doc["reason"] = reason
if teardown:
    doc["teardown"] = teardown
if window_left:
    doc["longshot_left_running"] = window_left
if porcelain:
    doc["longshot_dirty"] = porcelain.splitlines()
print(json.dumps(doc, indent=2))
PY
}

cleanup() {
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  local notes=()
  if [ "$LAUNCHED" = 1 ]; then
    timeout 30 python3 -I "$CTL" --run "$RUN_DIR" quit >/dev/null 2>&1
    timeout 40 python3 -I "$CTL" --run "$RUN_DIR" stop --timeout 20 >/dev/null 2>&1
    local i
    for i in $(seq 1 40); do
      pgrep -x longshot >/dev/null 2>&1 || break
      sleep 0.5
    done
    if pgrep -x longshot >/dev/null 2>&1; then
      WINDOW_LEFT=$(pgrep -x longshot | tr '\n' ' ')
      notes+=("longshot still running: $WINDOW_LEFT")
    else
      notes+=("no longshot process")
    fi
  fi
  PORCELAIN=$(git -C "$LONGSHOT_REPO" --no-optional-locks status --porcelain 2>&1)
  if [ -n "$PORCELAIN" ]; then
    notes+=("Longshot tree dirty (not touched by this script)")
  else
    notes+=("Longshot tree clean")
  fi
  TEARDOWN=$(IFS='; '; printf '%s' "${notes[*]}")
}

finalize() {
  [ "$FINALIZED" = 1 ] && return 0
  FINALIZED=1
  cleanup
  emit_json
  if [ "$EXIT_CODE" = 0 ] && [ -z "$REASON" ]; then
    printf 'RESULT: PASS\n'
  else
    printf 'RESULT: FAIL(%s)\n' "${REASON:-exit $EXIT_CODE}"
  fi
}

fail() {
  EXIT_CODE=$1
  shift
  REASON=$*
  RESULT=fail
  printf 'ASSERT FAIL: %s\n' "$REASON" >&2
  finalize
  exit "$EXIT_CODE"
}

finalize_and_exit() {
  RESULT=pass
  finalize
  exit 0
}

on_trap() {
  local rc=$?
  trap - EXIT INT TERM
  if [ "$FINALIZED" = 0 ]; then
    if [ "$EXIT_CODE" = 0 ] && [ "$rc" != 0 ]; then
      EXIT_CODE=$rc
      REASON=${REASON:-unexpected_exit_$rc}
    fi
    RESULT=${RESULT:-fail}
    [ -n "$REASON" ] && RESULT=fail
    finalize
  fi
  exit "${EXIT_CODE:-1}"
}
trap on_trap EXIT INT TERM

# ----------------------------------------------------------------- helpers ---

# Prints "state window_w window_h" from one status call; "-" for unknown.
status_triple() {
  ctl --json status 2>/dev/null | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    print("- - -")
    raise SystemExit
window = doc.get("window")
if isinstance(window, dict) and window.get("width") and window.get("height"):
    print(doc.get("state") or "-", int(window["width"]), int(window["height"]))
else:
    print(doc.get("state") or "-", "-", "-")'
}

# Prints "x y w h scale" for the single mapped Longshot window.
find_window() {
  python3 -c '
import json, subprocess, sys

def hypr(what):
    out = subprocess.run(["hyprctl", what, "-j"], capture_output=True, text=True)
    return json.loads(out.stdout)

clients = hypr("clients")
live = [c for c in clients if c.get("mapped") and not c.get("hidden")]
def cls(c):
    return ((c.get("class") or "") + " " + (c.get("initialClass") or "")).lower()
tiers = [
    [c for c in live if cls(c).split()[0] == "longshot" or (c.get("class") or "").lower() == "longshot"],
    [c for c in live if "longshot" in cls(c)],
    [c for c in live if "longshot" in (c.get("title") or "").lower()],
]
chosen = next((t for t in tiers if t), [])
if not chosen:
    raise SystemExit(1)
chosen.sort(key=lambda c: c["size"][0] * c["size"][1], reverse=True)
c = chosen[0]
x, y = c["at"]; w, h = c["size"]
cx, cy = x + w // 2, y + h // 2
scale = 1.0
for m in hypr("monitors"):
    if m["x"] <= cx < m["x"] + m["width"] and m["y"] <= cy < m["y"] + m["height"]:
        scale = float(m.get("scale") or 1.0)
        break
print(int(x), int(y), int(w), int(h), scale)'
}

# Prints the Hyprland address of the single mapped Longshot window.
window_address() {
  python3 -c '
import json, subprocess

clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"],
                                    capture_output=True, text=True).stdout)
live = [c for c in clients if c.get("mapped") and not c.get("hidden")]
def name(c):
    return ((c.get("class") or "") + " " + (c.get("initialClass") or "") + " "
            + (c.get("title") or "")).lower()
hits = [c for c in live if "longshot" in name(c)]
if len(hits) != 1:
    raise SystemExit(1)
print(hits[0]["address"])'
}

# One capture attempt. Returns 1 with CHECK_REASON set when the check fails,
# 0 and records the shot when it passes.
capture_once() { # name
  local name=$1
  local path=$SHOTS_DIR/$name.png
  local addr
  addr=$(window_address) || { CHECK_REASON="WINDOW_NOT_FOUND:$name"; return 1; }
  # Raise it: grim captures the composited screen region, so an overlapping
  # window would be captured instead. Input does not need this (the bridge
  # bypasses HID); the screenshot does.
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })" >/dev/null 2>&1 || true
  sleep 0.4
  read -r WX WY WW WH WSCALE < <(find_window) || { CHECK_REASON="WINDOW_NOT_FOUND:$name"; return 1; }
  [ "${WW:-0}" -gt 0 ] || { CHECK_REASON="WINDOW_NOT_FOUND:$name"; return 1; }
  EXPECT_W=$(python3 -c "print(round($WW*$WSCALE))")
  EXPECT_H=$(python3 -c "print(round($WH*$WSCALE))")

  grim -g "$WX,$WY ${WW}x${WH}" "$path" >/dev/null 2>&1 || { CHECK_REASON="GRIM_FAILED:$name"; return 1; }
  [ -s "$path" ] || { CHECK_REASON="PNG_MISSING:$name"; return 1; }

  local ax ay aw ah
  read -r ax ay aw ah _ < <(find_window) || true
  if [ "${ax:-}" != "$WX" ] || [ "${ay:-}" != "$WY" ] ||
     [ "${aw:-}" != "$WW" ] || [ "${ah:-}" != "$WH" ]; then
    CHECK_REASON="WINDOW_MOVED:$name:${WX},${WY} ${WW}x${WH} -> ${ax:-?},${ay:-?} ${aw:-?}x${ah:-?}"
    return 1
  fi

  local stats
  stats=$(png_stats "$path") || { CHECK_REASON="PNG_UNREADABLE:$name"; return 1; }
  read -r PNG_W PNG_H PNG_MODE PNG_MEAN PNG_UNIFORM <<<"$stats"
  if [ "$PNG_W" != "$EXPECT_W" ] || [ "$PNG_H" != "$EXPECT_H" ]; then
    CHECK_REASON="PNG_SIZE:$name:${PNG_W}x${PNG_H}!=${EXPECT_W}x${EXPECT_H}"
    return 1
  fi
  local threshold=$STDDEV_MIN
  [ "$PNG_MODE" = spread ] && threshold=$SPREAD_MIN
  if ! awk -v v="$PNG_UNIFORM" -v t="$threshold" 'BEGIN{exit !(v > t)}'; then
    CHECK_REASON="PNG_UNIFORM:$name:${PNG_MODE}=$PNG_UNIFORM<=$threshold"
    return 1
  fi

  SHOT_NAMES+=("$name")
  SHOT_PATHS+=("$path")
  SHOT_LINES+=("$PNG_W $PNG_H $PNG_MODE $PNG_MEAN $PNG_UNIFORM $WW $WH")
  say "shot $name: ${PNG_W}x${PNG_H} ${PNG_MODE}=$PNG_UNIFORM at ${WX},${WY} ${WW}x${WH}x$WSCALE -> $path"
  return 0
}

# shot <name> [settle-seconds]
#
# A load fades in from black, so state=play is reached a little before the
# scene is visible. Settling is a bounded wait for a frame that passes the same
# checks: it never relaxes them, it only gives the game a fixed budget to draw
# one. Zero settle (the default) is a single attempt.
shot() {
  local name=$1
  local settle=${2:-0}
  local deadline
  deadline=$(( $(date +%s) + settle ))
  while :; do
    capture_once "$name" && return 0
    if [ "$(date +%s)" -lt "$deadline" ]; then
      say "settle: $name rejected ($CHECK_REASON), retrying"
      sleep 0.5
      continue
    fi
    fail 5 "$CHECK_REASON"
  done
}

# Sets PNG_W/H/MODE/MEAN/UNIFORM.
png_stats() {
  python3 - "$1" <<'PY'
import re
import subprocess
import sys

path = sys.argv[1]
try:
    from PIL import Image, ImageStat
except ImportError:
    Image = None

if Image is not None:
    im = Image.open(path).convert("L")
    stat = ImageStat.Stat(im)
    print(im.width, im.height, "stddev", "%.3f" % stat.mean[0], "%.3f" % stat.stddev[0])
    raise SystemExit(0)

err = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-i", path,
                      "-vf", "signalstats", "-f", "null", "-"],
                     capture_output=True, text=True).stderr
size = re.search(r",\s*(\d{2,5})x(\d{2,5})[\s,]", err)
if not size:
    raise SystemExit(2)
def field(name):
    m = re.search(name + r":([\d.]+)", err)
    return float(m.group(1)) if m else None
ymin, ymax, yavg = field("YMIN"), field("YMAX"), field("YAVG")
if ymin is None or ymax is None or yavg is None:
    raise SystemExit(2)
print(int(size.group(1)), int(size.group(2)), "spread", "%.3f" % yavg, "%.3f" % (ymax - ymin))
PY
}

log_tail() { # lines
  ctl log --lines "$1" 2>&1 | sed 's/^/    /' >&2 || true
}

# --------------------------------------------------------------- preflight ---

preflight() {
  if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    say "PREFLIGHT FAIL: no WAYLAND_DISPLAY and no DISPLAY (a windowed run needs a session)"
    exit 2
  fi
  local tool
  for tool in grim hyprctl python3 dart; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      say "PREFLIGHT FAIL: $tool not found in PATH"
      exit 2
    fi
  done
  if [ ! -d "$LONGSHOT_REPO" ]; then
    say "PREFLIGHT FAIL: Longshot checkout not found: $LONGSHOT_REPO"
    say "  Set LONGSHOT_REPO=/path/to/Longshot (the built-in value is only a host-specific example)."
    exit 2
  fi
  if [ ! -f "$CTL" ]; then
    say "PREFLIGHT FAIL: control bridge not found: $CTL"
    say "  Set CTL=/path/to/longshot_ctl.py or E2E_ROOT=/path/to/e2e-tree."
    exit 2
  fi
  if [ ! -x "$GAME_DIR/longshot" ]; then
    say "PREFLIGHT FAIL: game binary not found: $GAME_DIR/longshot"
    say "  Set GAME_DIR=/path/to/game or E2E_ROOT=/path/to/e2e-tree."
    exit 2
  fi
  if [ ! -f "$GAME_DIR/image.bin" ] || [ ! -d "$GAME_DIR/romfs" ]; then
    say "PREFLIGHT FAIL: game content not found: $GAME_DIR/image.bin and $GAME_DIR/romfs"
    say "  Set GAME_DIR=/path/to/game or E2E_ROOT=/path/to/e2e-tree."
    exit 2
  fi
  if [ ! -f "$TEMPLATE_SLOT/progress.sav" ]; then
    say "PREFLIGHT FAIL: template slot has no progress.sav: $TEMPLATE_SLOT"
    exit 2
  fi
  if [ ! -f "$TEMPLATE_SLOT/caption.sav" ]; then
    say "PREFLIGHT FAIL: template slot has no caption.sav: $TEMPLATE_SLOT"
    exit 2
  fi
  local running
  running=$(pgrep -x longshot 2>/dev/null | tr '\n' ' ')
  if [ -n "$running" ]; then
    say "PREFLIGHT FAIL: another longshot is already running (pid $running); refusing to capture the wrong window"
    exit 2
  fi
}

mkdir -p -- "$OUT" 2>/dev/null || true
if [ ! -d "$OUT" ]; then
  printf 'PREFLIGHT FAIL: cannot create --out directory: %s\n' "$OUT" >&2
  exit 2
fi
if [ -n "$(ls -A "$OUT" 2>/dev/null)" ] && [ ! -f "$OUT/$MARKER" ]; then
  printf 'PREFLIGHT FAIL: --out exists and is not a previous run of this script: %s\n' "$OUT" >&2
  exit 2
fi
: >"$LOG_FILE"
touch -- "$OUT/$MARKER"

say "windowed_load_test: out=$OUT life=$LIFE template=$TEMPLATE_SLOT"
preflight
say "preflight: ok (no longshot running, tools present)"

# Remove everything from a previous run of this script, then start clean.
rm -rf -- "$RUN_DIR" "$USER_DIR" "$SHOTS_DIR" "$SAVEGEN" "$OUT/max_life_probe.dart"
mkdir -p -- "$SHOTS_DIR" "$SAVEGEN"

# ------------------------------------------------------------ save build -----

say "build: create_save --template $TEMPLATE_SLOT --life $LIFE${SCENE:+ --scene $SCENE}"
build_args=(--template "$TEMPLATE_SLOT" --out "$SAVEGEN" --life "$LIFE")
[ -n "$SCENE" ] && build_args+=(--scene "$SCENE")
build_out=$(cd "$REPO_ROOT" && dart run tool/create_save.dart "${build_args[@]}" 2>&1)
build_rc=$?
printf '%s\n' "$build_out" >>"$LOG_FILE"
if [ "$build_rc" != 0 ]; then
  printf '%s\n' "$build_out" >&2
  say "PREFLIGHT FAIL: create_save exited $build_rc"
  exit 2
fi
printf '%s\n' "$build_out" | sed 's/^/  build: /'

emitted=$(find "$SAVEGEN" -mindepth 1 -maxdepth 1 -type d | sort)
emitted_count=$(printf '%s\n' "$emitted" | grep -c . || true)
if [ "$emitted_count" != 1 ]; then
  say "PREFLIGHT FAIL: create_save emitted $emitted_count directories under $SAVEGEN (expected 1)"
  exit 2
fi
if [ ! -f "$emitted/progress.sav" ] || [ ! -f "$emitted/caption.sav" ]; then
  say "PREFLIGHT FAIL: create_save did not emit progress.sav and caption.sav under $emitted"
  exit 2
fi
say "build: emitted $emitted"

SCENE_SEEN=$(printf '%s\n' "$build_out" | sed -n 's/.*caption decode=ok scene=\([^ ]*\).*/\1/p' | head -1)
CAPTION_MAP=$(printf '%s\n' "$build_out" | sed -n 's/.*caption decode=ok scene=[^ ]* map=\([^ ]*\).*/\1/p' | head -1)
[ -n "$CAPTION_MAP" ] || { say "PREFLIGHT FAIL: create_save did not report the caption's map path"; exit 2; }
EXPECTED_MAP=${CAPTION_MAP##*/}
say "build: scene=$SCENE_SEEN expected_map=$EXPECTED_MAP"

# --------------------------------------------------------------- stage -------

mkdir -p -- "$SLOT_DIR"
cp -- "$emitted/progress.sav" "$emitted/caption.sav" "$SLOT_DIR/"
copied=()
for extra in account.sav option.sav; do
  if [ -f "$TEMPLATE_PARENT/$extra" ]; then
    cp -- "$TEMPLATE_PARENT/$extra" "$USER_DIR/save/$SAVE_UID/$extra"
    copied+=("$extra")
  fi
done
say "stage: slot_00 at $SLOT_DIR (with ${copied[*]:-no account/option pair})"

if [ -f "$GAME_DIR/longshot_options.ini" ]; then
  cp -- "$GAME_DIR/longshot_options.ini" "$USER_DIR/longshot_options.ini"
  say "stage: options copied from the game folder (the game folder itself is untouched)"
fi

# ------------------------------------------------------- max_life probe ------

cat >"$OUT/max_life_probe.dart" <<'DART'
// Prints PlayerStatus.MaxLife of a progress.sav, by the codec's own field hash.
import 'dart:io';

import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/newsave/template_clone.dart';

void main(List<String> args) {
  final decoded = ProgressCodec.decode(File(args.single).readAsBytesSync());
  if (decoded is! ProgressDecodeOk) {
    stderr.writeln('probe: not a decodable progress.sav');
    exit(1);
  }
  final record = decoded.save.recordByHash(maxLifeFieldHash);
  if (record == null) {
    stderr.writeln('probe: no PlayerStatus.MaxLife record');
    exit(1);
  }
  stdout.writeln(record.asInt());
}
DART

probe_out=$(dart run --packages="$REPO_ROOT/.dart_tool/package_config.json" \
  "$OUT/max_life_probe.dart" "$SLOT_DIR/progress.sav" 2>&1)
if [ $? != 0 ]; then
  printf '%s\n' "$probe_out" >&2
  say "PREFLIGHT FAIL: max_life probe failed"
  exit 2
fi
MAX_LIFE=$(printf '%s' "$probe_out" | tr -d '[:space:]')
case $MAX_LIFE in ''|*[!0-9]*) say "PREFLIGHT FAIL: max_life probe printed '$probe_out'"; exit 2 ;; esac
if [ "$LIFE" -gt "$MAX_LIFE" ]; then
  say "PREFLIGHT FAIL: --life $LIFE exceeds the template's MaxLife $MAX_LIFE"
  exit 2
fi
say "probe: template max_life=$MAX_LIFE (staged life=$LIFE)"

SHA_BEFORE=$(sha256sum "$SLOT_DIR/progress.sav" | cut -d' ' -f1)
SIZE_BEFORE=$(stat -c %s "$SLOT_DIR/progress.sav")
say "stage: progress.sav $SIZE_BEFORE bytes sha256=$SHA_BEFORE"

# --------------------------------------------------------------- launch ------

mkdir -p -- "$OUT/xdg/data" "$OUT/xdg/config" "$OUT/xdg/cache"
LAUNCHED=1
say "launch: windowed (no --headless; HOS_HEADLESS and HOS_AUDIO unset)"
if ! launch_out=$(env -u HOS_HEADLESS -u HOS_AUDIO \
      XDG_DATA_HOME="$OUT/xdg/data" \
      XDG_CONFIG_HOME="$OUT/xdg/config" \
      XDG_CACHE_HOME="$OUT/xdg/cache" \
      python3 -I "$CTL" --run "$RUN_DIR" launch "$GAME_DIR" \
        --image "$GAME_DIR/image.bin" --romfs "$GAME_DIR/romfs" \
        --user "$USER_DIR" --timeout "$BRIDGE_TIMEOUT" 2>&1); then
  printf '%s\n' "$launch_out" >&2
  fail 3 "LAUNCH_FAILED"
fi
say "launch: $(printf '%s' "$launch_out" | tail -1)"

if grep -qE '"HOS_HEADLESS"|"HOS_AUDIO"' "$RUN_DIR/manifest.json" 2>/dev/null; then
  fail 5 "WINDOWED_ENV:$RUN_DIR/manifest.json carries HOS_HEADLESS or HOS_AUDIO"
fi

# ----------------------------------------------------------- menu, dialog ----

say "wait: state=menu (<=180 s)"
if ! ctl wait state --state menu --timeout 180 >/dev/null 2>&1; then
  printf '%s\n' "last 20 log lines:" >&2
  log_tail 20
  fail 3 "MENU_TIMEOUT"
fi
read -r STATE_NOW WIN_W WIN_H < <(status_triple)
say "state: $STATE_NOW (game window ${WIN_W}x${WIN_H})"

# Resolve the window. The tile changes on focus, so this is only a sanity
# check: every capture re-reads it immediately before grim.
geom_ok=0
for i in $(seq 1 20); do
  if read -r WX WY WW WH WSCALE < <(find_window) && [ "${WW:-0}" -gt 0 ]; then geom_ok=1; break; fi
  sleep 0.5
done
[ "$geom_ok" = 1 ] || fail 5 "WINDOW_NOT_FOUND"
say "window: at ${WX},${WY} size ${WW}x${WH} scale ${WSCALE}"
say "window: game renders ${WIN_W}x${WIN_H}; the compositor scales it into the tile"
say "expect: each PNG is the window's physical pixels, ${WW}x${WH} x $WSCALE"

shot menu

# The title's Load flow is three screens, each one A press: the Load list, the
# Load/Cancel dialog, then the confirm. Both captures below come from this run
# and are committed evidence, not a guess. The ladder is bounded at three
# presses; a fourth would be guessing, so it fails instead.
press_a() { ctl press A --frames 20 >/dev/null 2>&1 || fail 3 "PRESS_FAILED"; }
wait_loading() { ctl wait state --state loading --timeout "${1:-5}" >/dev/null 2>&1; }
state_now() { read -r S_NOW _ _ < <(status_triple); printf '%s' "$S_NOW"; }

say "input: press A --frames 20 (title -> Load list)"
press_a
if ! wait_loading 5; then
  STATE_NOW=$(state_now)
  say "after press 1: state=$STATE_NOW (expected loading)"
  if [ "$STATE_NOW" = menu ]; then
    shot dialog
    say "input: press A --frames 20 (Load list -> Load/Cancel dialog)"
    press_a
    if ! wait_loading 5; then
      STATE_NOW=$(state_now)
      say "after press 2: state=$STATE_NOW (expected loading)"
      if [ "$STATE_NOW" = menu ]; then
        shot dialog-after
        say "input: press A --frames 20 (Load is focused; confirm)"
        press_a
        if ! wait_loading 10; then
          STATE_NOW=$(state_now)
          if [ "$STATE_NOW" != loading ]; then
            wait_loading 60 || {
              printf '%s\n' "last 10 log lines:" >&2
              log_tail 10
              fail 3 "DIALOG_UNRESOLVED:state=$STATE_NOW"
            }
          fi
        fi
      fi
    fi
  fi
fi
STATE_NOW=$(state_now)
case $STATE_NOW in
  loading|play) ;;
  *) fail 3 "NO_LOADING:state=$STATE_NOW" ;;
esac
say "state: loading"

# ------------------------------------------------------------------ play -----

say "wait: state=play (<=120 s)"
if ! ctl wait state --state play --timeout 120 >/dev/null 2>&1; then
  printf '%s\n' "last 20 log lines:" >&2
  log_tail 20
  fail 4 "LOAD_TIMEOUT"
fi
read -r STATE_NOW _ _ < <(status_triple)
[ "$STATE_NOW" = play ] || fail 4 "NOT_IN_PLAY:state=$STATE_NOW"
say "state: play"

# The load fades in from black: give the scene a bounded 30 s to be drawn.
shot play 30

# The oot snapshot must describe the same moment as the play shot.
SHOT_CLOCK=$(python3 -c 'import time; print("%.6f" % time.monotonic())')
oot_file=$OUT/oot.json
if ! timeout 30 python3 -I "$CTL" --json --run "$RUN_DIR" watch --events oot --count 1 --every 1 \
    >"$oot_file" 2>"$oot_file.err"; then
  cat "$oot_file.err" >&2
  fail 5 "OOT_UNAVAILABLE"
fi
say "oot: $(tr -d '\n' <"$oot_file")"

read -r OOT_MAP OOT_LIFE OOT_MAX _ OOT_OK < <(python3 - "$oot_file" "$SHOT_CLOCK" <<'PY'
import json
import sys

try:
    events = []
    for line in open(sys.argv[1]):
        line = line.strip()
        if line.startswith("{"):
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    doc = next((e for e in reversed(events) if e.get("event") == "oot"), None)
    if doc is None:
        doc = events[-1] if events else {}
except Exception:
    doc = {}
game = doc.get("game") or {}
map_name = game.get("map")
life = game.get("life")
max_life = game.get("max_life")
stamp = game.get("t")
shot = float(sys.argv[2])
if map_name is None or life is None or max_life is None or stamp is None:
    print("- - - - no")
    raise SystemExit
print(map_name, life, max_life, stamp, "yes" if abs(float(stamp) - shot) <= 1.0 else "no")
PY
)
[ "$OOT_OK" = yes ] || fail 5 "OOT_SNAPSHOT:missing_fields_or_not_same_second(shot=$SHOT_CLOCK)"
say "oot: map=$OOT_MAP life=$OOT_LIFE max_life=$OOT_MAX (sampled within 1 s of the play shot)"

case $OOT_MAP in
  *"$EXPECTED_MAP"*) ;;
  *) fail 5 "MAP:$OOT_MAP does not contain $EXPECTED_MAP" ;;
esac
[ "$OOT_LIFE" = "$LIFE" ] || fail 5 "LIFE:got $OOT_LIFE want $LIFE"
[ "$OOT_MAX" = "$MAX_LIFE" ] || fail 5 "MAX_LIFE:got $OOT_MAX want $MAX_LIFE"

# ------------------------------------------------------- save untouched ------

SHA_AFTER=$(sha256sum "$SLOT_DIR/progress.sav" | cut -d' ' -f1)
SIZE_AFTER=$(stat -c %s "$SLOT_DIR/progress.sav")
[ "$SIZE_AFTER" = "$SIZE_BEFORE" ] || fail 5 "SAVE_SIZE:$SIZE_BEFORE -> $SIZE_AFTER"
[ "$SHA_AFTER" = "$SHA_BEFORE" ] || fail 5 "SAVE_SHA256:$SHA_BEFORE -> $SHA_AFTER"
say "save: staged progress.sav unchanged ($SIZE_AFTER bytes)"

finalize_and_exit
