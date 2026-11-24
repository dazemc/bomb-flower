# Architecture

Bomb Flower is a Flutter desktop application whose only verified target is
Linux, with a pure-Dart save engine.
The engine is the product; the UI is a client of it, and `lib/main.dart` now
wires that client to the engine. Save-format knowledge is data supplied by
research, not constants baked into the engine.

## Layers

```text
┌──────────────────────────────────────────────────────────────────────┐
│ presentation                                                         │
│   theme/        Deep Canopy tokens and ThemeData                     │
│   shell/        AppShell, navigation rail, footer, eleven tabs        │
│   bloc/shell/   ShellCubit: selection, rail, shortcuts                │
│   bloc/save_session/  SaveSessionCubit: open, edit, undo, export      │
│   tabs_support/ SaveTabScope, FieldEditor, tab field views            │
│   dialogs/      open, save-as, reset, unsaved-changes, compare,        │
│                 slot rotation                                          │
│   widgets/      chrome (title bar, file actions), controls, hex       │
│   imports: domain types and data entry points; never dart:io          │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ reads domain state, calls domain APIs
┌───────────────────────────────▼──────────────────────────────────────┐
│ domain (pure Dart: no Flutter, no dart:io, no bloc)                  │
│   core/         identities, spans, ByteRegion, snapshots, project,   │
│                 layouts, edit commands, history, audit log, parsing   │
│   engine/       SaveEngine, ports, SaveSessionController              │
│   save/         caption and progress layouts, models, record accessors   │
│   newsave/      NewSaveSpec and the schema-default builder            │
│   schema/       hash-verified GameData schema and Murmur3 hashing     │
│   validation/   field validators and validation results               │
│   formatting/   hearts, labels, scalar display                        │
│   fields/       field groups and tab membership                       │
│   world/        verified map/base-scene/actor catalogues              │
│   catalogue/    actor catalogue                                       │
└───────────────────────────────▲──────────────────────────────────────┘
                                │ implements ports, converts bytes
┌───────────────────────────────┴──────────────────────────────────────┐
│ data                                                                 │
│   adapter/      progress field ids, layout builder, resolver,         │
│                 repository factory, display value codec               │
│   codec/        ByteReader, caption and progress codecs               │
│   io/           FileSlotSource, FileSaveRepository, AtomicFileWriter, │
│                 SidecarBackup, path helpers                          │
│   newsave/      NewSaveWriter over the atomic writer                  │
│   system/       host platform, save locations, picker, diagnostics    │
│   imports: domain; never Flutter, bloc, or presentation               │
└──────────────────────────────────────────────────────────────────────┘
```

The domain does not know where bytes came from. `SlotSource` and `OriginalStore`
in `lib/domain/engine/ports.dart` are implemented by `lib/data/io/`. The engine
never imports `dart:io`; the file adapters never contain UI state. The
presentation layer does not read files itself: it calls the `SaveSessionCubit`,
which owns a `SaveSessionController` and reaches the filesystem only through the
injected `SaveRepository`.

## Immutable models

`SaveSlotId` and `FieldId` are extension types over `String`
(`lib/domain/core/identity.dart`). A slot id names a logical file family, not a
path; the layout owns the relative path, so a slot can move between layout
versions without changing its identity.

`SaveProject` is the open-document aggregate
(`lib/domain/core/save_project.dart`). It holds:

- the layout descriptor and detected version;
- open-time originals, current snapshots, and saved fingerprints;
- one decoded `SaveDocument` per slot;
- an `EditHistory` and an append-only `EditLog`;
- `preserveUnknown`, which must stay `true` for any exportable project.

Domain operations return a new `SaveProject` or a new snapshot; they do not
mutate the originals in place. `EditHistory` and `EditLog` are explicit mutable
collaborators because undo/redo and the audit trail are session state.

## ByteRegion: copy-on-write bytes

`ByteRegion` (`lib/domain/core/byte_region.dart`) stores one immutable base
buffer plus a list of `BytePatch` values. Ingest copies a file once. Every edit
appends a patch that shares the base and previous patch list, so memory use
scales with changed bytes rather than file size.

- `materialize()` applies every patch to a fresh buffer. It is the only
  full-copy operation.
- After 64 patches or 16 KiB of patch payload, the next edit materializes once
  and starts a new base. That is byte-preserving compaction, not a copy per
  edit.
- `fingerprint` is a cached FNV-1a 32-bit content hint. It is not an integrity
  proof; dirty checks that depend on it compare bytes before declaring clean.
- `SaveSnapshot` is a slot, a revision, and a region pointer
  (`lib/domain/core/save_snapshot.dart`). Equality is state identity, not byte
  equality, so a 120 KB buffer never participates in an implicit UI `==`.

Unknown bytes are preserved because patches are selective. An unedited
`caption.sav` re-encodes byte-identically; this is tested against synthetic
buffers always and the three scrubbed samples when those fixtures are available
(`test/data/caption_codec_test.dart`).

## Edit commands

Edits are values, not direct mutations. `EditCommand`
(`lib/domain/core/edit_command.dart`) is a sealed hierarchy:

| Command | Effect |
|---|---|
| `SetScalar` | Writes an unsigned value into a whole numeric field span |
| `SetBit` | Sets one bit inside a field span; bit 0 is the low bit of the first byte |
| `SetEnum` | Resolves an enum key to its raw hash and writes that value |
| `SetBytes` | Writes bytes into a subrange contained by the field span |

Every command validates against the descriptor and current bytes before
encoding a patch. Failures throw `FieldWriteException` with a stable code such
as `field.out_of_range`, `field.not_editable`, or
`field.target_outside_span`. There is intentionally no clamping or truncation
path.

`SaveEngine.apply` validates and encodes first, then updates the snapshot,
history, decoded view, and audit log. A no-op edit returns the same project
instance. A rejected edit leaves bytes, revision, history, and log untouched.

## Undo, redo, and transactions

`EditHistory` (`lib/domain/core/edit_history.dart`) is snapshot-based:

- 100 entries per stack; the oldest entry is evicted.
- Edits to the same field and command type within 400 ms coalesce into one
  entry. `SetBytes` also requires the same target span.
- `seal()` stops the next edit from joining the previous group. The UI is
  expected to call it on blur, selection change, or tab change.
- Every new committed edit clears the redo stack.
- A transaction groups several commands into one undo entry. Nested
  transactions and undo/redo during a transaction are rejected.
- Rolling back a transaction returns the pre-group snapshot; the caller
  installs it with `restoreSnapshot`. The history class never owns project
  state.

Undo installs the prior bytes with a fresh, higher revision, so two snapshots
with the same bytes can still differ in revision. The engine's undo/redo tests
assert byte identity, not revision identity.

## Dirty tracking

`DirtyState` (`lib/domain/core/dirty_state.dart`) exposes two independent
badges:

- `hasUnsavedChanges` — current bytes differ from the last successful export.
- `differsFromOriginal` — current bytes differ from the bytes captured at open.

It also reports changed-field and changed-byte counts and the dirty slots.
Undoing back to the saved state clears the first badge; resetting to the sidecar
original clears the second. `SaveProject.changedSpans` coalesces contiguous
byte differences for validation and display.

## Export, backup, and reset

`SaveEngine.planExport` produces an `ExportPlan` without writing anything
(`lib/domain/core/export_plan.dart`). It resolves the destination, refuses
overlapping roots, refuses a destination that contains or is contained by the
source or sidecar, and collects blocking validation issues. Modes are
`saveInPlace`, `saveAs`, and `duplicate`.

`SaveEngine.export` refuses before the first write when validation has a
blocking issue, when a sidecar conflicts, or when a non-in-place destination
already contains a slot and `allowOverwrite` is false. It writes through
`AtomicFileWriter`:

1. Write a temp file in the same directory, flush, and read it back.
2. Keep a `.bak` of the previous target (or an unretained safety copy when
   previous-version retention is off).
3. Rename the temp over the target and fsync the parent directory (best effort;
   `dart:io` exposes no portable directory fsync).
4. Verify the final target. A failure restores the `.bak` or removes a new
   target.

Multi-file exports stage every temp first, then rename all of them. A
`.bombflower-pending.json` manifest lets the next open finish verified renames
or roll an incomplete batch back. After a successful export the engine re-reads
every written slot and compares bytes; this is independent of the writer's own
verification.

The sidecar original lives beside the save root:

```text
<root>.bombflower-original/
  READY              # written last, after every file is durable
  manifest.json      # project, format, layout version, tree fingerprint
  files/             # mirror of the slot relative paths
```

An existing sidecar is never silently overwritten. It is reusable only when
`READY` exists, the manifest parses, the source-tree fingerprint matches, and
every mirrored file still matches byte for byte. Reset reads this sidecar,
refuses a mismatch, rewrites the slot atomically, verifies the read-back, and
then resets the in-memory document.

## Format gateway

The format boundary is explicit:

- `SaveFormat.layoutFor(version)` returns an exact version match. It does not
  round to a nearby layout; unsupported versions become `ParseUnsupported`.
- Parsing returns typed results: `ParseOk`, `ParseUnverified`, `ParseUnsupported`,
  or `ParseCorrupt` (`lib/domain/core/parse_result.dart`). Malformed user data
  does not throw.
- The container magic is `04 03 02 01`, read as little-endian `0x01020304`.
- The GameData schema revision is `2982123` (`0x2d80eb`) at byte offset 4. A
  mismatch is rejected rather than guessed.
- The committed `caption.sav` codec also checks its layout marker `1392` at
  offset 540 and requires the JPEG to reach the end of the file
  (`lib/domain/save/caption_layout.dart`).
- The committed `progress.sav` codec checks the same magic and exactly
  `ProgressLayout.revision` (`2982123`) before decoding the record stream. It
  rejects a different revision with `ProgressDecodeUnsupported`
  (`lib/data/codec/progress_codec.dart`).
- The container is a 40-byte header, then 11,958 8-byte records
  `{u32 key, u32 value}`: 11,925 fields, 32 sentinels, and a footer
  `{0xA3DB7114, value}`. The pointer tail starts at the `u32` at byte 8. There
  is no checksum. The layout constants are `ProgressLayout` in
  `lib/domain/save/progress_layout.dart`.

`SaveEngine` opens `progress.sav`. The wiring is in `lib/data/adapter/`:
`ProgressLayoutResolver` detects a `slot_NN/progress.sav` and `caption.sav`,
`ProgressLayoutBuilder` derives a `SaveSlotLayout` and a
`LayoutDescriptor` from the decoded records and the GameData schema, and the
resolver hands that exact descriptor to `SaveEngine.open`. The repository
factory is `ProgressSaveRepositoryFactory` in
`lib/data/adapter/progress_repository.dart`; `lib/main.dart` constructs it and
passes the resolver into both `SaveSessionCubit` and `FileSaveRepository`.

Because a `progress.sav`'s spans are derived per file, the format registers no
static layouts. A plain `SaveFormat.layoutFor(version)` is therefore not the
open path for this format; detection and descriptor construction happen in the
adapter before the engine sees the bytes. Layouts are descriptions, not
guesses: a record the schema does not name keeps its hash as its label and is
read-only.

The format is documented in [`SAVE-FORMAT.md`](SAVE-FORMAT.md).

The remake format is not assumed to be the N64 format. Scene and map identities
are strings such as `KokiriForest/KokiriForest_Child`, not numeric ids; the N64
scene-id space is a separate glossary and is rejected by the world catalogue's
validator when it appears in a string field.

## UI surface

Eleven tabs, of which seven are real:

| Tab | What it does |
|---|---|
| Overview | Read-only session summary: slot, health, currency, scene, age, outstanding changes |
| Player/World | Edits verified player and world fields; read-only stored scene when the catalogue cannot name it |
| Inventory | Six-by-four inventory grid and per-slot properties |
| Equipment | Equipped gear, tiers, condition; unknown actor text is read-only |
| Resources | Vitals, currency, consumable counts; enforces semantic bounds |
| Advanced Data | Hex inspection plus editing behind an explicit **Unlock editing** toggle |
| Settings | Editor preferences persisted per OS user through `shared_preferences`, and applied app-wide: the text scale is a `MediaQuery` override in `MaterialApp.builder` |

No tab renders a read-only **gap panel** any more: Progression and Dungeons
became editors in `f4e0499`, Collectibles and Flags in `3048558`. The retired
`V1GapPanel` widget (`lib/presentation/shell/tabs/v1_gap_panel.dart`) is no
longer constructed by any tab. Fields a tab does not expose remain reachable as
raw bytes in Advanced Data. Committed tests assert the editable ratios:
`test/presentation/tabs/progression_tab_test.dart` 297/297,
`dungeons_tab_test.dart` 42/42, `collectibles_tab_test.dart` 159/159, and
`flags_tab_test.dart` 3,438 of 3,443 named (0 of 6,769 hash-only).

The title bar owns eight file actions: **Open**, **Save**, **Save As…**,
**Duplicate**, **Reset slot…**, **Undo**, **Redo**, and **Compare**
(`lib/presentation/widgets/chrome/file_action_bar.dart`). Enablement comes from
the session state — Save needs a dirty project, Compare needs a project that
differs from its open-time original, Undo and Redo need a non-empty stack — and
Reset still requires confirmation. Below 1280 logical pixels the eight actions
collapse into one overflow menu so the brand and save identity keep their room;
the compare entry keeps the widget key `shell-action-compare` in both forms.

**Compare** opens `CompareSaveDialog` (`lib/presentation/dialogs/
compare_save_dialog.dart`), a read-only view of one slot's changed fields with
Original and Current columns, provenance badges, FNV-1a fingerprints, and the
coalesced changed byte spans. It computes from the in-memory open-time original
(also mirrored to the sidecar on export); it never writes and it never accepts
or rejects a change.

The status footer reports validation results instead of hiding them. On a
single-slot real sample it shows no actionable warnings and **8,328
informational notes** (8,325 `field.unverified` records plus 3 caption records);
a six-slot folder totals 49,968. `1b387db` removed the former eleven
`field.out_of_range` results by decoding signed `Int` fields before range
validation, so the `0xFFFFFFFF`/`0xFFFFFFFB` sentinel values are no longer
misreported. Neither group blocks an export, and neither is silent.

## Compatibility gate

A codec test proves the bytes round-trip; it does not prove the game accepts
them. The only game-acceptance evidence is an external E2E run (2026-11-22,
external to this repository), performed once against:

- `/home/daze/GitHub/Longshot/work/sa/build/longshot`,
  `v3.0.0-rc.3-93-g82886e89`, `image.bin` sha256 `f77dd8d6…`.
- A relocated run with isolated `XDG_*` directories, `HOS_HEADLESS=1`, and
  `HOS_CRASH_WATCH=0`.
- A `kokiri-start` **copy**, never a real save.

The procedure a maintainer should repeat:

1. Record the Longshot `HEAD`, the hashes of every tracked file, and the
   `work/` entry count before starting. This is the repo-hash gate.
2. Copy one sample save root. Change exactly two bytes: `Life` 12→16 at value
   offset `0x14254` and `MaxLife` 12→16 at `0x14BFC`. Do not recompute anything.
3. Launch the relocated build against the copy with the isolation variables
   above. Assert `state=play`, `map=KokiriForest_Child`, live `life=16`,
   `max_life=16`, the baseline position, and 4 hearts instead of 3.
4. Perform an in-game save. Confirm it writes a new `slot_NN` and that the new
   slot still contains 16/16.
5. Repeat with a control value (`Life=999`, `MaxLife=12`). Confirm the game
   clamps to 12 at runtime while the file keeps 999 until the next save. This
   proves the game does not reject the value and that the editor must enforce
   `Life <= MaxLife`.
6. Re-run the repo-hash gate. The verified run left Longshot at `HEAD 6377ed7c`
   with all 3,313 tracked files sha256-identical and 720 `work/` entries
   identical, and no file newer than the run start. External `.git` object churn
   from other worktrees was noted; `HEAD` did not move.

The gate proves one scalar edit on one build. It does **not** prove strings,
enums, vectors, arrays, corrupt-file rejection, multi-slot/multi-region edits, or
later game versions, and it cannot run in CI here because neither the game
binary nor its assets are committed.

The run left the Longshot tree sha256-identical: every tracked file, the `HEAD`,
and the `work/` entry count matched the pre-run capture, so the read-only rule
held in practice and not only by convention.

**Created saves are not covered.** `tool/create_save.dart` produces a
120,572-byte schema-default save whose shape matches the samples, but no created
save has been loaded by the game. That acceptance remains unproven; a shape
comparison is not a game-acceptance test.

## Enforced layering

`test/architecture/layering_test.dart` scans every `import` and `export`
directive in `lib/` and fails with file and line on a violation:

- `lib/domain/` may not import `package:flutter/`, `package:flutter_bloc/`,
  `package:bloc/`, `package:material_ui/`, `package:bitsdojo_window/`,
  `package:equatable/`, `dart:io`, or `dart:ui`.
- `lib/data/` may not import UI or state-management packages.
- `lib/presentation/` may not import `dart:io`.

This is a source-level test because `dart analyze` cannot express layer
boundaries and no custom lint package is added. Directory existence is checked
too, so deleting a layer fails the test.

## Where does new code go?

| Change | Location | Required evidence |
|---|---|---|
| New verified byte offset or field | `lib/domain/save/` layout descriptor, or `lib/domain/schema/` for schema metadata | A citation in the descriptor, plus a fixture-backed test |
| New record-to-field mapping | `lib/data/adapter/` | Fixture-backed adapter test; unnamed records stay read-only |
| New byte parse/encode | `lib/data/codec/` | Round-trip test, malformed-input cases, no Flutter imports |
| New new-save rule or value source | `lib/domain/newsave/` | Builder test; the default build stays 120,572 bytes |
| New file operation | `lib/data/io/` behind `SlotSource` or `OriginalStore` | Test in `test/data/io/`; update the port only if the contract changes |
| New save-folder entry point | `lib/data/system/` | Typed result, no UI imports |
| New domain operation | `lib/domain/engine/` | Synthetic-layout test; no `dart:io` |
| New screen or tab | `lib/presentation/shell/tabs/` and `lib/presentation/bloc/` | Widget test; no `dart:io` |
| New persisted user preference | JSON in the store at `lib/presentation/settings/`, platform storage behind the pure `PreferencesBackend` port in `lib/domain/preferences/`, implementation in `lib/data/system/` | Round-trip test through a fresh store instance over the same backend |
| New shared tab control | `lib/presentation/tabs_support/` | Widget test; no filesystem access |
| New theme token | `lib/presentation/theme/` | Token test in `test/presentation/theme_test.dart` |
| New reusable widget | `lib/presentation/widgets/` | Widget test in `test/presentation/` |
| New fixture helper | `test/support/` | Must not contain copyrighted game assets |
| Format research prose | `docs/SAVE-FORMAT.md` (separate owner) | Cite the source and the observation |

## Current shell

- `lib/main.dart` — bitsdojo window setup: size, minimum size, title, show. It
  loads the schema, builds the engine and adapter resolver, creates
  `SaveSessionCubit`, and resolves an optional startup folder.
- `lib/app.dart` — `MaterialApp`, theme, the injected `SaveSessionCubit`,
  `AppShell`.
- `lib/presentation/widgets/chrome/app_title_bar.dart` — draggable custom
  chrome and the title-bar file actions. This replaces the old
  `lib/presentation/widgets/app_title_bar.dart` path; the old path does not
  exist.
- `lib/presentation/shell/app_shell.dart` — `AppShell`, the 44 px title bar,
  232/64 px navigation rail, capped tab content, and 28 px status footer. This
  replaces the old `BombFlowerShell` name.
- `lib/presentation/bloc/save_session/` — `SaveSessionCubit` wraps
  `SaveSessionController`. The cubit owns presentation state (busy, status,
  dialog inputs, active slot) and owns no offsets; it calls the engine and the
  injected repository.

`BombFlowerApp(enableWindowChrome: false)` renders the shell in tests without
native window calls. `ShellCubit` owns navigation selection, responsive rail
collapse, and keyboard shortcuts; it reads and writes no save data.
`SaveSessionCubit.disabled()` remains for widget tests that render the shell
without a save backend: every action returns a typed error instead of throwing.

## Testing strategy

- Pure domain tests build synthetic layouts and buffers
  (`test/domain/core/fixtures.dart`, `test/support/`). They do not require game
  files.
- `caption.sav` tests cover synthetic structure, malformed input, encode
  diffs, and the three scrubbed samples (`test/data/caption_codec_test.dart`).
- `progress.sav` tests cover the header, all 32 sections, typed accessors,
  in-place edit atomicity, malformed and truncated input, and the three real
  samples (`test/data/progress_codec_test.dart`).
- Adapter tests build the real descriptor from decoded samples:
  `test/data/adapter/progress_layout_builder_test.dart` and its resolver,
  field-id, and display-codec siblings.
- Integration tests drive the production wiring over a real fixture:
  `test/integration/fixture_chain_test.dart` opens the sample, edits `Life`,
  undoes, redoes, saves as, and reopens; the exported difference is exactly the
  declared `Life` span.
- The UI chain test
  (`test/presentation/tabs/ui_save_flow_test.dart`) drives the real shell:
  open → edit `Life` → observe the dirty state → undo → re-apply the edit →
  **Save As…** through the title-bar action → reopen the export with a fresh
  session. The export differs from the open-time copy at exactly one byte,
  `0x14254` (`0c` → `10`), inside the declared `Life` span. The undo step is
  asserted separately: it returns to 12 and clears the modified badge.
- Dialog and chrome tests cover file-action enablement and the comparison view
  (`test/presentation/chrome/compare_action_test.dart`,
  `test/presentation/dialogs/compare_save_dialog_test.dart`).
- The GameData schema tests verify counts, revision, type shapes, enum hashes,
  and that a `Bool64bitKey` is never on disk
  (`test/domain/schema/gamedata_schema_test.dart`).
- File and sidecar tests use temporary directories and fault-injection hooks.
- Two declared invariants — `(a)` zero-edit round-trip and `(b)` exact
  edit-span equivalence — are still stubs with a `skip:` in
  `test/domain/engine/roundtrip_invariants_test.dart`; do not report them as
  passing. The recorded gate at commit `491fa3d` reports `+880 ~8 -0`; a local
  run at the shipped tip `1b387db` reports `+896 ~2` with analyze clean. The
  real-format behaviour the stubs describe is exercised by the adapter and
  integration tests above, not by that file.
