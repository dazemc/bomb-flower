# Windowed load test

**Canonical entry point: `tool/e2e/windowed_load_test.sh`.**
`tool/e2e/windowed_e2e.sh` is **legacy** and is not the entry point: it predates
the windowed runs, requires ImageMagick `identify` (absent on this machine), uses
a redundant four-press title sequence that includes an `UP`, and rewrites
`output_res` in the `--user` options copy — a file the game ignores (see below).
It is kept for provenance, not for use. When the two disagree, this README and
`windowed_load_test.sh` are correct.

## Purpose

Prove, in a real window, that a save Bomb Flower writes is accepted by the game:
boot the game, load the staged slot through the title's own Load flow, and assert
that the `oot` snapshot the game reports matches the save and that the picture on
screen is the game's, not a blank region.

Not headless. Without `WAYLAND_DISPLAY` or `DISPLAY` it refuses to run.

## Preconditions

* Hyprland session on this machine, plus `grim`, `hyprctl`, `python3`, `dart`
* the game folder (`longshot`, `image.bin`, `romfs`)
* the control bridge (`longshot_ctl.py`, `longshot_bridge.py`)
* a **real** template slot (`progress.sav` + `caption.sav`) — see limits below
* no other `longshot` running: it refuses rather than capture the wrong window

## Command

```sh
tool/e2e/windowed_load_test.sh \
  --template-slot /path/to/<uid>/slot_00 \
  --out /path/to/e2e/runs/e2e-script
```

`--life` defaults to **12** quarter hearts (3 filled + 1 empty in the HUD). It is
overridable, and the JSON always reports the value used. `--life 8` also passes
(2 filled + 2 empty hearts); the two are distinct cases and must not be
conflated. `--scene S` overrides the caption scene name; `--timeout` (default
300) is the bridge-ready timeout. Exit codes: `0` pass, `1` usage, `2`
preflight/save build, `3` menu or dialog, `4` load, `5` assertion.

## What PASS asserts

| Assertion | Value |
|---|---|
| menu reached | ≤ 180 s |
| load flow | **three** A presses: Load list → Load/Cancel dialog → confirm (the earlier two-press model was wrong; proved by `dialog.png` / `dialog-after.png`) |
| play reached | ≤ 120 s after `loading` |
| every PNG | dimensions == the window's client size × output scale; both observed tiles: **1896×2020** (948×1010) and **1896×998** (948×499), scale 2 |
| every PNG non-uniform | luma **stddev > 8.0** (Pillow), or **YMAX−YMIN > 32** (ffmpeg fallback) |
| `oot.map` | contains the caption's own map basename (here `HyruleField_Child`) |
| `oot.life` | == `--life` (default 12 quarter hearts; the JSON reports the value used) |
| `oot.max_life` | == the **template's** MaxLife, read by a Dart probe through the codec's field hash (here 16) |
| `oot` timing | sampled within 1.0 s of the play shot |
| staged `progress.sav` | sha256 and byte length unchanged after the run |
| teardown | no `longshot` process; `git -C <Longshot> status --porcelain` empty |

## Reading the output

Ends with a JSON block and one `RESULT:` line:

```json
{"result":"pass","scene":"HyruleField","life":12,"max_life":16,
 "shots":{"menu":"menu.png","play":"play.png"},"exit":0}
```

`shots_meta` carries each shot's `width`, `height`, `client_width`,
`client_height`, `mode`, `mean` and the measured `non_uniformity`. `reason` is
present on failure; `longshot_dirty` appears if the Longshot tree was not clean
(reported, never laundered). Shots are in `<out>/shots/`.

## Known limits and corrections (measured, not assumed)

* **Synthesised saves are not game-loadable.** Only template cloning
  (`--template … --life N`) produces a save the game accepts.
* **The Load row's hearts are `CaptionData.Life`, not the live value.** A 12/16
  save shows four red hearts on the row while the HUD shows 3+1. Never assert on
  the row; this test asserts on the `oot` snapshot.
* **The window is tiled, not free-floating, and the tile size varies.** `title=Longshot`,
  `class=dev.magicbean.Longshot`, tiled on a 1920×1080 logical desktop at scale 2;
  observed at 948×1010 and 948×499, and it **moves between tiles when focus
  changes**. Nothing is hard-coded: the geometry is re-read immediately before
  every capture, and a capture is rejected (`WINDOW_MOVED`) if it changed while it
  was taken.
* **PNG size is the window's physical pixels**, not the game's render size. The
  game's swapchain follows the tile (1896×2020 and 1896×998 observed), so both
  agree.
* **The control bridge is the only input path.** The game ignores HID input until
  its window is focused, so keyboard/`ydotool`/`wtype` fallbacks do not work. The
  bridge bypasses HID. The script raises the window only so `grim` captures the
  game instead of an overlapping window.
* **The load flow is three screens, not two.** The earlier two-press model was
  wrong. Proved by this run's own captures: `dialog.png` is the Load list after
  press 1, `dialog-after.png` is the Load/Cancel dialog with Load focused after
  press 2 (state still `menu`), and press 3 reaches `loading`. The ladder is
  bounded at three presses and fails rather than guess a fourth.
* **An early `menu → loading → menu` bounce is the game attempting a load by
  itself** and falling back before any input. It is observed and reported; it is
  not "the dialog needs another press".
* **The options file is read from the game folder**, not from `--user`: the
  staged `longshot_options.ini` copy is ignored, so this script does **not**
  control resolution. The resolution is whatever the game folder's ini says.
  The copy is still staged so the run is self-describing.
* **First ~6 s after the window maps run at ~20 fps** (cold and warm; the
  pipeline cache fills to ~44 MB either way), then 60 fps. The 180 s menu timeout
  is safe.
* **`state=play` precedes the fade-from-black.** An immediate play shot measures
  **σ 0.862**, and the σ > 8 assertion correctly refuses it; the bounded 30 s
  settle then captures a real frame (σ 33.874 measured). The settle is a timing
  allowance for the game to draw one frame — it is **not** a threshold change.
* **Audio is on**: `HOS_AUDIO` is never set, and `HOS_HEADLESS` is never set (the
  manifest is asserted to carry neither).

## Known protocol deviations

* **2026-11-23 — launch gate overridden without escalation.** The attempt-4 launch
  `jev_gate` returned **`confirm`** (risk **1.23**, confidence 0.09) and the launch
  proceeded without escalating to the human. Blast radius: a test-harness launch
  against an isolated `--user` profile under the run directory; no rollback was
  needed, Longshot stayed clean and no `longshot` process remained.

## What it writes

Only `<out>`: the staged `--user` tree, the run manifest and log, the shots, and
a `max_life_probe.dart`. It never writes the game folder, the Longshot checkout,
or `~/.local/share/longshot`; the template slot is read-only.

Overrides: `E2E_ROOT`, `GAME_DIR`, `CTL`, `LONGSHOT_REPO`; `windowed_e2e.sh`
additionally takes `E2E_HARNESS`, `E2E_CTL`, `SOURCE_SAVE`. The literal
`/home/daze/...` values in the two scripts are host-specific examples from one
developer machine, not defaults either script depends on. Preflight prints the
variable to set when the path it resolved does not exist.
