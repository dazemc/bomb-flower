# Architecture

Bomb Flower is a Linux desktop Flutter application with a pure-Dart save engine.
The engine is the product; the UI is a client of it. Save-format knowledge is
data supplied by research, not constants baked into the engine.

## Layers

```text
┌──────────────────────────────────────────────────────────────────────┐
│ presentation                                                         │
│   theme/        Deep Canopy tokens and ThemeData                     │
│   shell/        AppShell, navigation rail, footer, eleven tabs        │
│   bloc/shell/   ShellCubit: selection, rail, shortcuts, placeholders  │
│   widgets/      chrome, common controls, hex editor                   │
│   imports: domain types only; never dart:io                          │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ reads domain state, calls domain APIs
┌───────────────────────────────▼──────────────────────────────────────┐
│ domain (pure Dart: no Flutter, no dart:io, no bloc)                  │
│   core/         identities, spans, ByteRegion, snapshots, project,   │
│                 layouts, edit commands, history, audit log, parsing   │
│   engine/       SaveEngine, ports, SaveSessionController              │
│   save/         caption and progress layouts, models, record accessors   │
│   schema/       hash-verified GameData schema and Murmur3 hashing     │
│   validation/   field validators and validation results               │
│   formatting/   hearts, labels, scalar display                        │
│   world/        verified map/base-scene/actor catalogues              │
│   catalogue/    actor catalogue                                       │
└───────────────────────────────▲──────────────────────────────────────┘
                                │ implements ports, converts bytes
┌───────────────────────────────┴──────────────────────────────────────┐
│ data                                                                 │
│   codec/        ByteReader, caption and progress codecs               │
│   io/           FileSlotSource, FileSaveRepository, AtomicFileWriter, │
│                 SidecarBackup, path helpers                          │
│   imports: domain; never Flutter, bloc, or presentation               │
└──────────────────────────────────────────────────────────────────────┘
```

The domain does not know where bytes came from. `SlotSource` and `OriginalStore`
in `lib/domain/engine/ports.dart` are implemented by `lib/data/io/`. The engine
never imports `dart:io`; the file adapters never contain UI state.

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

As of this document, both codecs and the GameData schema are committed. Neither
codec is wired into `SaveEngine`: there is no `LayoutDescriptor` adapter from
the record stream yet, and no UI path opens a save. Use `ProgressCodec` directly
only in tests or research until that adapter exists. The format is documented in
[`SAVE-FORMAT.md`](SAVE-FORMAT.md).

The remake format is not assumed to be the N64 format. Scene and map identities
are strings such as `KokiriForest/KokiriForest_Child`, not numeric ids; the N64
scene-id space is a separate glossary and is rejected by the world catalogue's
validator when it appears in a string field.

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
| New byte parse/encode | `lib/data/codec/` | Round-trip test, malformed-input cases, no Flutter imports |
| New file operation | `lib/data/io/` behind `SlotSource` or `OriginalStore` | Test in `test/data/io/`; update the port only if the contract changes |
| New domain operation | `lib/domain/engine/` | Synthetic-layout test; no `dart:io` |
| New screen or tab | `lib/presentation/shell/tabs/` and `lib/presentation/bloc/` | Widget test; no `dart:io` |
| New theme token | `lib/presentation/theme/` | Token test in `test/presentation/theme_test.dart` |
| New reusable widget | `lib/presentation/widgets/` | Widget test in `test/presentation/` |
| New fixture helper | `test/support/` | Must not contain copyrighted game assets |
| Format research prose | `docs/SAVE-FORMAT.md` (separate owner) | Cite the source and the observation |

## Current shell

- `lib/main.dart` — bitsdojo window setup: size, minimum size, title, show.
- `lib/app.dart` — `MaterialApp`, theme, `BlocProvider<ShellCubit>`, `AppShell`.
- `lib/presentation/widgets/chrome/app_title_bar.dart` — draggable custom
  chrome. This replaces the old `lib/presentation/widgets/app_title_bar.dart`
  path; the old path does not exist.
- `lib/presentation/shell/app_shell.dart` — `AppShell`, the 44 px title bar,
  232/64 px navigation rail, capped tab content, and 28 px status footer. This
  replaces the old `BombFlowerShell` name.

`BombFlowerApp(enableWindowChrome: false)` renders the shell in tests without
native window calls. `ShellCubit` owns navigation selection, responsive rail
collapse, and keyboard shortcuts; it reads and writes no save data. Ten of the
eleven tabs render `PlaceholderTab`; Overview renders an honest empty state.
Opening a save is the next integration seam.

## Testing strategy

- Pure domain tests build synthetic layouts and buffers
  (`test/domain/core/fixtures.dart`, `test/support/`). They do not require game
  files.
- `caption.sav` tests cover synthetic structure, malformed input, encode
  diffs, and the three scrubbed samples when those fixtures are available.
- `progress.sav` tests cover the header, all 32 sections, typed accessors,
  in-place edit atomicity, malformed and truncated input, and the three real
  samples when fixtures are available (`test/data/progress_codec_test.dart`).
- The GameData schema tests verify counts, revision, type shapes, enum hashes,
  and that a `Bool64bitKey` is never on disk
  (`test/domain/schema/gamedata_schema_test.dart`).
- File and sidecar tests use temporary directories and fault-injection hooks.
- Two real-format invariants — zero-edit round-trip and exact edit-span
  equivalence through `SaveEngine` — are declared but skipped in
  `test/domain/engine/roundtrip_invariants_test.dart`. The codec-level
  round-trips are covered; the skipped tests need a `LayoutDescriptor` adapter
  for the record stream. Do not report them as passing.
