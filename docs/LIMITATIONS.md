# Limitations

This document lists what Bomb Flower cannot yet prove or do. An unlisted
limitation is a documentation bug, not a feature.

Status is as of 2026-11-22; the last commit reviewed is `bcae1ea`. Check
`git log` and the current test output before relying on any statement.

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

## 2. Edited-save acceptance is one scalar case, not a general guarantee

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
rejected nor silently repaired the edit.

**Still not proven.** Arbitrary field types (strings, enums, vectors, arrays),
corrupt-file rejection, multi-slot or multi-region edits, and later game
versions. The E2E harness is not committed, no game binary or asset is shipped,
and this is not a repeatable CI test.

**Autosave slot rotation.** The game does not overwrite the loaded slot. An
in-game save writes a **new** `slot_NN`, and Continue loads the newest
`progress.sav` by modification time. Impact: editing an older slot alone does
not affect Continue. Mitigation: edit the newest slot, or confirm which slot the
game will load. The planned app mitigation is to warn when the open slot is not
the newest and to offer an explicit-consent update of the newest slot's
`progress.sav` mtime; the warning and the mtime update are **not implemented in
committed code as of this documentation commit**.

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

## 4. Pouch and inventory ownership is not mapped to raw fields

**Impact.** The editor cannot reliably say which raw field gives a pouch item to
the player, how inventory slots are owned, or how equipment ownership differs
from equipped state. An inventory screen built now would invent relationships.

**Mitigation.** Do not expose inventory or pouch editing from raw offsets. Keep
the tab read-only or a placeholder. Preserve all bytes outside verified fields.
Require a field-level citation and a sample observation for each ownership field.

## 5. `Binary` and `WString16Array` layouts are unverified

**Impact.** These tail values have no length derivable from a verified header.
The committed progress codec infers a span from the next tail pointer or EOF and
preserves it as opaque bytes. Structural edits inside them are unsafe, and a
wrong inference could misplace later records.

**Mitigation.** Keep both types opaque and byte-preserving; do not offer typed
editing. Add a fixture that pins every inferred span and its boundary before
treating either layout as verified. A wrong inference must fail loudly.

## 6. Enums are stored as hashes

**Impact.** A stored enum value is a 32-bit hash of a member name. Without a
matching name table, an unknown member cannot be named and any UI must fall back
to the raw hash, labelled `Unknown 0x…` or equivalent. Rewriting one, or
presenting it as a named choice, risks changing data the editor does not
understand.

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

**Mitigation.** Keep the dependency isolated to `lib/main.dart`, the title bar,
and the two lines in `linux/runner/my_application.cc`. Pin the version. Keep
`BombFlowerApp(enableWindowChrome: false)` working so widget tests never depend
on native chrome. Plan a replacement before it blocks a Flutter upgrade.

## 9. Verification is Linux-only; headless CI has no real window manager

**Impact.** Windows and macOS are untested. The Xvfb smoke test proves only that
the process starts and stays alive; it does not prove a first frame, dragging,
minimising, closing, multi-monitor behaviour, or compositor integration. Those
paths can regress without a failing test.

**Mitigation.** State Linux as the only supported target. Run a manual
window-chrome check under Wayland and X11 before a release. Do not claim platform
support from a headless run. Add a display-backed CI job before widening support.

## 10. The codecs are committed, but engine and UI integration is not

**Impact.** `ProgressCodec` and `CaptionCodec` can decode, edit, and re-encode
their files standalone, and their real-sample tests pass when fixtures are
present. `SaveEngine` still has no `LayoutDescriptor` adapter for the
`progress.sav` record stream, and no UI path opens a save. The two real-format
engine invariants in `test/domain/engine/roundtrip_invariants_test.dart` remain
skipped. Ten tabs are placeholders and Overview says "No save file open".

**Mitigation.** Do not present Bomb Flower as a working end-to-end save editor
yet. Keep the skipped tests visible and un-faked. Add the record-stream adapter
and the real-file engine round-trip before enabling any open/save control in the
UI.

## 11. A revision gate rejects unknown future saves

**Impact.** Only revision `2982123` (`0x2d80eb`) is understood. A game update
that changes it is rejected with `ParseUnsupported` instead of opened
best-effort. This is intentional, but the editor stops working until the layout
is updated.

**Mitigation.** Treat the rejection as safety, not a bug. Add a new layout only
with fresh samples and tests; never widen the accepted revision range to "make
it open". Report the detected revision in diagnostics.
