# Limitations

This document lists what Bomb Flower cannot yet prove or do. An unlisted
limitation is a documentation bug, not a feature.

Status is as of 2026-11-22, shipped tip `1b387db`. The recorded gate is commit
`491fa3d`: `flutter analyze` reports 0 issues (exit 0) and `flutter test`
reports `+880 ~8 -0`. A local run at `1b387db` reports `No issues found!` and
`+896 ~2: All tests passed!` (the preceding tip `ffa8359` measured `+894 ~2`).
Nothing is skipped in the default run: a full run at
`4562298` reports `No issues found!` and `+1131 ~0 -0`, and
`test/domain/engine/roundtrip_invariants_test.dart` asserts byte-identical
reserialisation of two real played slots on every run instead of skipping. What
remains is acceptance, not coverage: one scalar edit has ever loaded and no
created save has (section 2). Check `git log` and the current test output before
relying on any statement.

## 1. The format has no confirmed checksum

**Impact.** A 2-byte edit loaded with no checksum recomputation, so no integrity
field guards the edited path. The editor cannot detect tampering that existed
before the file was opened, and it cannot prove acceptance beyond the one
external E2E scalar case. A structurally valid file can still be semantically
wrong. The sidecar fingerprint is a change detector, not an authenticity or
integrity proof.

**Mitigation.** Treat validation as a bounds-and-structure check, not a
guarantee. Keep your own backup outside the app and compare exports with the
sidecar original. Do not describe an export as "verified" beyond the checks the
code performs: field spans, declared ranges, exact read-back, and the optional
`IntegrityRecomputer` (not configured for this format).

**Measured context.** A `progress.sav` is a 40-byte header, 11,958 8-byte
records (11,925 fields, 32 sentinels, one footer), and a pointer-referenced
tail. Real played saves carry 280–608 trailing bytes after the footer value, so
even file length is not a reliable integrity signal.

**Validation output is not silent.** On a single-slot real sample the status
footer reports no actionable warnings and **8,328 informational notes**: 8,325
`field.unverified` records plus 3 from the caption file. A six-slot folder
totals 49,968 notes. The former eleven `field.out_of_range` results on
`0xFFFFFFFF`/`0xFFFFFFFB` sentinel values were a signed-`Int` decoding bug and
are gone since `1b387db`. Those results describe what the schema and bounds
checks found; they are not an integrity verdict, and a tidy-looking file can
still be semantically wrong.

## 2. Edited-save acceptance is one scalar case; created-save acceptance is unproven

**Proven.** An external E2E acceptance run on 2026-11-22 (external to this
repository) loaded a `kokiri-start` copy with exactly two bytes changed:
`Life` 12→16 at value offset `0x14254` and `MaxLife` 12→16 at `0x14BFC`. No
checksum was recomputed. The tested build was
`/home/daze/GitHub/Longshot/work/sa/build/longshot`,
`v3.0.0-rc.3-93-g82886e89`, `image.bin` sha256 `f77dd8d6…`, run with isolated
`XDG_*` directories, `HOS_HEADLESS=1`, and `HOS_CRASH_WATCH=0`. The game reported
`state=play`, `map=KokiriForest_Child`, live `life=16`, `max_life=16`, the same
position as the baseline, and drew 4 hearts instead of 3. An in-game save wrote
a new `slot_01` that still contained `Life=16`/`MaxLife=16`; the game neither
rejected nor silently repaired the edit. The Longshot tree was sha256-identical
after the run.

**Not proven.** Arbitrary field types (strings, enums, vectors, arrays),
corrupt-file rejection, multi-slot or multi-region edits, and later game
versions. The E2E harness is not committed, no game binary or asset is shipped,
and this is not a repeatable CI test.

**Created saves.** `tool/create_save.dart` builds a schema-default save whose
shape matches the samples (120,572 bytes, footer value 120,564, same keys,
sentinels, pointers, and trailer). No created save has been loaded by the game.
Shape equality is not acceptance, and the schema defaults are not verified
against the game's New Game initialisation. This remains unproven.

**Autosave slot rotation.** The game does not overwrite the loaded slot. An
in-game save writes a **new** `slot_NN`, and Continue loads the newest
`progress.sav` by modification time. Impact: editing an older slot alone does
not affect Continue. v1 renders `SlotRotationWarning`
(`lib/presentation/dialogs/slot_rotation_warning.dart`) inside the Save As
dialog when the active slot is not the newest. That warning has no wired "Use
newest slot" callback, and the dialog's "make newest" checkbox is not consumed:
`SaveAsRequest.markNewest` is never read by the save path, and no code changes a
file's mtime. So the app explains the rotation risk but does not correct the
load order; choose the newest slot yourself.

**No-checksum clarification.** The 2-byte edit loaded without any checksum
recomputation, which confirms that the edited path has no integrity field to
update. It does not mean the game validates every value: a control edit with
`Life=999` and `MaxLife=12` loaded, and the game clamped `Life` to 12 at runtime
while the on-disk file kept 999 until the next save. The editor must enforce
semantic invariants such as `Life <= MaxLife` itself, rather than relying on
game rejection.

## 3. 11,657 `Bool64bitKey` fields are declared but absent from `progress.sav`

**Impact.** The schema declares 11,925 on-disk fields and 11,657
`Bool64bitKey` declarations that are not in the save record stream. A catalogue
built from the schema contains entries that cannot be read or written from a
save file; showing them as editable would be false.

**Mitigation.** Keep absent fields schema-only and visibly separate from on-disk
fields. Do not synthesize them into a save without a verified writer path and a
game test. The schema validation continues to reject a `Bool64bitKey` that
appears in on-disk data (`lib/domain/schema/`, `test/domain/schema/`).

## 4. Inventory semantics are only partly mapped

**Impact.** The save stores acquisition flags, not per-item stock. The Inventory
tab toggles named `IsGet.*` flags and edits bottle contents; it states that per-
item stock and ammo counts are not stored, and only
`PouchData.Item_Token_Gold.StockNum` is a named count. Which raw field owns a
pouch slot, and how equipment ownership differs from equipped state, is not
fully mapped. Some stored actor text is therefore shown read-only.

**Mitigation.** Edit only named, verified fields. Keep unrecognised actor text
read-only. Do not invent a stock or ownership relationship from offsets; require
a field-level citation and a sample observation.

## 5. `Binary`, `BinaryArray`, and `WString16Array` layouts are partly opaque

**Impact.** These tail values have no length derivable from a verified header.
The committed progress codec infers a span from the next tail pointer or EOF and
preserves it as opaque bytes. Structural edits inside them are unsafe, and a
wrong inference could misplace later records. The new-save builder zero-fills
the `Binary` payloads it emits.

**Mitigation.** Keep these types opaque and byte-preserving; do not offer typed
editing. Add a fixture that pins every inferred span and its boundary before
treating any layout as verified. A wrong inference must fail loudly.

## 6. Enums are stored as hashes

**Impact.** A stored enum value is a 32-bit hash of a member name. The schema
resolves 2,499 member hashes across 75 tables (1,257 unique members), but an
unknown member cannot be named and any UI must fall back to the raw hash,
labelled `Unknown 0x…` or equivalent. Rewriting one, or presenting it as a named
choice, risks changing data the editor does not understand.

**Mitigation.** Preserve unknown hashes exactly and display the raw value with an
unknown marker. Offer a named choice only when the schema resolves the hash;
never map an unknown hash to a nearest name. Include the hash in diagnostics.

## 7. Scene identity is a string; only 3 of 80 maps are observed

**Impact.** There is no remake numeric scene-id space to write. Scene and map
fields are ASCII strings such as `KokiriForest/KokiriForest_Child`. Only
`kokiri-start`, `castle-gate`, and `market-entrance` have been seen in a real
save. Acceptance of the other 77 known map strings by the game is untested.

**Mitigation.** Validate against the known map/base-scene list, warn on unknown
printable strings, and reject decimal or `0x` ids in these fields. Do not carry
N64 scene ids into a remake save. Treat an unobserved map as a warning.

## 8. `bitsdojo_window` is unmaintained

**Impact.** The frameless window and custom title bar depend on a package whose
upstream maintenance is uncertain. A future Flutter or GTK change can break the
build or the window controls. This is build risk, not save-format risk.

**Mitigation.** The dependency is pinned at `^0.1.6` and already spans more
than the title bar: `lib/main.dart`, `lib/app.dart`, the title bar
(`lib/presentation/widgets/chrome/app_title_bar.dart`), and
`lib/presentation/dialogs/open_save_browser.dart` import it, while
`linux/runner/my_application.cc` carries the include plus
`bitsdojo_window_from` / `setCustomFrame(true)` (three physical lines). Do not
spread it further and do not upgrade it casually. Keep
`BombFlowerApp(enableWindowChrome: false)` working so widget tests never depend
on native chrome. Plan a replacement before it blocks a Flutter upgrade.

**Measured 2026-11-23.** Last upstream commit `2023-12-23T14:38:15Z`
(`978d1ee`), 114 open issues (122 including 8 open PRs), 839 stars, and the
only published release is `0.1.6` (2023-12-23). It **does build** on Flutter
3.50.1 / Dart 3.14.0: a scratch Linux app depending on `bitsdojo_window ^0.1.6`
built in debug and in release, and the debug binary ran. The human decided to
keep it, because migrating to `window_manager 0.7.1` requires a native-API move
(`windowManager.*` → `WindowManager.instance.getCurrent()`,
`setAsFrameless()` → `setFrameless()`) and rewrites a working title bar for no
user-visible gain. Full record: `docs/RESEARCH-FORMATS.md` §9.2.

### Dependency rulings that are settled

- **Picker — forced choice.** `file_picker >=13.3.3` cannot resolve alongside
  the mandated `bitsdojo_window ^0.1.6`: `bitsdojo_window_windows` requires
  `win32 ^5.1.1`, while `windows_file_picker` requires `win32 ^6.3.0`. The
  solver's suggestion was to downgrade to `file_picker ^11.0.3`; the human
  rejected pinning an old picker and chose `file_selector ^1.1.0`
  (`pubspec.yaml:16`), the official Flutter-team GTK path. Recorded at
  `docs/RESEARCH-FORMATS.md` §9.1.
- **Hex editor — no supplier.** There is no maintained editable hex widget:
  `flutter_hex_editor`, `hex_editor`, and `byte_editor` return HTTP 404 on
  pub.dev, and `hex_viewer 0.2.1` is read-only (its only data hooks are
  `final List<int> data` and `onSelectionChanged`). The custom editor in
  `lib/presentation/widgets/hex/` is therefore justified by the rule
  "third-party where a supplier exists, hand-rolled only where none does".
  Recorded at `docs/RESEARCH-FORMATS.md` §9.3.

## 9. Verification is Linux-only; headless CI has no real window manager

**Impact.** Windows and macOS are untested. The Xvfb smoke test proves only that
the process starts and stays alive; it does not prove a first frame, dragging,
minimising, closing, multi-monitor behaviour, or compositor integration. Those
paths can regress without a failing test.

**Mitigation.** State Linux as the only supported target. Run a manual
window-chrome check under Wayland and X11 before a release. Do not claim platform
support from a headless run. Add a display-backed CI job before widening support.

## 10. The former gap panels are now editors

**Impact.** Progression and Dungeons became editors in `f4e0499`; Collectibles
and Flags in `3048558`. No tab constructs `V1GapPanel` any more, so the earlier
limitation — four field sets visible only as verified counts — no longer
applies. Each tab still exposes only fields the save's own descriptor marks
editable; hash-only fields remain read-only (section 11) and inspectable only as
raw bytes in Advanced Data.

**Mitigation.** Keep the rule that a tab ships only when its field semantics,
ownership rules, and write path are verified; a count of named fields is not a
mapping.

## 11. 8,317 unnamed fields are read-only

**Impact.** Of the 11,925 on-disk fields, 3,608 have a verified name and 8,317
are hash-only. Unnamed fields keep their bytes, appear by hash, and cannot be
edited through a typed control. A user who needs one of them must use the raw
hex editor, with the risks that implies.

**Mitigation.** Keep unnamed records read-only and clearly labelled. Do not
promote a hash-only field to a named editor without a recovered name and a
fixture that proves the mapping.

## 12. Comparison is a read-only, per-slot dialog

**Impact.** v1 has an original-versus-edited view: the Compare action opens
`CompareSaveDialog`, which lists changed fields with Original and Current
values, provenance badges, FNV-1a fingerprints, and coalesced changed byte
spans. It is inspection only. It shows one slot at a time, it does not compare
two exports, it cannot accept or reject an individual hunk, and its "original"
is the in-memory bytes captured when the slot was opened. There is no
side-by-side editable diff and no export preview.

**Mitigation.** Treat Compare as a review aid, not an approval gate. For a
byte-level audit against a stored copy, use the sidecar
`.bombflower-original/` directory and an external diff tool.

## 13. A revision gate rejects unknown future saves

**Impact.** Only revision `2982123` (`0x2d80eb`) is understood. A game update
that changes it is rejected with `ParseUnsupported` instead of opened
best-effort. This is intentional, but the editor stops working until the layout
is updated.

**Mitigation.** Treat the rejection as safety, not a bug. Add a new layout only
with fresh samples and tests; never widen the accepted revision range to "make
it open". Report the detected revision in diagnostics.

## 14. The footer reports engine validation, not tab-level cross-field rules

**Impact.** The status footer summarises the session's engine `ValidationIssue`
list (`lib/presentation/bloc/save_session/save_session_cubit.dart`, the
`_validationSummary` helper). Cross-field rules that a tab evaluates locally are
not in that list, so a conflict can be visible in a tab while the footer reports
no blocking issues. Concretely, with `Life=16` and `MaxLife=12`, Resources shows
**`Health values conflict`** with `Life (16) exceeds MaxLife (12).`
(`lib/presentation/shell/tabs/resources_tab.dart`,
`lib/domain/validation/field_validators.dart`) while the footer still reads
`No blocking issues · 8328 informational notes`. The export gate
(`SaveEngine.export` → `plan.blockingIssues`, `lib/domain/engine/save_engine.dart`)
consumes engine issues, so this tab banner is not an export refusal.

**Mitigation.** Read the tab banner as the check for the values that tab covers;
do not treat the footer as a complete validation report. Confirm cross-field
values in the tab before exporting. Do not claim the conflict blocks export.

## 15. The system file dialog is structurally fragile on Linux

**Impact.** Opening a save must not depend on the GTK folder chooser. The
in-app browser (`lib/presentation/dialogs/open_save_browser.dart`) is the
primary and only open path; the native chooser survives only as the Browse
fallback in Save As and Duplicate
(`lib/presentation/dialogs/save_as_dialog.dart:137-171`).

`file_selector_linux 0.9.4+1` uses `GtkFileChooserNative`, not
`GtkFileChooserDialog`: `gtk_file_chooser_native_new(...)` at
`file_selector_plugin.cc:59-61`, run through `gtk_native_dialog_run` at
`:144-145`, with the parent taken implicitly as
`GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)))` at `:135`. The plugin
contains no `gtk_window_set_transient_for` and no `gtk_window_set_modal`, so
"make the dialog transient/modal" is not implementable in this repository.

The likely cause of the unclickable-sidebar defect (issue #273) is
`bitsdojo_window_linux 0.1.4`, not parenting: `setCustomFrame` calls
`gtk_window_set_decorated(window, FALSE)` (`window_impl.cpp:123`) and registers
a screen-wide CSS provider with `window { background:none; }` at
`PRIORITY_APPLICATION` (`:129-137`). That selector reaches every `window` node,
including the native dialog's own window.

**Mitigation.** Keep the in-app browser as the open path. Keep the native
chooser opt-in/fallback and warn about it in plain English in Settings
(`lib/presentation/shell/tabs/settings_tab.dart`, the "System file dialog
(Linux)" section). Do not pursue plugin-level workarounds such as swapping in
`GtkFileChooserDialog` or toggling the frame while the dialog is open: both are
fragile, and the in-app browser sidesteps the whole class. Reviewed 2026-11-23
against the package versions named above.

