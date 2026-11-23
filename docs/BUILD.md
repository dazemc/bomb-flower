# Build and run

Bomb Flower targets Linux desktop only. Windows and macOS are untested.

## Prerequisites

| Component | Version or package | Notes |
|---|---|---|
| Flutter | 3.50.1 stable | Dart 3.14.0 is bundled; `pubspec.yaml` requires `^3.14.0` |
| Clang | recent system clang | C/C++ toolchain for the Linux runner |
| CMake | 3.13 or newer | Flutter's Linux template requirement |
| Ninja | recent version | Default Flutter Linux generator |
| GTK 3 | development headers, 3.24 tested | `pkg-config --modversion gtk+-3.0` must succeed |
| Display server | X11 or Wayland | Both are supported by the current runner |
| `xvfb-run` | optional | Required only for the headless smoke test |

Debian/Ubuntu:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev xvfb
```

Arch Linux:

```sh
sudo pacman -S clang cmake ninja pkgconf gtk3 xorg-server-xvfb
```

Enable the Linux desktop target once if needed, and confirm the toolchain:

```sh
flutter config --enable-linux-desktop
flutter doctor
```

A missing GTK 3 development package is the most common failure; the build stops
while configuring `linux/`.

## Fetch, format, analyze, test

From the repository root:

```sh
flutter pub get
dart format .
flutter analyze
flutter test
```

`flutter analyze` is expected to report `No issues found!`. `flutter test` runs
the committed suite. The recorded gate, at commit `491fa3d` with the local
sample fixtures present, is `+880 ~8 -0` with analyze at 0 issues and exit 0. A
local run at the shipped tip `1b387db` reports `No issues found!` and
`+896 ~2: All tests passed!` (the preceding tip `ffa8359` measured `+894 ~2`).
Two `skip:` stubs remain in
`test/domain/engine/roundtrip_invariants_test.dart`; the real-format behaviour
they describe is covered by `test/data/adapter/` and `test/integration/`. Codec
and integration tests that need the samples skip automatically when
`.local-fixtures/` is absent, so a run without fixtures has more skips and a
lower pass count; that is not a failure.

On a single-slot real sample the status footer reports no actionable warnings
and `8,328 informational notes` (8,325 `field.unverified` plus 3 caption
records); a six-slot folder totals 49,968. The former eleven sentinel
`field.out_of_range` warnings were removed by `1b387db`. A successful build or
analyzer run says nothing about those save-level results.

## Build

```sh
flutter build linux --debug
flutter build linux --release
```

The binaries land at:

```text
build/linux/x64/debug/bundle/bomb_flower
build/linux/x64/release/bundle/bomb_flower
```

`bundle/` is the complete runnable application: binary, ICU data, and Flutter
assets. Run it from there, not from an intermediate `build/` directory:

```sh
./build/linux/x64/debug/bundle/bomb_flower
```

Measured debug artifacts at the delivered gate: the launcher is 47,848 bytes and
the bundle directory is about 139 MB. A fresh rebuild on another machine can
differ by a few bytes because of toolchain metadata; the bundle size is the
useful figure.

During development, a display-backed run is `flutter run -d linux`.

## Creating a save

The new-save path is `tool/create_save.dart`, not a UI action:

```sh
dart run tool/create_save.dart --out /tmp/new-save
```

It writes `/tmp/new-save/slot_00/progress.sav` (120,572 bytes) and
`caption.sav` (2,029 bytes with the built-in 633-byte JPEG), then decodes both
with the production codecs. It refuses a non-empty destination unless
`--allow-overwrite` is passed. The complete options and the byte-level checks
are in [`NEW-SAVE.md`](NEW-SAVE.md).

A created save has **never been loaded by the game**. The build is verified
against the samples' shape and against the codecs, not against Longshot's
acceptance; see [`LIMITATIONS.md`](LIMITATIONS.md).

## Headless smoke test

There is no integration test that opens a real window manager. This recipe
starts the built bundle under Xvfb and kills it after 15 seconds:

```sh
xvfb-run -a --server-args='-screen 0 1400x900x24' \
  timeout 15 ./build/linux/x64/debug/bundle/bomb_flower
```

Exit status 124 means the timeout fired while the process was still running;
that is the expected successful result. The app prints Impeller and VM-service
startup lines; under Xvfb it may also print GDK cursor/device warnings, which
did not prevent the process from staying alive in the verified run. A non-zero
status other than 124 or an immediate exit is a failure.

This checks that the runner starts, GTK and the bitsdojo plugin load, and the
process stays alive without an immediate crash. It does not prove a first frame,
and it does not exercise dragging, native close/minimise behaviour, or a real
compositor.

## Custom window frame (bitsdojo)

The app uses `bitsdojo_window` for a frameless window and draws its own 44 px
title bar. That requires a patch in `linux/runner/my_application.cc`:

```cpp
#include <bitsdojo_window_linux/bitsdojo_window_plugin.h>
// ...
auto bdw = bitsdojo_window_from(window);
bdw->setCustomFrame(true);
```

Both lines are already committed. If `linux/` is regenerated (for example by
`flutter create .`), reapply them or the window returns to the native frame. The
Dart side sets the title, size, and minimum size in `lib/main.dart` through
`appWindow`; those calls are no-ops in widget tests, which construct
`BombFlowerApp(enableWindowChrome: false)`.

No X11-versus-Wayland workaround is required for the current build. The runner
sets the same custom frame on both; the development machine runs a Wayland
session, and the headless smoke test runs under Xvfb (X11). `bitsdojo_window` is
unmaintained, which is a maintenance risk rather than a build switch; see
[`LIMITATIONS.md`](LIMITATIONS.md).

## Windows and macOS

Untested. There are no `windows/` or `macos/` runners in the repository, no
verified bitsdojo configuration for them, and no CI job that builds them. Adding
a platform means generating a runner, revalidating the custom-frame patch, and
adding a build job before claiming support.

## Appendix: Acceptance test against a local Longshot build

This is an external, one-off check, not part of `flutter test` or CI. It requires
an already-built Longshot binary; this repository does not build the game, ship
its binary, or contain its assets. The verified run used:

```text
/home/daze/GitHub/Longshot/work/sa/build/longshot
v3.0.0-rc.3-93-g82886e89
image.bin sha256 f77dd8d6…
```

**Never point this run at a real save.** Use a copy of one sample save root. The
game may write a new `slot_NN`, and the run is intentionally isolated from your
normal game data. Isolate the process environment before launching:

```sh
export XDG_CONFIG_HOME="$PWD/run/config"
export XDG_DATA_HOME="$PWD/run/data"
export XDG_CACHE_HOME="$PWD/run/cache"
export XDG_STATE_HOME="$PWD/run/state"
export HOS_HEADLESS=1
export HOS_CRASH_WATCH=0
```

Then launch the already-built binary as the external harness does; the exact
save-directory argument belongs to that harness and is not committed here. The
edit, live-state assertions, control case, and repo-hash gate are documented in
the “Compatibility gate” section of
[`ARCHITECTURE.md`](ARCHITECTURE.md).

The verified 2026-11-22 run changed two bytes in a `kokiri-start` copy
(`Life`/`MaxLife` 12→16), loaded with 4 hearts, and wrote a new `slot_01` that
retained 16/16. A `Life=999` control was clamped to 12 at runtime. The Longshot
tree was sha256-identical after the run. This proves one scalar case only; it
does not make arbitrary edits safe, it says nothing about a **created** save,
and it cannot run in CI here without the game binary and assets.

## Troubleshooting

- **GTK errors** — install the GTK 3 development package and `pkg-config`, then
  rerun `flutter doctor`.
- **`Failed to open display`** — run under a desktop session, or use Xvfb.
- **Stale generated plugin files** — `flutter clean && flutter pub get` and
  rebuild. Do not hand-edit `linux/flutter/generated_plugin_registrant.cc`.
- **Native title bar** — confirm both bitsdojo lines are still in
  `linux/runner/my_application.cc`.
