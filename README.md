# Bomb Flower

Bomb Flower is a save editor and save creator for **Longshot**'s Ocarina of Time
Switch 2 remake saves. It is a Flutter desktop application with a pure-Dart save
engine: the engine parses, validates, edits, and exports save bytes through a
testable API, and the Flutter shell is wired to it. v1 opens a real `slot_NN`
folder, edits verified `progress.sav` fields, and writes the result through the
atomic export path.

Bomb Flower is an independent project. It ships no ROMs, game assets, ripped
artwork, or audio, and it is **not affiliated with Nintendo**. You need your own
legally obtained save data.

## Status

v1 is shipped. An area is listed as working only when both its code and its
tests are committed; a gap is listed with the reason it remains a gap.

| Area | State | Evidence |
|---|---|---|
| Save engine and adapter | Wired. `SaveEngine` opens `progress.sav` through a per-file `LayoutDescriptor` | `lib/data/adapter/`, `test/data/adapter/` |
| Save format | 40-byte header, 11,958 records, 32 sentinels, footer, no checksum | `lib/domain/save/progress_layout.dart` |
| GameData schema | 11,925/11,925 on-disk fields resolved; 3,608 named, 8,317 unnamed; 75 enum tables | `assets/schema/gamedata_110.json` |
| Real tabs (7) | Overview (read-only), Player/World, Inventory, Equipment, Resources, Advanced Data (gated hex), Settings (in-memory prefs) | `lib/presentation/shell/tabs/` |
| Gap panels (4) | Progression (297 named fields), Dungeons (42 named), Collectibles (159 named), Flags (3,443 named + 6,769 hash-only); read-only, verified counts | `v1_gap_panel.dart` |
| File actions | Title bar: Open, Save, Save As…, Duplicate, Reset slot…, Undo, Redo, Compare (key `shell-action-compare`); collapse to one overflow menu below 1280 px | `lib/presentation/widgets/chrome/file_action_bar.dart` |
| New save creation | `tool/create_save.dart` writes a schema-default 120,572-byte save | `test/domain/newsave/` |
| Edited save loads in game | One external E2E run: a 2-byte `Life`/`MaxLife` edit produced 4 hearts | one-off run, not CI |
| Created save loads in game | **Unproven** | no in-game test has been run |
| Original/edited comparison | Read-only **Compare** dialog: changed fields and byte spans, original vs current, one slot at a time | `compare_save_dialog.dart` |
| Validation footer | On a single-slot real sample: **no actionable warnings**, **8,328 informational notes** (8,325 field + 3 caption `field.unverified`). `1b387db` removed the former 11 sentinel `field.out_of_range` warnings | status footer; `1b387db` |
| Windows and macOS builds | Not supported | Linux-only verification |

Gate at commit `491fa3d`: `flutter analyze` → 0 issues, exit 0;
`flutter test` → `+880 ~8 -0`; `flutter build linux --debug` → ok, 47,848 B
launcher. A local run at the shipped tip `1b387db` reports `No issues found!`
and `+896 ~2: All tests passed!` (the preceding tip `ffa8359` measured
`+894 ~2`). The suite still declares two `skip:` stubs in
`test/domain/engine/roundtrip_invariants_test.dart`; real-format coverage lives
in `test/data/adapter/` and `test/integration/`.

The top-level `docs/` set:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layers, invariants, and
  where new code belongs.
- [`docs/BUILD.md`](docs/BUILD.md) — prerequisites, build, and smoke test.
- [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) — known gaps and their impact.
- [`docs/NEW-SAVE.md`](docs/NEW-SAVE.md) — the new-save builder and its limits.
- [`docs/WORLD.md`](docs/WORLD.md) — verified world and actor catalogues.
- [`docs/LONGSHOT-BOUNDARY.md`](docs/LONGSHOT-BOUNDARY.md) — the read-only rule.
- [`docs/SAVE-FORMAT.md`](docs/SAVE-FORMAT.md) — the save-format reference,
  container header, record stream, and schema provenance.

## Screenshots

The captures in this section **predate v1** and show the deliberate "No save
file open" state. They document the shell chrome and navigation only; they are
not a record of save editing, and no screenshot here shows a loaded save.

- `/tmp/opencode/bomb_flower_shell_1360.png` — 1360×880 window, expanded
  navigation rail, Overview tab, empty state.
- `/tmp/opencode/bomb_flower_shell_1100.png` — 1100×700 minimum-width layout
  with the rail collapsed to icons.
- `/tmp/opencode/bomb_flower_shell_1100_inventory.png` — collapsed rail on the
  Inventory tab, showing placeholder copy from before the tab was wired.

These are machine-local paths, not committed assets.

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

In the app, use **Open** in the title bar and select a save folder (a `slot_NN`
directory, or a parent of `slot_NN` directories). Edits stay in memory until
**Save** or **Save As…**. **Reset slot…** restores the open-time bytes after an
explicit confirmation. **Undo** and **Redo** walk the session history; they
disable when the corresponding stack is empty. **Compare** opens a read-only
dialog with the open-time original beside the current values, restricted to the
active slot.

To build a save from scratch:

```sh
dart run tool/create_save.dart --out /tmp/new-save
```

That writes `/tmp/new-save/slot_00/progress.sav` (120,572 bytes) and
`caption.sav` with an original 1×1 JPEG. The tool is a CLI; v1 has no
new-save action in the UI. See [`docs/NEW-SAVE.md`](docs/NEW-SAVE.md).

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
- **There is no checksum.** The format exposes no integrity value, so Bomb
  Flower cannot detect tampering that was already present in a save. See
  [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).
- **The game clamps invalid values; it does not reject the file.** A `Life=999`
  control edit loaded and was clamped at runtime, so the editor enforces
  semantic bounds itself rather than relying on the game.
- **Game acceptance is proven for one scalar edit only.** An external E2E run
  changed `Life`/`MaxLife` from 12 to 16 and the game loaded 4 hearts. A created
  save has never been loaded by the game. The harness is not in this
  repository. See [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).
- **Autosave rotates slots.** An in-game save writes a new `slot_NN`, and the
  game loads the newest one, so editing an older slot alone will not change what
  Continue loads.

## Why the format is evidence-based

The save format is not assumed to be the N64 format. The remake stores a
game-data container with a different record stream, string fields instead of
numeric scene ids, and its own schema revision. The layout work records its
evidence next to the offsets:

- `progress.sav` has a 40-byte header, a little-endian magic `0x01020304`, the
  schema revision `2982123` (`0x2d80eb`) at byte 4, and the absolute tail
  pointer at `u32@8`. It then holds 11,958 8-byte records
  `{u32 Murmur3(name), u32 value}`: 11,925 fields, 32 sentinels, and one footer
  `{0xA3DB7114, value}`. There is **no checksum**. Real played saves are
  122,444–122,940 bytes and carry 280–608 trailing bytes after the footer value,
  so the footer is not a total-length field. See
  `lib/domain/save/progress_layout.dart` and `lib/data/codec/progress_codec.dart`.
- The GameData schema is hash-verified from `GameDataList.Product.110`. All
  11,925 on-disk fields resolve; 3,608 have a verified name and 8,317 are
  hash-only and read-only. The schema also carries 75 enum tables (1,257 unique
  members). 11,657 `Bool64bitKey` declarations exist only in the schema and
  never on disk (`assets/schema/gamedata_110.json`,
  `test/domain/schema/gamedata_schema_test.dart`).
- `caption.sav`'s magic `04 03 02 01`, scene name at 684, map path at 748,
  layout marker 1392 at 540, JPEG length at 1392, and JPEG at 1396 are cited in
  `lib/domain/save/caption_layout.dart` against Longshot's `host/control.c`
  (`caption_json`, lines 1869–1901), `scripts/longshot_saves.py` lines 565–618,
  `website/src/lib/save-scrub.ts`, and `docs/dev/reference/saves.md` lines
  92–94. All three scrubbed samples are 4,741 bytes and round-trip.
- **External E2E acceptance run, 2026-11-22, external to this repository.** A
  `kokiri-start` copy with exactly two bytes changed (`Life` 12→16 at
  `0x14254`, `MaxLife` 12→16 at `0x14BFC`, no checksum recomputation) loaded in
  Longshot `v3.0.0-rc.3-93-g82886e89` (`image.bin` sha256 `f77dd8d6…`):
  `state=play`, `map=KokiriForest_Child`, live `life=16`, `max_life=16`, same
  position as baseline, HUD 4 hearts instead of 3. The Longshot tree was
  sha256-identical after the run. The harness is not committed and no game
  binary or asset is shipped. This does not prove a **created** save is
  accepted; that has never been tested in game.
- The three observed samples are `kokiri-start`, `castle-gate`, and
  `market-entrance`; their scene and map strings are tabulated in
  [`docs/WORLD.md`](docs/WORLD.md). Only 3 of 80 known maps have been observed in
  a real save.

The current weaknesses of that evidence are listed in
[`docs/LIMITATIONS.md`](docs/LIMITATIONS.md): no checksum, one scalar
game-acceptance result rather than a repeatable test, partly opaque
`Binary`/`BinaryArray`/`WString16Array` layouts, 8,317 unnamed fields, and
11,657 `Bool64bitKey` declarations that exist only in the schema, not in
`progress.sav`.

## Licence

TBD before the first release. No third-party game assets are distributed.
