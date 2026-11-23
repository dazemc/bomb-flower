# Bomb Flower

Bomb Flower is an in-development save editor and save creator for **Longshot**'s
Ocarina of Time Switch 2 remake saves. It is a Flutter desktop application with
a pure-Dart save engine: the engine parses, validates, edits, and exports save
bytes through a testable API, and the Flutter shell provides the UI surface. The
shell is **not yet wired to the engine**; see Status.

Bomb Flower is an independent project. It ships no ROMs, game assets, ripped
artwork, or audio, and it is **not affiliated with Nintendo**. You need your own
legally obtained save data.

## Status

The project is in early development. The save engine, the `caption.sav` and
`progress.sav` codecs, and the GameData schema exist and are tested; the
application shell is real, but it is **not yet wired to the engine**. No tab can
open a save today.

An area is listed as working only when both its code and its tests are committed.
Anything else is marked not implemented, even when research or a working tree
contains partial work. The one exception is the external Longshot acceptance
row, which records a one-off E2E result and is explicitly not committed code or
a CI test.

| Area | Implemented | Tested | Not yet |
|---|---|---|---|
| App shell, theme, 11-tab navigation | Yes: `lib/presentation/shell/`, `lib/presentation/theme/` | Yes: `test/presentation/shell_test.dart`, `test/presentation/theme_test.dart`, `test/widget_test.dart` | Opening, saving, or editing a save from the UI |
| Save engine core (parse, apply, undo/redo, validate, plan, export) | Yes: `lib/domain/engine/`, `lib/domain/core/` | Yes, against synthetic layouts: `test/domain/engine/`, `test/domain/core/` | An adapter from `progress.sav` records to `LayoutDescriptor`; the real-format engine invariants are skipped |
| Atomic file writes and sidecar originals | Yes: `lib/data/io/` | Yes: `test/data/io/` | Windows and macOS filesystem behaviour |
| `caption.sav` decode/encode | Yes: `lib/data/codec/caption_codec.dart`, `lib/domain/save/caption_layout.dart` | Yes: synthetic cases always; the three scrubbed Longshot samples when fixtures are available (`test/data/caption_codec_test.dart`) | Exposing caption fields in a tab |
| `progress.sav` decode/encode | Yes: `lib/data/codec/progress_codec.dart`, `lib/domain/save/progress_layout.dart`, `progress_save.dart`, `progress_record.dart` | Yes: synthetic cases and the three real samples when fixtures are available (`test/data/progress_codec_test.dart`) | Opening it through `SaveEngine` or any UI; a verified editable descriptor for every record |
| Edited save loads in Longshot | Verified by external E2E run (2-byte Life edit → 4 hearts in game) | One-off acceptance run, 2026-11-22, external to this repo; harness and game not committed | Repeatable CI test; arbitrary field types; corrupt-file rejection; multi-slot edits; later game versions |
| GameData schema and 2982123 revision gate | Yes: `lib/domain/schema/`, `assets/schema/gamedata_110.json` | Yes: `test/domain/schema/gamedata_schema_test.dart` | Loading the schema into the engine or UI; mapping names to editable choices |
| Hex editor widget | Yes: `lib/presentation/widgets/hex/` | Yes: `test/presentation/hex_editor_test.dart` | Wiring it to the Advanced Data tab or a project |
| World and actor catalogues | Yes: `lib/domain/world/`, `lib/domain/catalogue/`, `assets/world/`, `assets/catalogue/` | Yes: `test/domain/world/`, `test/domain/catalogue/` | A map-browsing UI; the assets are not yet declared in `pubspec.yaml` |
| Save creation from scratch | No | No | All of it |
| Windows and macOS builds | No | No | Runners and verification |

The E2E acceptance harness is not committed to this repository, and no game
binary, ROM, image, or save asset is shipped. The Longshot row is a one-off
external result, not a repeatable CI test.

The top-level `docs/` set:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layers, invariants, and
  where new code belongs.
- [`docs/BUILD.md`](docs/BUILD.md) — prerequisites, build, and smoke test.
- [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) — known gaps and their impact.
- [`docs/WORLD.md`](docs/WORLD.md) — verified world and actor catalogues.
- [`docs/LONGSHOT-BOUNDARY.md`](docs/LONGSHOT-BOUNDARY.md) — the read-only rule.
- [`docs/SAVE-FORMAT.md`](docs/SAVE-FORMAT.md) — the save-format reference,
  container header, record stream, and schema provenance.

## Screenshots

These are local development captures from a Flutter Linux run. They are **not
committed** to the repository; the paths below are machine-local and may not
exist elsewhere.

- `/tmp/opencode/bomb_flower_shell_1360.png` — 1360×880 window, expanded
  navigation rail, Overview tab. Shows the custom title bar and the deliberate
  "No save file open" state.
- `/tmp/opencode/bomb_flower_shell_1100.png` — 1100×700 minimum-width layout
  with the rail collapsed to icons.
- `/tmp/opencode/bomb_flower_shell_1100_inventory.png` — collapsed rail on the
  Inventory tab, showing the "ENGINE PENDING" placeholder copy.

The screenshots document the shell, not save editing. No screenshot shows a
loaded save, because that path is not implemented.

## Quick start

Requirements: Flutter 3.50.1 with Dart 3.14, and a Linux desktop toolchain
(`clang`, CMake, Ninja, GTK 3 development headers). Full prerequisites and
troubleshooting are in [`docs/BUILD.md`](docs/BUILD.md).

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter build linux --debug
./build/linux/x64/debug/bundle/bomb_flower
```

For a headless check:

```sh
xvfb-run -a --server-args='-screen 0 1400x900x24' \
  timeout 15 ./build/linux/x64/debug/bundle/bomb_flower
```

`flutter run -d linux` also works on a machine with a display server.

## Safety

Bomb Flower is a save editor. Treat every save as the only copy you have.

- **Longshot is never modified.** It is a read-only reference and is not a build
  or runtime dependency. See [`docs/LONGSHOT-BOUNDARY.md`](docs/LONGSHOT-BOUNDARY.md).
- **Work on copies.** Open and export copies of your save folder. Do not point
  the editor at the only copy the game can see until you have verified the
  result.
- **Exports keep a previous version.** The atomic writer keeps a `.bak` of a
  replaced slot and the sidecar `.bombflower-original/` stores the open-time
  bytes. Neither is a substitute for your own backup.
- **There is no confirmed checksum.** The format does not expose an integrity
  value the editor can verify, so Bomb Flower cannot detect tampering that was
  already present in a save. See [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).
- **Game acceptance is proven for one scalar edit only.** An external E2E run
  changed `Life`/`MaxLife` from 12 to 16 in a `kokiri-start` copy and the game
  loaded it with 4 hearts. Arbitrary field types, corrupt files, multi-slot
  edits, and later game versions are untested, and the harness is not in this
  repository. See [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).

## Why the format is evidence-based

The save format is not assumed to be the N64 format. The remake stores a
game-data container with a different record stream, string fields instead of
numeric scene ids, and its own schema revision. The layout work records its
evidence next to the offsets:

- `caption.sav`'s magic `04 03 02 01`, scene name at 684, map path at 748,
  layout marker 1392 at 540, JPEG length at 1392, and JPEG at 1396 are cited in
  `lib/domain/save/caption_layout.dart` against Longshot's `host/control.c`
  (`caption_json`, lines 1869–1901), `scripts/longshot_saves.py` lines 565–618,
  `website/src/lib/save-scrub.ts`, and `docs/dev/reference/saves.md` lines
  92–94. All three scrubbed samples are 4,741 bytes and round-trip.
- The container magic is `04 03 02 01`. The GameData schema revision is
  `2982123` (`0x2d80eb`) at byte offset 4. The schema's revision gate rejects a
  different revision rather than rounding to a nearby schema.
- `progress.sav` is 120,572 bytes: magic `04 03 02 01`, schema revision
  `2982123` (`0x2d80eb`) at byte 4, a data offset at byte 8, then 8-byte
  records and a pointer-referenced tail. The committed codec decodes all 32
  sentinel-delimited sections, preserves unknown spans, and re-encodes the
  three samples byte-identically. See `lib/domain/save/progress_layout.dart`
  and `lib/data/codec/progress_codec.dart`.
- The GameData schema is hash-verified from `GameDataList.Product.110`: 11,925
  on-disk fields, 11,657 `Bool64bitKey` declarations that are not on disk, and
  3,608 fields with a verified name (`assets/schema/gamedata_110.json`,
  `test/domain/schema/gamedata_schema_test.dart`). The schema revision gate is
  exact: a different revision is rejected, not guessed.
- **External E2E acceptance run, 2026-11-22, external to this repository.** A
  `kokiri-start` copy with exactly two bytes changed (`Life` 12→16 at
  `0x14254`, `MaxLife` 12→16 at `0x14BFC`, no checksum recomputation) loaded in
  Longshot `v3.0.0-rc.3-93-g82886e89` (`image.bin` sha256 `f77dd8d6…`):
  `state=play`, `map=KokiriForest_Child`, live `life=16`, `max_life=16`, same
  position as baseline, HUD 4 hearts instead of 3. An in-game save wrote a new
  `slot_01` that still held 16/16. A control edit (`Life=999`, `MaxLife=12`)
  loaded and was clamped to 12 at runtime; the file kept 999 until the next
  save. The harness is not committed and no game binary or asset is shipped.
- The three observed samples are `kokiri-start`, `castle-gate`, and
  `market-entrance`; their scene and map strings are tabulated in
  [`docs/WORLD.md`](docs/WORLD.md). Only 3 of 80 known maps have been observed in
  a real save.

The current weaknesses of that evidence are listed in
[`docs/LIMITATIONS.md`](docs/LIMITATIONS.md): no checksum, one scalar
game-acceptance result rather than a repeatable test, unverified
`Binary`/`WString16Array` layouts, and 11,657 `Bool64bitKey` declarations that
exist only in the schema, not in `progress.sav`.

## Licence

TBD before the first release. No third-party game assets are distributed.
