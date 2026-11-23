# Creating a new save

Bomb Flower can build a new `slot_00` save pair from the GameData schema and
write it to a directory. The tool is `tool/create_save.dart`; the bytes come
from `NewSaveBuilder`, and the filesystem rules come from `NewSaveWriter`.

**Whether the game accepts a created save is UNPROVEN.** Creation has never
been tested in-game. The production codecs and the engine can read the bytes,
but that is not the same as Ocarina of Time loading them. Treat a created save
as a format experiment until an in-game test has been recorded.

## What is created

A successful run writes:

| File | Length | Notes |
| --- | ---: | --- |
| `<out>/slot_00/progress.sav` | 120,164 bytes | Schema defaults, verified record order. |
| `<out>/slot_00/caption.sav` | 2,029 bytes | 1,396-byte header plus a 633-byte JPEG. |
| `<out>/slot_00/caption.sav` with `--no-screenshot` | 1,400 bytes | 1,396-byte header plus `FF D8 FF D9`. |

The verified sample `progress.sav` files are 120,572 bytes. The built file is
408 bytes shorter for two reasons:

- The samples' `Binary` spans are 404, 4 and 4 bytes. The schema's `Binary`
  defaults (156000, 376 and 160000) are meaningless scalars, not verified byte
  lengths, so the builder emits a well-formed empty blob (`u32 0`) for each
  field. The 404-byte span becomes 4 bytes: **400 bytes shorter**.
- The samples have 8 zero bytes after the last tail payload (the last
  `WString16Array` payload runs to 120,564, and the file is 120,572). Their
  meaning is unknown, so the builder does not reproduce them: **another 8
  bytes shorter**.

120,572 − 400 − 8 = 120,164. The footer is still emitted verbatim; see
[Limitations](#limitations-and-unknowns).

The verified caption samples are 4,741 bytes and carry a 3,345-byte JPEG. The
builder's JPEG is an original 633-byte 1×1 image, so its caption is 2,029
bytes. It is not game artwork.

Both files are written through one `AtomicFileWriter.writeAll` batch. A
non-empty destination root is refused before anything is created unless
`--allow-overwrite` is passed; overwriting keeps `.bak` copies of the previous
files.

## `progress.sav` format recap

The file is a 40-byte header, an 8-byte-record table, and a
pointer-referenced tail. All multi-byte values are **little-endian**.

| Offset | Size | Value |
| ---: | ---: | --- |
| `0x00` | 4 | Magic `04 03 02 01`, u32 LE `0x01020304` |
| `0x04` | 4 | Schema revision `2982123` (`0x002D80EB`) |
| `0x08` | 4 | Tail/data offset `0x175D8` (95,704) |
| `0x0C` | 28 | All zero |
| `0x28` | 95,664 | 11,958 records, each `{u32 key, u32 value}` |

The record table is:

- **11,925 field records**;
- **32 sentinel records**, one `{0, typeId}` per typed section, type ids 1–32;
- **1 footer record**, `{0xA3DB7114, 0x1D6F4}`.

11,925 + 32 + 1 = 11,958 records. `0x28 + 8 × 11,958 = 0x175D8`.

There are **20 populated sections and 12 sentinel-only sections**. The
frequently quoted “19 populated” count is off by one: `WString16Array`
(typeId 28, 2 fields) is the 20th. The populated sections, in file order, are:

| typeId | Type | Fields |
| ---: | --- | ---: |
| 1 | Bool | 10,212 |
| 2 | BoolArray | 6 |
| 3 | Int | 1,144 |
| 4 | IntArray | 155 |
| 5 | Float | 76 |
| 6 | FloatArray | 3 |
| 7 | Enum | 101 |
| 8 | EnumArray | 14 |
| 11 | Vector3 | 16 |
| 15 | String32 | 1 |
| 17 | String64 | 30 |
| 18 | String64Array | 3 |
| 19 | Binary | 3 |
| 20 | BinaryArray | 2 |
| 21 | UInt | 87 |
| 22 | UIntArray | 33 |
| 23 | Int64 | 28 |
| 25 | UInt64 | 5 |
| 26 | UInt64Array | 4 |
| 28 | WString16Array | 2 |

The counts sum to 11,925. The sentinel-only ids are `9, 10, 12, 13, 14, 16,
24, 27, 29, 30, 31, 32`.

A field's record key is `Murmur3_x86_32(name, seed 0)`. The schema contains
11,925 on-disk fields; 8,317 of them have no recovered name and are keyed by
hash alone. There is **no checksum** in either save file. The footer value is
opaque, not a checksum.

## Which values are written

Every progress field takes its own `default` from
`assets/schema/gamedata_110.json`. The builder has no second table of values.
The default is encoded according to the field type:

| Schema type | Encoding of the schema default |
| --- | --- |
| `Bool` | Inline `0` or `1` in the record's value word. |
| `Int` | Inline signed 32-bit. |
| `UInt` | Inline unsigned 32-bit. |
| `Float` | Inline IEEE-754 binary32 bits. |
| `Enum` | Inline `u32` member hash (Murmur3 of the member name), not a member index. |
| `Vector3` | Offset to 3 × binary32 (12 bytes). |
| `String32` | Offset to a 32-byte NUL-terminated, zero-filled slot. |
| `String64` | Offset to a 64-byte NUL-terminated, zero-filled slot. |
| `String64Array` | Offset to `u32 arrayLen`, then `arrayLen` × 64-byte slots. |
| `BoolArray` | Offset to `u32 bitCount`, then one `u32` bit mask. `true` sets the low `bitCount` bits. |
| `IntArray` / `FloatArray` / `EnumArray` / `UIntArray` | Offset to `u32 arrayLen`, then `arrayLen` elements, each the schema's single element default. |
| `BinaryArray` | Offset to `u32 arrayLen`, then `arrayLen` × `u32` defaults. |
| `UInt64Array` | Offset to `u32 arrayLen`, then `arrayLen` × 8-byte defaults. |
| `Int64` / `UInt64` | Offset to 8 bytes. |
| `WString16Array` | Offset to `u32 arrayLen`, then `arrayLen` × 32-byte UTF-16LE slots. |
| `Binary` | Offset to `u32 0` (an empty blob), as described above. |

Examples:

- An `IntArray` with default `-1` and `arrayLen` 2 becomes `02 00 00 00`,
  then `FF FF FF FF` twice.
- A `BoolArray` with default `true` and `arrayLen` 10 becomes `0A 00 00 00`,
  then `FF 03 00 00`: bitCount 10, bits `0x3FF`.
- Every `String32`, `String64` and `String64Array` default in this schema is
  `""`, so the slots are all zero bytes; the first byte is the NUL terminator.
- A `Vector3` default such as `{x: 0, y: 0, z: 0}` becomes 12 zero bytes.
- `Int64` and `UInt64` values occupy exactly 8 bytes in the tail.

**Schema defaults are not necessarily a playable game state.** They are the
GameData declaration defaults; they do not encode the game's New Game
initialization sequence. For example, the default start position is the
origin, and the defaults do not by themselves establish a coherent inventory,
quest state or spawn setup. Nothing here has been tested in-game.

There is only one preset, `schemaDefaults`. The only Adult/Child default
difference in the whole schema is
`MiniGame_Fishing_RecordFishSize_Adult` = 45 versus
`MiniGame_Fishing_RecordFishSize_Child` = 40. Any other Adult/Child preset
would have to invent rules the schema does not contain.

## `caption.sav` format recap

The caption file is a 1,396-byte header followed by a JPEG.

| Offset | Size | Value |
| ---: | ---: | --- |
| `0` | 4 | Magic `04 03 02 01` |
| `540` | 4 | Layout marker `1392` |
| `684` | 64 | Scene name, NUL-terminated printable ASCII |
| `748` | 64 | Scene/map path, NUL-terminated printable ASCII |
| `1392` | 4 | JPEG length, little-endian `u32` |
| `1396` | rest | JPEG bytes |

The builder writes:

- Scene `KokiriForest` and map path `KokiriForest/KokiriForest_Child`. These
  are the values observed in the verified caption samples, not schema
  defaults; the schema has no caption fields.
- Six date entries fixed to **2026-01-01 00:00:00** (year 2026, month 1, day 1,
  hour 0, minute 0, second 0). The wall clock is never consulted.
- An original 1×1 JPEG generated for Bomb Flower, not game art. It is 633
  bytes. With `--no-screenshot`, the four bytes `FF D8 FF D9` are written
  instead, giving a 1,400-byte file.

`CaptionCodec` does not decode the JPEG. It checks that the declared length
reaches end of file and that the first two and last two bytes are `FF D8` and
`FF D9`. It also checks the magic, the marker at 540, the names and the date
keys. It does not prove that the image is a valid or useful JPEG.

## CLI usage

Run from the repository root, because `assets/schema/gamedata_110.json` is
resolved relative to the current working directory:

```sh
dart run tool/create_save.dart --out <dir>
```

| Flag | Meaning |
| --- | --- |
| `--out <dir>` | Destination root. Required. The tool creates `<dir>/slot_00/`. |
| `--preset <name>` | Preset name. The only value is `schemaDefaults`, which is also the default. |
| `--profile-name <name>` | Rejected with `profile_name_unavailable`; no verified schema field carries a profile or player name. Never silently ignored. |
| `--x <n> --y <n> --z <n>` | Start position. All three are required together and must be finite. Replaces the `Player_Pos_For_Map` Vector3 (hash `0x960AD56A`). |
| `--no-screenshot` | Write the 4-byte `FF D8 FF D9` marker pair instead of the 633-byte JPEG. |
| `--allow-overwrite` | Write into a non-empty directory, keeping `.bak` copies of the previous files. |
| `-h`, `--help` | Print the usage text and exit successfully. |

Exit codes:

| Code | Meaning |
| ---: | --- |
| 0 | Success, including `--help`. |
| 1 | A write failure or a decode failure after the files were written. |
| 2 | A usage error, a schema read/parse failure, a build failure (including `--profile-name`), or a non-empty destination without `--allow-overwrite`. |

Example:

```sh
dart run tool/create_save.dart --out /tmp/opencode/newsave-doc-example
```

```text
progress.sav 120164 bytes fnv1a32=0x2457304c
caption.sav 2029 bytes fnv1a32=0x446b2890
records=11958 fields=11925 sentinels=32 dataOffset=0x000175d8
section 1 count=10212
section 2 count=6
section 3 count=1144
section 4 count=155
section 5 count=76
section 6 count=3
section 7 count=101
section 8 count=14
section 11 count=16
section 15 count=1
section 17 count=30
section 18 count=3
section 19 count=3
section 20 count=2
section 21 count=87
section 22 count=33
section 23 count=28
section 25 count=5
section 26 count=4
section 28 count=2
slot_00 /tmp/opencode/newsave-doc-example/slot_00
progress /tmp/opencode/newsave-doc-example/slot_00/progress.sav
caption /tmp/opencode/newsave-doc-example/slot_00/caption.sav
progress decode=ok fields=11925 sections=32
caption decode=ok scene=KokiriForest map=KokiriForest/KokiriForest_Child jpeg=633 bytes
corrupt=0 unsupported=0
```

With `--no-screenshot`, the same run prints `caption.sav 1400 bytes
fnv1a32=0x8b00ce25` and `jpeg=4 bytes`.

## Limitations and unknowns

- **`Binary` fields.** The three `Binary` fields have schema defaults 156000,
  376 and 160000. Those values are not verified byte lengths; the sample spans
  are 404, 4 and 4 bytes. The builder emits `u32 0` for each field, a
  well-formed empty blob. This is the 400-byte reduction described above. The
  real payloads are unknown and are not reproduced.
- **Footer.** The footer record is emitted verbatim as
  `{0xA3DB7114, 0x1D6F4}`. `0x1D6F4` is 120,564, so in the built
  120,164-byte file the footer value lies **400 bytes past EOF**. The codec
  does not follow it. In the samples the same value is 8 bytes before the
  sample's end, not the file length.
- **Caption header bytes.** The verified samples carry bytes at caption
  offsets 4 and 8 (observed values: 2982123 and 672), and a table of
  hash/value entries between offsets 40 and 367. `CaptionLayout` describes only
  the six date entries in that range. The builder writes those date entries
  and leaves every other byte at offsets 4, 8 and 40..367 zero. The caption
  codec accepts that; the game may not.
- **No profile name.** No verified schema field carries a profile or player
  name. The builder's rejection message identifies the name-like on-disk
  fields as `PlayerStatus.*` equipment strings and
  `WarpPoint_*.LocationName`. `profileName` and `--profile-name` are rejected
  with `profile_name_unavailable` (exit 2).
- **One preset.** Only `schemaDefaults` exists. The only Adult/Child default
  difference in the schema is the fishing record-size pair described above;
  an Adult or Child preset would have to invent every other difference.
- **In-game acceptance is unproven.** Creation has never been tested in-game.
  The codecs, the engine and the tests can accept the bytes without proving
  that Ocarina of Time will load them, spawn the player correctly, or avoid
  corrupting state.

## Verification

What the tests currently prove:

- `test/domain/newsave/new_save_builder_test.dart` decodes the built
  `progress.sav` as `ProgressDecodeOk` with 11,958 records, 11,925 fields and
  the 32 section sentinels. It checks record order against the schema, checks
  that every sentinel closes its section, and checks the tail is contiguous
  from `dataOffset` to EOF.
- The same test proves an unedited decode re-encodes byte-for-byte, and that
  edits survive encode/decode without changing the file length.
- It feeds the built bytes to the engine under a test-local container layout
  and gets `ParseOk` with no blocking validation issues.
- It decodes the built `caption.sav` as `CaptionDecodeOk`, checks the scene,
  map path, fixed 2026-01-01 date and JPEG geometry, and round-trips the
  caption byte-for-byte. It also covers the 1,400-byte `--no-screenshot`
  variant.
- `test/data/newsave/new_save_writer_test.dart` proves the writer creates both
  files with the reported lengths and byte-identical contents, creates a
  missing root and `slot_00`, refuses a non-empty root and an existing
  `slot_00` with `destination_not_empty`, keeps the first `progress.sav` as
  `progress.sav.bak` when `allowOverwrite` is true, and reports FNV-1a 32
  fingerprints of the in-memory bytes.
- The writer hands both files to one `AtomicFileWriter.writeAll` batch.
  `test/data/io/atomic_file_writer_test.dart` covers the underlying staging,
  rename and rollback behavior; the new-save writer tests cover the refusal
  and `.bak` rules on top of it.
- The CLI's own decode lines report `progress decode=ok`,
  `caption decode=ok`, and `corrupt=0 unsupported=0` for a default build.

What the tests do **not** prove:

- That the game accepts a created save. No in-game test has been run.
- That the schema defaults form a coherent New Game state: inventory, quest
  flags, spawn setup and scene state are not validated against the game's
  initialization code.
- That the opaque `Binary` payloads, the caption header entries at offsets 4,
  8 and 40..367, or the samples' trailing 8 bytes are unnecessary. They are
  omitted or zeroed because their meaning is unverified, not because they are
  known to be irrelevant.
- That the 633-byte JPEG or the 4-byte marker pair is accepted by the game's
  caption reader. The codec only checks the container and the SOI/EOI markers.
