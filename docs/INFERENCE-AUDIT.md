# Inference audit

This file lists the claims this editor currently rests on, and how strong the
evidence behind each one actually is. Nothing here is a claim about the game
accepting a save; it is only a claim about what has been traced, observed, or
merely assumed.

Classes:

- **(a) traced** — established from Longshot/decompiled host sources, or from a
  repo doc that cites them by file:line.
- **(b) observed** — established from real saves, sample bytes, or a parse of
  this repo's own fixtures. The slot count and offsets are named.
- **(c) plausible only** — coherent with what is observed, but nothing pins it.

A row may mix classes; both are stated. A byte-level coincidence is (b), never
(a). Line numbers are against base commit `b7b1bbc`.

| Claim | Class | Evidence | Consequence if wrong |
| --- | --- | --- | --- |
| Of 11,925 on-disk field records, 3,608 have a verified name and 8,317 are hash-only; a created save parses as `ParseUnverified` with 0 blocking and 8,328 informational `field.unverified` notes (8,325 progress + 3 caption). | (b) | `docs/SAVE-FORMAT.md:52-54` (11,925 / 3,608 / 8,317); `docs/LIMITATIONS.md:39-41`; measured: `flutter test test/e2e/created_save_structure_test.dart` prints `total=8328 blocking=0 actionable=0 informational=8328 progressNotes=8325 captionNotes=3` on a 120,572-byte created save; record arithmetic is fixed by the header: (0x175D8 − 0x28) / 8 = 11,958 records = 11,925 fields + 32 sentinels + 1 footer. | Promoting a hash-only field to a named editor without a recovered preimage would present a guess as fact; and the notes are informational, so they must not be quoted as an integrity verdict in either direction. |
| The 49,968 figure is six slots × 8,328, not one slot with 41,640 extra unverified fields: the unverified descriptor **hash set is identical** between a real played slot and the created save. | (b) | Probe `.tmp/probe_unverified.dart` (throwaway, not committed) decoded `.tmp/inference-audit-a7f3/slot_00/progress.sav` (a copy of real `slot_00`, 122,852 B) and `.tmp/e2e-created/slot_00/progress.sav` (created, 120,572 B) through `ProgressCodec.decode` + `ProgressLayoutBuilder.buildProgressSlotLayout`, counting descriptors whose `confidence != FieldConfidence.verified`: `A=8325 B=8325 intersection=8325 Aonly=0 Bonly=0`. Per slot that is 8,325 progress + 3 caption = 8,328; 49,968 / 6 = 8,328 (`docs/LIMITATIONS.md:39-41`). | If the sets had differed, real saves would carry structurally different descriptors and every count here would be suspect for played saves; they do not. |
| `Binary`, `BinaryArray` and `WString16Array` spans are inferred from the next tail pointer or EOF, so they are read-only with no typed editing; the three `Binary` sample spans are 404 / 4 / 4 bytes and their payload bytes are unknown (zero-filled in new saves). | (b) for observed span lengths and the opaque rule; (c) for payload meaning | `lib/domain/save/progress_layout.dart:32-36` (`tailOpaque`); `docs/LIMITATIONS.md:117-127`; `docs/NEW-SAVE.md:55-60`; `docs/NEW-SAVE.md:291-296` (schema defaults 156000 / 376 / 160000 / 104 / 17304 are not usable lengths; the builder emits `u32 400` + 400 zero bytes, then `u32 0`, `u32 0`). | A wrong span misplaces every later record and breaks byte-identical round-trip; typed editing here would rewrite bytes the editor cannot interpret. |
| Enum values are an inline `u32` member hash (Murmur3 of the member name), not a member index. | (b) | `docs/SAVE-FORMAT.md:130` and `:165` (Enum = `u32` member hash, "byte-verified; labels Murmur3-verified"); `docs/NEW-SAVE.md:156`; `lib/data/adapter/progress_layout_builder.dart:196-204` maps member names to `member.hash`; `test/data/progress_codec_test.dart:703-712` asserts `setEnumHash` changes exactly the four value bytes and reads back the hash. No host/decompiled source is cited for the encoding, so it is not (a). | Writing an index into an enum field silently selects a different or unknown member; an unresolved hash must be shown raw, never mapped to a nearest name. |
| Schema `default` values used by `NewSaveBuilder` are BYML declaration defaults, not the game's New Game state. | (a) for default provenance; (c) for playability and coherence | `docs/SAVE-FORMAT.md:42-50` (`struct-default`: the BYML's own `Struct` member table, `Hash` = Murmur3 of the member name, `Value` = field hash); `docs/NEW-SAVE.md:180-184`; `docs/LIMITATIONS.md:67-71`. | A structurally valid created save can still be semantically wrong, and nothing in the shape check proves the game will load it. |
| The footer record is `{0xA3DB7114, value}`; `value == length − 8` for the three fixtures and the created 120,572-byte save (`0x1D6F4` = 120,564), but it is **not** a general rule for played saves. | (b) | `lib/domain/save/progress_layout.dart:226-235` (`footerValue` 0x1D6F4, opaque, never rewritten); `docs/SAVE-FORMAT.md:64`; created save: e2e prints `footer=0xa3db7114/120564` and `trailerZero=yes`, tail `0x175d8..0x1d6fc`; six real slots: footer 122,572 / 122,660 / 122,252 / 122,660 / 122,660 / 122,436 against lengths 122,852 / 122,940 / 122,612 / 122,940 / 122,940 / 122,716, i.e. length − 280 for five slots and length − 360 for `slot_02`. | Treating the footer as a total length (or recomputing it) would corrupt every real played save on write. |
| The 8-byte zero trailer sits inside the final inferred tail span, and the last tail span runs to EOF: for the created file the tail is `0x175D8..0x1D6FC` with the last 8 bytes zero, and real played saves also end in 8 zero bytes but at their own EOF. | (b) | `docs/SAVE-FORMAT.md:64`; e2e prints `tailSpans=305 tail=0x175d8..0x1d6fc trailerZero=yes`; `xxd` of `~/.local/share/longshot/.../slot_00/progress.sav` (122,852 B) ends `…1a93d8fa 0000000000000000`. | Treating the trailer as a separate region, or assuming a fixed 0x1D6F4 trailer offset, misreads every real played save (122,444–122,940 B). |
| **Highest-severity observation.** Synthesised-defaults creation (the `NewSaveBuilder` path) is reported to have crashed the game: `create_save: WARNING: synthesised-defaults mode is experimental, not game-verified, and has crashed the game in testing (SIGSEGV on load with a real caption; not listed with our caption). Template mode is recommended: pass --template <slotDir> to clone a save the game accepts.` | (b), quoted from the tool's own warning | `tool/create_save.dart:45-49`, emitted to stderr at `:280`. The wording limits the crash to a real caption, so the built caption pair is not the reported crash case; the builder's progress file is implicated. | Shipping the synthesised path as equivalent to template mode would ship a known game-crashing save generator as if it were safe. |
| The in-app dialog's warning is **softer** than the CLI's: it says a created save has never been loaded, and omits that it has crashed the game. | (b), and a UI safety defect | `lib/presentation/dialogs/new_save_dialog.dart:324-332`: `Banner(key: Key('new-save-never-loaded'))`, title `A created save has never been loaded by the game` (`:327`), message `The codecs and engine can read these bytes, which is not proof the game will. Cloning a save the game already accepts is the safer path.` (`:328-331`). | A user who creates a save from the dialog reads "never been loaded", not "has crashed in testing", and may reasonably conclude the risk is only unproven rather than observed. |
| The 11,700 / 3,372 / 3,608 count gap reconciles as a count-convention difference: 11,700 decodable descriptors + 225 opaque/uninterpretable = 11,925; the 8 progress `field.unverified` notes beyond the 8,317 hash-only fields are the eight `nameSource: prefix` fields, because the note fires on any confidence other than `verified` (measured: 8,325 progress notes on a real slot and on the created save, sets identical); 3,372 is 11,700 − 8,328 and therefore wrongly subtracts the 3 caption notes from a progress-only count. | (b), with one remainder open (c) | `test/e2e/created_save_structure_test.dart:73-83` (8,328 and 11,700/225 constants) and `:392-426` (11,925 descriptors vs 11,700 decodable vs 225 opaque); `lib/domain/engine/save_engine.dart:498-511` (`descriptor.confidence != FieldConfidence.verified` → `field.unverified`); `lib/data/adapter/progress_layout_builder.dart:166-168` (`prefix` → `FieldConfidence.inferred`); schema counts: 651 `struct` + 2,943 `string` + 6 `host` + 8 `prefix` = 3,608, and 8,317 unnamed. Arithmetic: 8,317 + 8 + 3 = 8,328; 11,700 − 8,325 = 3,375; 3,608 − 8 = 3,600 verified named; 3,375 = 3,600 − 225. Remainder open (c): the identity `3,608 = 3,375 + 225 + 8` would require all 225 undecodable descriptors to be named, which the schema does not support for the three opaque types (all unnamed) and was not measured for the other undecodable kinds; so "3,375 decoded named" is a numeric identity, not a verified per-field set. Command to settle it: group the 11,925 descriptors by `FieldConfidence` and `FieldKind.list` over one parsed slot. | Reporting 3,372 as "named fields in the created save" understates by 3; treating the 8 prefix fields as verified would upgrade an inferred name to a fact, and calling 3,375 "decoded named" may understate by up to 225. |
| Edited-save acceptance is exactly one scalar case; created-save acceptance is unproven. | (b) as a repo claim, not re-verified in this session | `docs/NEW-SAVE.md:15-24` (template mode clone of `slot_00`, `PlayerStatus.Life` `10 00 00 00` → `0c 00 00 00` at offset 82516, a one-byte `cmp -l` diff, unchanged 122,852 B, game reached `state=play` with `life 12`); `docs/LIMITATIONS.md:47`. | The singular "one scalar edit has ever loaded" must be stated as a length-preserving clone of an already-accepted slot, or it overstates generality; conversely, no created save has any acceptance evidence at all. |

## Suspect defaults and documentation discrepancies

- **86 fields have a schema default that differs from every one of the 9
  observed saves** (6 real slots + 3 fixtures): 41 Enum (mostly the shared
  `NotReady` default hash `1471695344`), 20 Bool, 7 UInt, 6 Int, 5 String64,
  3 Vector3, 3 Int64, 1 UInt64. Evidence is scratch: the cancelled agent's
  `.tmp/inference-audit-a7f3/defaults-differs.tsv` (86 rows; type histogram
  re-counted here from that file), not an independent re-measurement. Class
  (b) with that caveat. Consequence: a default no observed save uses is
  suspect and must not ship silently as a "normal" value.
- **`Binary`/`BinaryArray` schema defaults are not spans.** Verified in
  `assets/schema/gamedata_110.json`: `Binary` defaults 156000, 376, 160000;
  `BinaryArray` defaults 104, 17304 (with `arrayLen` 10). `NewSaveBuilder`
  ignores them and emits length words 400/0/0 (`docs/NEW-SAVE.md:291-296`).
  A scratch report additionally claims the first `Binary` span is variable in
  real saves (length word 2088–2496) rather than the documented constant 404;
  that is **open (c)** — not re-measured here.
- **`nameSource` vocabulary.** The asset uses `host` (6), `struct` (651),
  `prefix` (8), `string` (2,943); `docs/SAVE-FORMAT.md:42-50` names them
  `host-code`, `struct-default`, `prefix-search`, `game-string`. Verified by
  reading the asset's `nameSource` values. Both vocabularies must not be mixed
  in code, which keys off `startsWith`.
- **Enum counts.** The asset reports `enumTables: 75`, `enumMembers: 1257`,
  `enumMemberUses: 2499`; `docs/LIMITATIONS.md` §6 restates this as "2,499
  member hashes across 75 tables (1,257 unique members)", which inverts which
  number is the use count. Totals are the same; the labels are not.

## Class (c) claims

Plausibility only: the meaning of the bytes inside `Binary` payloads and the
shapes of `BinaryArray`/`WString16Array` beyond their inferred extents; the
variable first `Binary` span reported above; whether the 225 undecodable
descriptors include any named field; and the claim that a save built entirely
from schema defaults is a coherent, spawnable game state (inventory, quest
flags, start position, scene identity).

The consequence for a user is direct: a class-(c) claim is plausibility, not
proof, so a structurally valid save — right magic, right revision, 11,958
records, zero trailer, 0 blocking — may still be semantically wrong, and
nothing class (c) here establishes game acceptance. A save can pass every check
this repo performs and still fail on load.

## UI exposure

Hash-only and inferred fields are surfaced read-only with a stated reason:
`lib/presentation/widgets/data/edit_table.dart:200-205` renders
`Field name is prefix-derived (inferred), so the meaning is not verified` for
`FieldConfidence.inferred` and `Field has no verified name` for
`FieldConfidence.unverified`; `lib/presentation/widgets/help/help_surface.dart:188-192`
explains the verified versus hash-only distinction. A suspected
provenance overstatement is recorded, not fixed: `_levelFor` at
`lib/presentation/widgets/data/edit_table.dart:280-295` returns
`ProvenanceLevel.verified` for any row whose confidence is not `unverified`
or `inferred` and whose provenance is not `observed`, and the builder maps
`string`-sourced names to `FieldConfidence.verified`
(`lib/data/adapter/progress_layout_builder.dart:159-162`), so a name-derived
`string` field displays as Verified. Whether that label overstates the
evidence is a UI judgement left open (c). Opaque `Binary`/array spans have no
editor surface: not yet determined.
