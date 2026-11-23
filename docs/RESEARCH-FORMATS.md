# Bomb Flower — save-format research record

This is the durable record of what Bomb Flower knows about the save container it
edits, and of the rulings that shaped the app around it. It replaces the scratch
notes that lived in `.tmp/research/`. Every claim carries a `path:line` citation;
a claim without one is a bug in this document.

Longshot (`/home/daze/GitHub/Longshot`) is read-only research input. Nothing in
this repository writes to it, and no offset below is copied from a Longshot
parser, because Longshot does not have one.

Certainty labels used throughout:

| Label | Means |
| --- | --- |
| **VERIFIED-IN-SOURCE** | A cited source states it, or three independent samples agree with the arithmetic. |
| **INFERRED** | The bytes or names are consistent with the claim, but no source names the semantics. |
| **UNKNOWN** | No verified name, unit, count, mapping, or layout exists. Preserve the bytes; do not guess. |
| **NOT-IN-SOURCE** | The fact does not exist in Longshot at all; it was derived from real sample bytes. |

---

## 1. What Longshot is and what it owns

Longshot is a static-recompilation port of the Switch 2 remake of *Ocarina of
Time* to Windows and Linux: "Longshot is a static recompilation tool. It
translates a supported console game's code to C and compiles it into a native
port" (`/home/daze/GitHub/Longshot/README.md:28`). It is not a save editor and
contains no byte-level `progress.sav` parser.

Its complete save awareness is: list the files, report their size and mtime,
pick the newest slot for Continue, read the `caption.sav` preview header, and
copy `progress.sav` unchanged.

| What Longshot has | Citation |
| --- | --- |
| A file record of name, size, and mtime — no field data | `host/control.c:1814` — `typedef struct { char name[64]; int64_t size, mtime; } SaveFile;` |
| A JSON save listing of slot paths, sizes, mtimes, and the caption JSON | `host/control.c:1903-1943` (`cmd_saves`) |
| Newest-slot selection for Continue, by mtime | `host/oot_autoload.c:59-60,92` (`hos_oot_newest_save`) |
| A byte-for-byte copy of `progress.sav` | `docs/dev/reference/saves.md:89` — "`progress.sav` is copied as it is" |
| A no-op copy path that prints `progress.sav: copied unchanged` | `scripts/longshot_saves.py:1048-1049` |

**Consequence, stated plainly:** every `progress.sav` offset in Bomb Flower's
documents is **NOT-IN-SOURCE** in Longshot. The header, record, sentinel, tail,
and footer offsets come from the bytes of the three real samples
(`kokiri-start`, `castle-gate`, `market-entrance`, 120,572 bytes each), checked
by arithmetic — not from a Longshot parser, and not from a Longshot constant.
Only the `caption.sav` offsets are also present in Longshot source (§4).

---

## 2. Save identity

The file set is per-slot under a profile folder:

```
<save folder>/
  account.sav
  option.sav            the game's own settings
  slot_NN/
    progress.sav
    caption.sav         the Load screen's header and picture
```

(`/home/daze/GitHub/Longshot/docs/dev/reference/saves.md:17-24`.)

The `SaveFileIndex` map names the same files by index
(`docs/SAVE-FORMAT.md:72-80`):

| Index | Path | `SaveTypeHash` | Bomb Flower reads it? |
| ---: | --- | ---: | --- |
| 0 | `slot_%02d/progress.sav` | 2749067540 | yes — full field layout |
| 1 | `option.sav` | 2785780629 | no — no documented layout |
| 2 | `slot_%02d/caption.sav` | 653480507 | yes — header only |
| 3 | `account.sav` | 3198092477 | no — no documented layout |

Bomb Flower does not read `option.sav` or `account.sav`, and their internal
layouts are **UNKNOWN** (`docs/SAVE-FORMAT.md:314`).

**Region: UNKNOWN.** No document and none of the three samples state a
region (PAL / NTSC / JPN). No region marker was located in the container. Do
not infer one from a build string or a file size.

---

## 3. Container layout — `progress.sav`

File-absolute offsets, little-endian unless stated
(`docs/SAVE-FORMAT.md:60-65,83-105`;
`lib/domain/save/progress_layout.dart:183-247`;
`lib/data/codec/progress_codec.dart:235-345`).

| Offset | Size | Endianness | Value in every sample | Meaning | Certainty |
| ---: | ---: | --- | --- | --- | --- |
| `0x00` | 4 | LE u32 | `0x01020304` (bytes `04 03 02 01`) | magic | VERIFIED-IN-SOURCE |
| `0x04` | 4 | LE u32 | `2982123` (`0x002D80EB`) | schema revision | VERIFIED-IN-SOURCE |
| `0x08` | 4 | LE u32 | `0x000175D8` = 95,704 | absolute tail offset (stored, not derived) | VERIFIED-IN-SOURCE |
| `0x0C` | 28 | — | all zero (`0x0C`–`0x27`) | reserved | VERIFIED-IN-SOURCE |
| `0x28` | 4 | LE u32 | Murmur3 of the field name, seed 0 | first record key | VERIFIED-IN-SOURCE |
| `0x2C` | 4 | LE u32 | value or absolute tail offset | first record value | VERIFIED-IN-SOURCE |

The record stream is exactly 11,958 records:

- record = `{u32 LE key, u32 LE value}`, 8 bytes;
- `recordCount = (tail − 0x28) / 8 = (0x175D8 − 0x28) / 8 = 11,958`;
- 11,925 fields + 32 sentinels + 1 footer = 11,958;
- key `0` is a sentinel whose value is the section type id `1..32`; sections
  appear in increasing order and 12 of them are sentinel-only;
- the last record is not a sentinel: it is the footer
  `{2749067540, 120564}`, where `2749067540` is `SaveTypeHash[0]` and `120564`
  is file size − 8. The footer's meaning is **UNKNOWN**; it is preserved
  verbatim.

Field names are not stored. `key = Murmur3_x86_32(name, seed 0)`
(`docs/SAVE-FORMAT.md:13,83-91`). Of the 11,925 on-disk fields, 3,608 have a
verified name; 8,317 are hash-only (`docs/SAVE-FORMAT.md:52-54`).

---

## 4. `caption.sav`

Samples are 4,741 bytes each (`lib/domain/save/caption_layout.dart:3-7`).

| Offset | Size | Field | Value in samples | Certainty |
| ---: | ---: | --- | --- | --- |
| `0` | 4 | magic `04 03 02 01` | same as progress | CONFIRMED |
| `540` | 4 LE u32 | `layoutCheck` | `1392` | CONFIRMED |
| `684` | 64 ASCII, NUL-padded | scene name | `KokiriForest`, `HyruleField`, `Market` | CONFIRMED |
| `748` | 64 ASCII, NUL-padded | map path | `KokiriForest/KokiriForest_Child`, … | CONFIRMED |
| `1392` | 4 LE u32 | JPEG length | `3345`; `1396 + 3345 = 4741` | CONFIRMED |
| `1396` | to EOF | JPEG | starts `FF D8 FF E0 … JFIF`, ends `FF D9` | CONFIRMED |

These offsets (and the magic) are **CONFIRMED in Longshot**, independently of
Bomb Flower's samples:

- `host/control.c:1869-1871` — comment: "magic 04 03 02 01; the names at 684 and
  748, the JPEG's length at 1392 and the JPEG at 1396";
- `host/control.c:1882` — the magic check `memcmp(h, "\x04\x03\x02\x01", 4)`;
- `host/control.c:1885` — `h + (which ? 748 : 684)`;
- `host/control.c:1894` — the 32-bit JPEG length read at 1392;
- `host/control.c:1899-1900` — `h[1396] == 0xff && h[1397] == 0xd8` plus the
  `1396 + jpeg <= total` bound;
- `scripts/longshot_saves.py:573-577` — `CAPTION_MAGIC`, `CAPTION_SCENE`/
  `CAPTION_MAP`/`CAPTION_NAME_LEN` (684, 748, 64), `CAPTION_CHECK = 540`,
  `CAPTION_JPEG_LEN = 1392`, `CAPTION_JPEG = 1396`;
- `scripts/longshot_saves.py:609-622` — the reader that enforces exactly this
  layout and calls any other layout an error;
- `docs/dev/reference/saves.md:91-95` — the prose statement of the layout.

Bomb Flower's own layout constants are `lib/domain/save/caption_layout.dart:129-147`
(`sceneNameOffset`, `mapPathOffset`, `layoutCheckOffset`, `jpegLengthOffset`,
`jpegOffset`).

**Citation drift found (correction, not a claim change).**
`lib/domain/save/caption_layout.dart:179` cites
`scripts/longshot_saves.py:573-574` for `CAPTION_CHECK=540`. The actual lines
are `575-577` (575 `CAPTION_CHECK`, 576 `CAPTION_JPEG_LEN`, 577 `CAPTION_JPEG`).
The whole constant block in that Dart file is two lines early: `571` should be
`573` (`CAPTION_MAGIC`), `574` should be `576` (`CAPTION_JPEG_LEN`). The
constants themselves are correct; only the line numbers were stale. Fixing
those comments is safe and does not change a byte-level claim.

---

## 5. Integrity — there is no checksum

**No checksum exists.** A probe over all three `progress.sav` and all three
`caption.sav` samples tested:

- the classic OoT `u16` byte-sum in a `0x2000`-byte block header;
- CRC32, Adler32, FNV-1a-32, byte-sum, and 32-bit word-sum over the whole file,
  header+table, table, and tail;
- every stored u32 against each of those digests;
- every stored u32 against CRC32 of the bytes preceding it.

No candidate reproduced a stored value (`docs/SAVE-FORMAT.md:238-251`). This is
a **negative probe result**, not a structural proof, which is why the wording
stays "no checksum was found" rather than "the format has none".

Behavioural corroboration: a two-byte edit (`Life` 12→16, `MaxLife` 12→16)
loaded with no checksum recomputed, and the game accepted and re-saved it
(`docs/LIMITATIONS.md:45-56`). A control edit with `Life=999` also loaded, and
the game clamped `Life` at runtime while the file kept 999
(`docs/LIMITATIONS.md:80-86`) — so absence of a checksum does not mean the game
validates values.

Longshot does not compute a checksum either. Its write journal stores only
`"%c %s\n"` (operation kind and path), with no digest, and a terminating `E`
line (`host/nn_fs.c:756-777`, format string at line 771).

**RULE: NEVER INVENT A CHECKSUM.** Do not add an integrity field, do not
"repair" the footer, and do not describe an export as checksum-verified. The
footer values (`120564` for progress, `0` for caption) are opaque and preserved
(`docs/SAVE-FORMAT.md:249-251`; `docs/LIMITATIONS.md:14-27`).

---

## 6. Field inventory

Names and hashes are grounded in `assets/schema/gamedata_110.json`, where every
named field carries `name` plus `nameSource` (`host`, `struct`, `string`, or
`prefix`), and in `docs/FIELDS.md`. Hashes below were re-read from the schema
for this document. "Editable" follows the `sf=0` rule: only `SaveFileIndex 0`
rows are editable in `progress.sav` (`docs/FIELDS.md:21-23`).

| Group | Example symbol | Hash | Type / section | Editable | Certainty |
| --- | --- | --- | --- | --- | --- |
| Player position | `Player_Pos_For_Map` (`prefix`) | `0x960AD56A` | Vector3 / 11 | yes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:52-56`) |
| Player rotation | `Player_Rot_For_Map` (`host`) | `0xA4AEE8CD` | Float / 5 | yes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:53-56`) |
| World / map identity | `Sequence_CurrentBanc` (`host`) | `0x1D6189DA` | String64 / 17 | yes, map-string validated | VERIFIED-IN-SOURCE (`docs/FIELDS.md:145`; `docs/WORLD.md:26-36`) |
| Health | `PlayerStatus.Life` (`host`) | `0x31AB5580` | Int / 3 | yes (quarter hearts) | VERIFIED-IN-SOURCE (`docs/FIELDS.md:29-30,40-42`) |
| Magic | `PlayerStatus.MP` (`struct`) | `0x76B18200` | Int / 3 | yes; **unit UNKNOWN** | VERIFIED-IN-SOURCE for name/type (`docs/FIELDS.md:31-32`) |
| Rupees | `PlayerStatus.CurrentRupee` (`host`) | `0xA77921D7` | Int / 3 | yes; no verified cap | VERIFIED-IN-SOURCE (`docs/FIELDS.md:33,44-46`) |
| Inventory — acquisition flags | `IsGet.Item_Hookshot` (`string`) | `0xFF98ED58` | Bool / 1 | yes | VERIFIED-IN-SOURCE (`docs/LIMITATIONS.md:100-111`) |
| Inventory — stock / pouch slot | only `PouchData.Item_Token_Gold.StockNum` is a named count | `0x04735978` | Int / 3 | no (mapping unknown) | **UNKNOWN** (`docs/LIMITATIONS.md:100-111`) |
| Ammo / per-item stock | no verified per-item field exists | — | — | no | **UNKNOWN** (`docs/LIMITATIONS.md:102-107`) |
| Equipment | `PlayerStatus.EquipWeapon` (`struct`) | `0xA95A3521` | String64 / 17 | text only; preserve trailing bytes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:73-89`) |
| Bottles | `…BottleInfo.BottleA.BottleItem` (`struct`) | `0x7D48DF76` | Enum / 7 | yes (13-member table) | VERIFIED-IN-SOURCE (`docs/FIELDS.md:96-107`) |
| Songs (individual) | `HavePlayedEvent.Dm_MelodyGet_Saria` (`string`) | `0x35307FEB` | Bool / 1 | yes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:143-158`) |
| Quest / story (individual) | `AllSage_AwakeSageCount` (`string`) | `0xBF5F1321` | Int / 3 | yes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:111-124`) |
| Quest aggregate (medallions, stones, wallet) | no single bitmask or capacity field is named | — | — | no | **UNKNOWN** (`docs/FIELDS.md:121-124,229-230`) |
| Dungeon items (only 5 named) | `DungeonInfo.FireTemple.IsGetBossKey` (`string`) | `0xB72D73DF` | Bool / 1 | yes | VERIFIED-IN-SOURCE for those 5 (`docs/FIELDS.md:128-139`) |
| Dungeon key/map/boss set — complete group | small keys are per-room `*_GetSmallKey_*` | `0x57771BBD` | Bool / 1 | yes, individually | **UNKNOWN** as a group; no counts (`docs/FIELDS.md:135-139`) |
| Collectibles (named flags) | `InsideTheDekuTree_Heart_Container_Obtained` (`string`) | `0x98CA7AAB` | Bool / 1 | yes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:162-178`) |
| Collectibles — Gold Skulltula count | no `GoldSkull`/`GSFlag` field is named | — | — | no | **UNKNOWN** (`docs/FIELDS.md:169-174`) |
| Switches | `DodongoCavern_StepSwitch_02` (`string`) | `0x03061F09` | Bool / 1 | yes | **INFERRED** (grouping from the name only) |
| Event flags | `HavePlayedEvent.Entry_LonLonRanch` (`string`) | `0x0119E2AE` | Bool / 1 | yes | VERIFIED-IN-SOURCE (`docs/FIELDS.md:162-178`) |
| Raw unknown regions | 8,317 unnamed on-disk fields, `Binary`/`BinaryArray`/`WString16Array`, 12 empty sections | — | mixed | no (read-only / raw hex) | **UNKNOWN** (`docs/SAVE-FORMAT.md:52-54,307-315`; `docs/LIMITATIONS.md:113-123,183-192`) |

Notes that must not be papered over:

- the save stores **acquisition flags, not per-item stock** — the Inventory tab
  toggles `IsGet.*` and bottle contents, and honestly states that stock and
  ammo are not stored (`docs/LIMITATIONS.md:100-111`);
- 10,212 `Bool` fields, of which 3,443 are named and 6,769 are hash-only
  (`docs/FIELDS.md:176-178`);
- `Bool64bitKey` (11,657) and `declaredNotSaved` (1,220) rows are **not**
  `progress.sav` fields (`docs/LIMITATIONS.md:88-98`; `docs/FIELDS.md:58-69`);
- a verified field *name* proves the hash preimage, not the game semantics. The
  `Switches` row is the one place where a verified name was stretched into a
  group: the name and the bytes agree, but nothing states that the bit means
  "switch pressed", so the row stays INFERRED rather than VERIFIED.

---

## 7. Serialization path — Bomb Flower's implementation

**This is Bomb Flower's own writer. Longshot has no `progress.sav` writer and
none of these classes exist there.** Roles only; the code is authoritative.

| Stage | Symbol | file:line | Role |
| --- | --- | --- | --- |
| Open a slot | `SaveEngine.open` | `lib/domain/engine/save_engine.dart:39` | Reads slot bytes through a `SlotSource` and parses them. |
| Decode `progress.sav` | `ProgressCodec.decode` | `lib/data/codec/progress_codec.dart:124` | Validates magic, revision, and header shape, then delegates. |
| Parse records | `ProgressCodec._parse` | `lib/data/codec/progress_codec.dart:235` | Walks the 11,958 records, sentinels, and footer. |
| Measure tail spans | `ProgressCodec._tailLength` | `lib/data/codec/progress_codec.dart:444` | Computes each offset span from the next pointer or EOF. |
| In-memory model | `ProgressSave.fromDecodedBytes` | `lib/domain/save/models/progress_save.dart:153` | Holds the original bytes and resolved records. |
| Apply edits | `ProgressSave.applyEdits` | `lib/domain/save/models/progress_save.dart:342` | Patches only the 4-byte value word or the edited span. |
| Encode | `ProgressSave.encode` | `lib/domain/save/models/progress_save.dart:236` | Returns the patched buffer; unedited decode re-encodes byte-for-byte. |
| Layout constants | `ProgressLayout`, `SaveType` | `lib/domain/save/progress_layout.dart:51,181` | Owns every header, record, sentinel, and sample constant. |
| Export gate | `SaveEngine.export` | `lib/domain/engine/save_engine.dart:798` | Refuses export when the plan has blocking issues. |
| Write | `AtomicFileWriter.writeAll` | `lib/data/io/atomic_file_writer.dart:136,224` | Writes through a temp file and swaps it in. |
| Sidecar originals | `SidecarBackup` | `lib/data/io/sidecar_backup.dart:92` | Stores and verifies `<root>.bombflower-original/` copies. |
| Created save | `NewSaveWriter.write` | `lib/data/newsave/new_save_writer.dart:72,95` | Builds a schema-default save with the sample shape. |
| Caption codec | `CaptionCodec.decode` / `encode` | `lib/data/codec/caption_codec.dart:89,195` | Reads and rewrites the preview header. |

Byte-preservation contract: an unedited decode re-encodes byte-for-byte, an
edit patches only its own span, and the file never grows, shrinks, or moves a
record (`docs/SAVE-FORMAT.md:272-292`).

---

## 8. Certainty summary and must-not-assume list

Counts over the 21 rows of the §6 table:

| Label | Count | Rule |
| --- | ---: | --- |
| **VERIFIED-IN-SOURCE** | 14 | The name and type are established by a cited source at the cited line. |
| **INFERRED** | 1 | The bytes or grouping are consistent with the evidence but no source names the semantics (Switches). |
| **UNKNOWN** | 6 | No verified name, unit, count, mapping, or layout exists. |

Outside that table: the header, records, sentinels, tail, and the five
`caption.sav` offsets are VERIFIED-IN-SOURCE (labelled CONFIRMED in §4); the
"no checksum" result is VERIFIED-IN-SOURCE as a negative probe; region,
`option.sav`/`account.sav` layouts, footer meaning, created-save acceptance, and
multi-word `BoolArray` behaviour are UNKNOWN.

### What must not be assumed

1. **No invented offsets.** Field locations come only from the stored record
   table. Never derive one from a name or a guess.
2. **No invented defaults.** Schema defaults are the BYML's declarations, not
   observed game values (`docs/SAVE-FORMAT.md:272-292`).
3. **No invented checksum.** See §5.
4. **`Bool64bitKey` is not on disk.** 11,657 declarations must never be
   synthesized into a save (`docs/LIMITATIONS.md:88-98`).
5. **1,220 `declaredNotSaved` rows are runtime-only** (`sf=-1`) and must not be
   shown as disk fields (`docs/FIELDS.md:21-23,58-69`).
6. **`Binary`, `BinaryArray`, and `WString16Array` are opaque.** Their spans are
   inferred from the next pointer or EOF; element meaning is unverified
   (`docs/LIMITATIONS.md:113-123`).
7. **8,317 of 11,925 fields are unnamed** and read-only
   (`docs/LIMITATIONS.md:183-192`).
8. **Created-save acceptance is unproven.** The builder matches the sample shape
   but no created save has been loaded by the game
   (`docs/LIMITATIONS.md:63-67`).
9. **Exactly one scalar game-acceptance result exists** (`Life`/`MaxLife`
   12→16). Strings, enums, vectors, arrays, corrupt-file rejection, multi-slot,
   and multi-region edits are unproven (`docs/LIMITATIONS.md:45-67`).
10. **Region is UNKNOWN**, and `option.sav`/`account.sav` layouts are UNKNOWN.
11. **The footer is opaque.** `120564` is size − 8; `0` for caption; neither is
    a checksum (`docs/SAVE-FORMAT.md:249-251`).
12. **`BoolArray` masks wider than one u32 are unobserved**
    (`docs/SAVE-FORMAT.md:202,310`).
13. **No numeric scene ids.** Scene and map fields are ASCII strings; N64 ids do
    not apply (`docs/WORLD.md:38-49`).
14. **File length is not an integrity signal.** Real played saves carry 280–608
    trailing bytes after the footer value (`docs/LIMITATIONS.md:29-32`).

---

## 9. Dependencies and architecture — human rulings

These are decisions, not open questions. They were made with evidence and are
recorded here so they are not re-litigated.

### 9.1 `file_selector: ^1.1.0` — the picker

Declared at `pubspec.yaml:16`; locked as a direct main dependency at
`pubspec.lock:132`. As of this document, no tracked `lib/` file imports it yet
(`grep -rn file_selector lib/` returns nothing); the call site is outside this
document's scope. What is recorded here is the dependency decision.

Two reasons, and the second is not optional:

1. It is the official Flutter-team path. `file_selector` is published by
   `flutter.dev`, and so is its Linux implementation `file_selector_linux`
   (pub.dev publisher API, verified 2026-11-23).
2. `file_picker` cannot coexist with the mandated windowing package. A probe
   package depending on both failed to resolve, and `flutter pub get` printed:

   ```text
   Because bitsdojo_window >=0.1.6 depends on bitsdojo_window_windows ^0.1.6 which depends on win32 ^5.1.1, bitsdojo_window >=0.1.6 requires win32 ^5.1.1.
   And because file_picker >=13.3.3 depends on windows_file_picker ^2.0.2 which depends on win32 ^6.3.0, bitsdojo_window >=0.1.6 is incompatible with file_picker >=13.3.3.
   So, because bf_picker_probe depends on both bitsdojo_window ^0.1.6 and file_picker ^13.3.3, version solving failed.
   ```

   The solver's own suggestion was to downgrade to `file_picker:^11.0.3`. That
   trades a maintained picker for an old one to keep a dead window package, so
   it was rejected in favour of the official GTK path.

The API Bomb Flower will call is `getDirectoryPath`, declared in the installed
source at `~/.pub-cache/hosted/pub.dev/file_selector-1.1.0/lib/file_selector.dart:135`
(`Future<String?> getDirectoryPath({String? initialDirectory, String? confirmButtonText, bool? canCreateDirectories})`).
Context7 has no `file_selector` entry — it resolves only the unrelated
`file_picker` libraries — so the package source is the authority.

### 9.2 `bitsdojo_window: ^0.1.6` — mandated, kept

Declared at `pubspec.yaml:14`. It is kept deliberately.

**It builds.** Flutter 3.50.1 / Dart 3.14.0 (`environment: sdk: ^3.14.0`):
a scratch Linux app depending on `bitsdojo_window ^0.1.6` built in debug
(`✓ Built build/linux/x64/debug/bundle/spike_app`) and in release
(`✓ Built build/linux/x64/release/bundle/spike_app`), and the debug binary ran
with the Impeller GL backend. The release build was re-verified for this
document on 2026-11-23.

**It is a maintenance risk, measured on 2026-11-23:**

| Fact | Value | Source |
| --- | --- | --- |
| Last upstream commit | `2023-12-23T14:38:15Z`, `978d1ee` | GitHub API, `bitsdojo/bitsdojo_window` |
| Open issues | 114 (122 including 8 open PRs) | GitHub search API |
| Stars | 839 | GitHub API |
| Latest release | `0.1.6`, published `2023-12-23T14:30:17Z` | pub.dev API |

**Decision: keep it.** The human ruled that migrating to `window_manager 0.7.1`
requires a native-API move (`windowManager.*` → `WindowManager.instance.getCurrent()`,
`setAsFrameless()` → `setFrameless()`) and rewrites a working title bar for no
user-visible gain. The risk is isolated to `lib/main.dart`, the title bar, and
two lines in `linux/runner/my_application.cc`, and
`BombFlowerApp(enableWindowChrome: false)` keeps widget tests off native chrome
(`docs/LIMITATIONS.md` §8; `docs/BUILD.md:145-157`).

### 9.3 The custom hex editor — retained because no supplier exists

`lib/presentation/widgets/hex/hex_editor.dart` and
`lib/presentation/widgets/hex/hex_editor_controller.dart` are hand-rolled. Checked
on 2026-11-23:

- `flutter_hex_editor`, `hex_editor`, and `byte_editor` are **not on pub.dev** —
  each `/api/packages/<name>` request returns HTTP 404
  (`NoSuchKey`).
- `hex_viewer 0.2.1` exists but is a **viewer**, not an editor. Its widget's only
  data hooks are `final List<int> data` and
  `final ValueChanged<ByteSelection?>? onSelectionChanged`
  (`lib/src/widgets/hex_viewer_widget.dart:46,68` in the 0.2.1 archive). There is
  no `onChanged`, no write callback, and no controller that mutates bytes.
- A pub.dev search for `hex editor` returns no package by that name (the top
  results are themes, icon sets, and a diagram editor).

**The rule that justifies the hand-rolled widget:** use a third-party package
where a supplier exists; hand-roll only where none does. For an *editable* hex
grid there is no maintained supplier, so this is settled and is not re-opened
without a new, working package.

---

## 10. What must not be assumed — the short version

- No invented offsets, defaults, or checksums.
- `Bool64bitKey` fields are **not** on disk (11,657 declarations).
- `Binary`, `BinaryArray`, and `WString16Array` are opaque; keep them byte-preserving.
- 8,317 of 11,925 on-disk fields are unnamed and read-only.
- Region is UNKNOWN; `option.sav` and `account.sav` layouts are UNKNOWN.
- Created-save acceptance is unproven.
- Exactly one scalar game-acceptance result exists (`Life`/`MaxLife` 12→16).
- The footer is opaque, not an integrity field.
- File length is not an integrity signal.
- A verified name proves a hash preimage, not game semantics.

If a future reader needs the detail behind any line here, it is in §1–§9 above
and in the linked documents, each with a `path:line`.
