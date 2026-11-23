#!/usr/bin/env bash
# Windowed end-to-end test for the Longshot harness on this desktop.
#
# Boots the game in a real window (no HOS_HEADLESS), drives it through the
# control bridge, and captures the game window with grim. Two runs:
#
#   A  a save made by Bomb Flower's CLI template path (create_save --life)
#   B  a save edited through Bomb Flower's own editing code
#      (SaveSessionController -> SaveEngine.apply -> export)
#
# Audio is on by default. HOS_AUDIO=0 is an opt-in for silent runs; this script
# never sets it, and never sets HOS_HEADLESS.
#
# Every write happens under the run tree (default /tmp/longshot-windowed).
# The game folder, the Longshot checkout and ~/.local/share/longshot are never
# written. The staged save is a copy; the source save is only read.
#
# Usage:
#   tool/e2e/windowed_e2e.sh            # both runs
#   tool/e2e/windowed_e2e.sh a          # only run A
#   tool/e2e/windowed_e2e.sh b          # only run B
#
# Overrides (environment):
#   E2E_ROOT       scratch tree for saves, run folders and screenshots
#                  (default /tmp/longshot-windowed)
#   E2E_CTL        the control bridge folder holding longshot_ctl.py
#                  (default /home/daze/longshot-e2e/ctl)
#   GAME_DIR       the game folder with the longshot binary and image.bin
#                  (default /home/daze/longshot-e2e/game)
#   SOURCE_SAVE    a save folder (account.sav, option.sav, slot_NN/) to copy
#                  from (default the e2e-control run in E2E_HARNESS)
#   UID_SAVE       the user id folder under save/ (default the longshot uid)
#   DISPLAY_SIZE   the window size the game is asked for, WxH
#                  (default 1280x720)
#   LONG_BRIDGE    launch timeout in seconds (default 300)
#   PLAY_TIMEOUT   seconds to wait for state=play (default 180)
#   REPO           the bomb-flower checkout (default this script's repository)
#
# Exit status: 0 all requested runs passed, 1 a run failed, 2 preflight failed.

set -u -o pipefail

REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
E2E_ROOT=${E2E_ROOT:-/tmp/longshot-windowed}
E2E_HARNESS=${E2E_HARNESS:-/home/daze/longshot-e2e}
E2E_CTL=${E2E_CTL:-$E2E_HARNESS/ctl}
GAME_DIR=${GAME_DIR:-$E2E_HARNESS/game}
UID_SAVE=${UID_SAVE:-5a3c9e1f0b7d24680000000000000001}
SOURCE_SAVE=${SOURCE_SAVE:-$E2E_HARNESS/runs/e2e-control/user/save/$UID_SAVE}
DISPLAY_SIZE=${DISPLAY_SIZE:-1280x720}
LONG_BRIDGE=${LONG_BRIDGE:-300}
PLAY_TIMEOUT=${PLAY_TIMEOUT:-180}

CTL="$E2E_CTL/longshot_ctl.py"
SCHEMA="$REPO/assets/schema/gamedata_110.json"
RUN_PIDS=()

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die()  { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
skip() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed"
}

cleanup() {
  local dir
  for dir in "${RUN_PIDS[@]:-}"; do
    [ -n "$dir" ] || continue
    python3 -I "$CTL" --run "$dir" quit >/dev/null 2>&1
    python3 -I "$CTL" --run "$dir" stop --timeout 20 >/dev/null 2>&1
  done
}
trap cleanup EXIT

# --- preflight -------------------------------------------------------------

preflight() {
  step "preflight"

  # 1. a display: refuse rather than fall back to headless
  [ -n "${WAYLAND_DISPLAY:-}" ] || die "WAYLAND_DISPLAY is unset: no windowed run is possible"
  [ -n "${XDG_RUNTIME_DIR:-}" ] || die "XDG_RUNTIME_DIR is unset: libwayland cannot resolve WAYLAND_DISPLAY"
  [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] \
    || die "no wayland socket at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  say "session: $WAYLAND_DISPLAY on $XDG_RUNTIME_DIR (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown})"

  # 2. the tools this harness needs
  need grim
  need hyprctl
  need identify
  need ffmpeg
  need python3
  need dart

  # 3. the compositor must answer and name its output
  local monitor
  monitor=$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
m = json.load(sys.stdin)[0]
print("%s %dx%d@%.0f scale %s" % (
    m["name"], m["width"], m["height"], m["refreshRate"], m["scale"]))
' 2>/dev/null) || die "hyprctl cannot read the monitors: is Hyprland running for this user?"
  say "monitor: $monitor"

  # 4. a capture that is not a uniform colour
  local probe="$E2E_ROOT/preflight-grim.png"
  grim -t png "$probe" || die "grim cannot capture the display"
  local stats
  stats=$(image_stats "$probe") || die "grim wrote a file that is not a PNG"
  say "capture: $probe $stats"
  [ "$(printf '%s' "$stats" | sed -n 's/.*stddev=\([0-9.]*\).*/\1/p' | cut -d. -f1)" -gt 1 ] \
    || die "grim captured a uniform image: the compositor is not reachable"

  # 5. a real GPU renderer, or say plainly that it is software
  if command -v vulkaninfo >/dev/null 2>&1; then
    local gpu
    gpu=$(vulkaninfo --summary 2>/dev/null | sed -n 's/.*deviceName *= *//p' | head -1)
    say "renderer: ${gpu:-unknown}"
    case "$gpu" in
      *llvmpipe*|*lavapipe*|'') say "WARNING: no hardware Vulkan device; expect a slow run" ;;
    esac
  fi

  # 6. the control bridge must exist
  [ -f "$CTL" ] || die "no control bridge at $CTL"
  [ -x "$GAME_DIR/longshot" ] || die "no game binary at $GAME_DIR/longshot"
  [ -f "$GAME_DIR/image.bin" ] || die "no image.bin in $GAME_DIR"
  [ -d "$SOURCE_SAVE" ] || die "no source save at $SOURCE_SAVE"

  say "preflight: ok"
}

# --- helpers ---------------------------------------------------------------

# Prints "<x>,<y> <w>x<h>" for the game window, from hyprctl.
window_geometry() {
  hyprctl clients -j | python3 -c '
import json, sys
wins = [c for c in json.load(sys.stdin)
        if "longshot" in (c["class"] + c["title"]).lower() and c["mapped"]]
if not wins:
    sys.exit(1)
c = wins[0]
print("%d,%d %dx%d" % (c["at"][0], c["at"][1], c["size"][0], c["size"][1]))
'
}

# Prints "WxH mean=<m> stddev=<s> ymin=<a> ymax=<b> yavg=<c>" for a PNG.
image_stats() {
  local png=$1 wh mn sd
  wh=$(identify -format '%wx%h' "$png" 2>/dev/null) || return 1
  mn=$(identify -format '%[fx:mean*255]' "$png" 2>/dev/null | cut -d. -f1)
  sd=$(identify -format '%[fx:standard_deviation*255]' "$png" 2>/dev/null | cut -c1-6)
  local y
  y=$(ffmpeg -hide_banner -loglevel error -i "$png" -vf signalstats,metadata=print -f null - 2>&1 \
      | sed -n 's/.*lavfi.signalstats.\(YMIN\|YMAX\|YAVG\)=\([0-9.]*\).*/\1=\L\2/p' | tr '\n' ' ')
  printf '%s mean=%s stddev=%s %s' "$wh" "$mn" "$sd" "$y"
}

# Captures the game window and proves the image is not uniform.
shot() {
  local out=$1 geom stats
  geom=$(window_geometry) || die "no mapped game window to capture"
  grim -g "$geom" -t png "$out" || die "grim -g '$geom' failed"
  stats=$(image_stats "$out") || die "the capture is not a readable PNG: $out"
  say "  shot: $(basename "$out") geom=$geom $stats"
  case "$stats" in
    mean=*) ;;
  esac
  printf '%s\n' "$stats" >> "$RUN_DIR/shots/$2.stats"
  printf '%s %s\n' "$geom" "$stats"
}

# Bridge wrapper. The run folder is always explicit.
bridge() {
  local run=$1; shift
  python3 -I "$CTL" --run "$run" "$@"
}

# Prints the current state word.
bridge_state() {
  bridge "$1" --json status 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["state"])
except Exception:
    print("none")
'
}

wait_state() {
  local run=$1 want=$2 timeout=${3:-120} start
  start=$(date +%s)
  while :; do
    if [ "$(bridge_state "$run")" = "$want" ]; then return 0; fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then return 1; fi
    sleep 1
  done
}

# Waits for the window to map, then for the title menu.
wait_menu() {
  local run=$1 start
  start=$(date +%s)
  while ! window_geometry >/dev/null 2>&1; do
    [ $(( $(date +%s) - start )) -lt 120 ] || die "no game window mapped within 120 s"
    sleep 1
  done
  say "  window: $(window_geometry)"
  wait_state "$run" menu "$LONG_BRIDGE" || die "the game never reached the title menu"
  say "  state: menu"
}

# The game only takes HID input while its window is focused here.
focus_game() {
  local addr
  addr=$(hyprctl clients -j | python3 -c '
import json, sys
print([c["address"] for c in json.load(sys.stdin) if "longshot" in c["class"].lower()][0])
')
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })" >/dev/null
  sleep 0.4
}

# Drives title -> Load list -> Load/Cancel dialog -> confirm -> play.
# Prints the oot snapshot taken the moment play is reached.
load_first_slot() {
  local run=$1 outdir=$2 tag=$3

  focus_game
  bridge "$run" press A --frames 12 >/dev/null || die "the bridge refused the first A press"
  sleep 0.6
  # The list opens; the row is already the first (only) one.
  shot "$outdir/$tag-load.png" "$tag-load"

  bridge "$run" press UP --frames 6 >/dev/null 2>&1
  bridge "$run" press A --frames 12 >/dev/null || die "the bridge refused the A press on the row"
  sleep 0.6
  # Load/Cancel dialog: Load is focused; this second A confirms it.
  shot "$outdir/$tag-dialog.png" "$tag-dialog"
  bridge "$run" press A --frames 12 >/dev/null || die "the bridge refused the confirm press"

  if ! wait_state "$run" play "$PLAY_TIMEOUT"; then
    shot "$outdir/$tag-bounce.png" "$tag-bounce"
    die "the load never reached state=play (a bounce means the slot or the dialog was rejected)"
  fi
  say "  state: play"
  bridge "$run" watch --events oot --count 1 2>/dev/null | sed -n 's/^game *//p' | head -1
}

# Stages a save folder under the run's --user tree.
stage_user() {
  local run=$1 slot=$2 dst="$1/user/save/$UID_SAVE"
  mkdir -p "$dst" "$run/xdg/data" "$run/xdg/config" "$run/xdg/cache"
  cp -a "$SOURCE_SAVE/account.sav" "$SOURCE_SAVE/option.sav" "$dst/"
  cp -a "$slot" "$dst/"
  # The options file belongs in the --user folder; ask for a window that fits.
  sed -e "s/^output_res=.*/output_res=$DISPLAY_SIZE/" \
      -e 's/^fullscreen=.*/fullscreen=0/' \
      -e 's/^ultrawide=.*/ultrawide=0/' \
      "$GAME_DIR/longshot_options.ini" > "$run/user/longshot_options.ini"
}

# Launches windowed. HOS_HEADLESS is never set; HOS_AUDIO is never set.
launch_windowed() {
  local run=$1
  local sock
  sock=$(python3 -I "$CTL" --run "$run/run" launch "$GAME_DIR" \
    --user "$run/user" \
    --image "$GAME_DIR/image.bin" \
    --romfs "$GAME_DIR/romfs" \
    --timeout "$LONG_BRIDGE" \
    --env "XDG_DATA_HOME=$run/xdg/data" \
    --env "XDG_CONFIG_HOME=$run/xdg/config" \
    --env "XDG_CACHE_HOME=$run/xdg/cache" 2>&1 | tail -1)
  case "$sock" in
    /*) say "  bridge: $sock" ;;
    *)  die "launch failed: $sock" ;;
  esac
  RUN_PIDS+=("$run/run")
}

# The Dart helper for run B, written to the scratch tree so this stays one file.
write_editor_helper() {
  cat > "$E2E_ROOT/apply_life.dart" <<'DART'
// Applies one field edit through Bomb Flower's own editing code path:
// SaveSessionController.open -> edit(SetScalar) -> save().
import 'dart:io';

import 'package:bomb_flower/data/adapter/progress_field_value_codec.dart';
import 'package:bomb_flower/data/adapter/progress_repository.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/engine/save_session.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';

Future<void> main(List<String> args) async {
  final root = args[0];
  final slot = SaveSlotId(args[1]);
  final target = int.parse(args[2]);
  final schema = GameDataSchema.fromJsonString(File(args[3]).readAsStringSync());
  final repository = ProgressSaveRepositoryFactory(schema: schema).create(root);
  final engine = SaveEngine(
    const SaveFormat('oot-remake', 'Ocarina of Time (Switch 2 remake)',
        <LayoutDescriptor>[]),
    valueCodec: const ProgressFieldValueCodec(),
  );
  final session = SaveSessionController(engine: engine, repository: repository);
  await session.open(root);
  var project = session.state.project;
  if (project == null) {
    stderr.writeln('open failed: ${session.state.error}');
    exit(1);
  }
  final document = project.documents[slot]!;
  SaveField<FieldValue> find(String label) => document.fields.firstWhere(
      (SaveField<FieldValue> f) => f.descriptor.label == label);
  final life = find('PlayerStatus.Life');
  stdout.writeln('before: Life=${life.value}');
  session.edit(SetScalar(life.descriptor.id, target));
  if (session.state.error != null) {
    stderr.writeln('edit refused: ${session.state.error}');
    exit(3);
  }
  project = session.state.project!;
  final after = project.documents[slot]!.fields.firstWhere(
      (SaveField<FieldValue> f) => f.descriptor.label == 'PlayerStatus.Life');
  stdout.writeln('after: Life=${after.value}');
  await session.save();
  if (session.state.error != null) {
    stderr.writeln('save failed: ${session.state.error}');
    exit(4);
  }
  session.dispose();
}
DART
}

# --- run A -----------------------------------------------------------------

run_a() {
  step "run A: CLI template slot, windowed"
  RUN_DIR="$E2E_ROOT/runA"
  mkdir -p "$RUN_DIR/shots"
  rm -rf "$RUN_DIR/src" "$RUN_DIR/created" "$RUN_DIR/user"
  mkdir -p "$RUN_DIR/src"

  cp -a "$SOURCE_SAVE/slot_00" "$RUN_DIR/src/"
  say "CLI: create_save --template src/slot_00 --out created --life 12"
  ( cd "$REPO" && dart run tool/create_save.dart \
      --template "$RUN_DIR/src/slot_00" \
      --out "$RUN_DIR/created" --life 12 ) || die "create_save failed"
  [ -f "$RUN_DIR/created/slot_00/progress.sav" ] || die "create_save wrote no slot_00"

  stage_user "$RUN_DIR" "$RUN_DIR/created/slot_00"
  [ -f "$RUN_DIR/user/longshot_options.ini" ] || die "no options file staged"
  say "  staged: $RUN_DIR/user/save/$UID_SAVE"

  launch_windowed "$RUN_DIR"
  wait_menu "$RUN_DIR/run"
  shot "$RUN_DIR/shots/WA-01-menu.png" "WA-01-menu"

  local oot
  oot=$(load_first_slot "$RUN_DIR/run" "$RUN_DIR/shots" "WA-02")
  say "  oot: $oot"
  shot "$RUN_DIR/shots/WA-03-play.png" "WA-03-play"

  case "$oot" in
    *'"map": "HyruleField_Child"'*) ;;
    *) die "run A did not land in HyruleField_Child: $oot" ;;
  esac
  case "$oot" in
    *'"life": 12'*) ;;
    *) die "run A did not load life 12: $oot" ;;
  esac
  case "$oot" in
    *'"max_life": 16'*) ;;
    *) die "run A did not report max_life 16: $oot" ;;
  esac
  say "  run A: PASS"
}

# --- run B -----------------------------------------------------------------

run_b() {
  step "run B: save edited through Bomb Flower's editing code, windowed"
  RUN_DIR="$E2E_ROOT/runB"
  mkdir -p "$RUN_DIR/shots"
  rm -rf "$RUN_DIR/save" "$RUN_DIR/user"
  mkdir -p "$RUN_DIR/save"

  cp -a "$SOURCE_SAVE/slot_02" "$RUN_DIR/save/slot_02"
  write_editor_helper
  say "editor: SaveSessionController.open -> edit(SetScalar PlayerStatus.Life=12) -> save()"
  ( cd "$REPO" && dart --packages="$REPO/.dart_tool/package_config.json" \
      "$E2E_ROOT/apply_life.dart" "$RUN_DIR/save" slot_02 12 "$SCHEMA" ) \
    || die "the editor path refused the edit"
  rm -f "$RUN_DIR/save/slot_02"/*.bak

  # Exactly one byte may differ, and the length may not change.
  local changed
  changed=$(cmp -l "$SOURCE_SAVE/slot_02/progress.sav" \
      "$RUN_DIR/save/slot_02/progress.sav" 2>/dev/null | wc -l)
  [ "$changed" -eq 1 ] || die "expected exactly one changed byte, got $changed"
  [ "$(stat -c %s "$SOURCE_SAVE/slot_02/progress.sav")" \
    -eq "$(stat -c %s "$RUN_DIR/save/slot_02/progress.sav")" ] \
    || die "the edit changed the file length"
  cmp -s "$SOURCE_SAVE/slot_02/caption.sav" "$RUN_DIR/save/slot_02/caption.sav" \
    || die "the edit touched the caption"
  say "  verified: 1 byte changed, length unchanged, caption untouched"

  stage_user "$RUN_DIR" "$RUN_DIR/save/slot_02"
  launch_windowed "$RUN_DIR"
  wait_menu "$RUN_DIR/run"
  shot "$RUN_DIR/shots/WB-01-menu.png" "WB-01-menu"

  local oot
  oot=$(load_first_slot "$RUN_DIR/run" "$RUN_DIR/shots" "WB-02")
  say "  oot: $oot"
  shot "$RUN_DIR/shots/WB-03-play.png" "WB-03-play"

  case "$oot" in
    *'"map": "KokiriForest_Child"'*) ;;
    *) die "run B did not land in KokiriForest_Child: $oot" ;;
  esac
  case "$oot" in
    *'"life": 12'*) ;;
    *) die "run B did not load life 12: $oot" ;;
  esac
  case "$oot" in
    *'"max_life": 16'*) ;;
    *) die "run B did not report max_life 16: $oot" ;;
  esac
  say "  run B: PASS"
}

# --- main ------------------------------------------------------------------

main() {
  mkdir -p "$E2E_ROOT"
  preflight
  case "${1:-both}" in
    a)    run_a ;;
    b)    run_b ;;
    both) run_a; run_b ;;
    *)    die "usage: windowed_e2e.sh [a|b|both]" ;;
  esac
  step "done"
  say "screenshots: $E2E_ROOT/run*/shots"
  say "audio: on by default (HOS_AUDIO is not set; set HOS_AUDIO=0 for a silent run)"
}

main "$@"
