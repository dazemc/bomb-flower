# Bomb Flower — save format

This document describes the container that Bomb Flower reads and writes, and
the provenance of the field schema in `assets/schema/gamedata_110.json`.

The short version:

- `progress.sav` is a 40-byte header, an 8-byte-record table, and a
  pointer-referenced tail.
- The record table is split into 32 sentinel-delimited section slots; 20 carry
  fields, 12 are empty.
- All multi-byte values are **little-endian**.
- Field names are not stored. Each key is `Murmur3_x86_32(name, seed 0)`.
- No checksum or integrity field was found. Preserve every byte you do not
  intentionally edit.
- The header's schema revision is **2982123 (`0x2d80eb`)**. Refuse to write a
  different revision until it has been researched.

Claims below are marked **byte-verified** when three independent samples agree
with the arithmetic, or **inferred** when only one layout is consistent with
the bytes.

## 1. Provenance

The schema comes from the game's own GameData definition:

| Item | Value |
| --- | --- |
| Source | `GameDataList.Product.110.byml.zs` |
| Dump path | `/home/daze/GitHub/Longshot/work/dump/romfs/GameData/GameDataList.Product.110.byml.zs` |
| Compressed SHA-256 | `e7000369f9f8d838cc35e076d756014874f8193a5e0b6cc8e74bb649516de7f1` |
| Decompressed BYML SHA-256 | `a704d680e7e1ac249c13d7407d6ae5bebabeb672e51dcc6d11be4dec6f553c99` |
| Revision sidecar | `GameDataList.Product.110.revision.txt` = `2982123` |
| Save samples | `kokiri-start`, `castle-gate`, `market-entrance` (three `progress.sav`, 120,572 B each) |
| Sample SHA-256 | kokiri-start `71cc57e12b9408f6a2dceaee6b57c5b875f37c98d629b7a9ba161aa77f53e3dc`; castle-gate `ef627ed363d206214b8ae0a37283d6213832678c6c4b1dcca88c4435da3d117c`; market-entrance `4d55d1e53142378e45c2ef7c8f8725fe3fa6e51aaaf1d04ead261db5dcc1a21d` |
| Independent key dump | `/tmp/opencode/research/fields/progress_fields.csv` (11,926 data rows: 11,925 fields + footer) |

The `.byml` is read-only research input. Neither it nor any save file, game
binary, string dump, or artwork is stored in this repository. The checked-in
JSON contains factual names, types, defaults, section ids, and enum labels.

Name provenance is recorded per field as `nameSource`:

- `host-code`: the seven constants in `host/oot_state_tap.c` lines 35–41.
- `struct-default`: the BYML's own `Struct` default member table. A member's
  `Hash` is the Murmur3 of the member name and its `Value` is the full field
  hash; both were checked.
- `prefix-search` / `game-string`: a name recovered from the game's readable
  string tables (`logic`, event, and miscellaneous ROMFS strings) and accepted
  only when `Murmur3(name) == field hash`.

The BYML stores **hashes only**. Names are evidence-backed preimages, not a
name table from the file. Of 11,925 on-disk fields, 3,608 have a verified name;
the other 8,317 are emitted with `"name": null` and counted in `unresolved`.

## 2. Container header

`progress.sav` is 120,572 bytes. All offsets are file-absolute.

| Offset | Size | Value in every sample | Meaning | Confidence |
| ---: | ---: | --- | --- | --- |
| `0x00` | 4 | `04 03 02 01` (u32 LE `0x01020304`) | Magic | byte-verified |
| `0x04` | 4 | `2982123` (`0x002d80eb`) | Schema revision | byte-verified |
| `0x08` | 4 | `0x000175d8` (95,704) | Data/tail offset | byte-verified |
| `0x0c` | 28 | all zero | Reserved | byte-verified |

`0x175d8` is also `MetaData.SaveDataOffsetPos[0]` for
`slot_%02d/progress.sav`. For `caption.sav`, byte `0x08` is `0x2a0` (672), which
is `SaveDataOffsetPos[2]`. The header value is the tail offset for the file,
not a constant.

The `SaveFileIndex` map from `MetaData.SaveDirectory` is:

| Index | Path | `SaveTypeHash` |
| ---: | --- | ---: |
| 0 | `slot_%02d/progress.sav` | 2749067540 |
| 1 | `option.sav` | 2785780629 |
| 2 | `slot_%02d/caption.sav` | 653480507 |
| 3 | `account.sav` | 3198092477 |

## 3. Record table

The record table starts at `0x28` (40) and ends at the header's data offset.

```
tail          = u32le(0x08)
recordCount   = (tail - 0x28) / 8
record[i]     = u32le key at 0x28 + 8*i, u32le value at 0x2c + 8*i
```

For the verified `progress.sav`: `(0x175d8 - 0x28) / 8 = 11,958` records.

A record with `key == 0` is a **sentinel**: its value is the section type id
(`1..32`). The last record is a footer, not a sentinel:

| Item | Value |
| --- | --- |
| Footer key | `2749067540` (`SaveTypeHash[0]`) |
| Footer value | `120564` = file size − 8 |
| Verified in | all three progress samples |
| Caption footer | `{653480507, 0}` (caption does not use file-size − 8) |
| Meaning | unknown; preserved verbatim |

The footer value is **not** a checksum (see §7). Do not recompute it from a
guess.

## 4. Sentinel sections

Sections are stored in increasing type-id order, including empty slots. The
stream is:

```
[fields of type 1] {0,1}
[fields of type 2] {0,2}
...
[fields of type 32] {0,32}
[footer]
```

An empty slot is a bare `{0, typeId}`. The 20 non-empty sections are:

| typeId | Type | Count | Field records | Sentinel record | Tail span |
| ---: | --- | ---: | --- | ---: | --- |
| 1 | Bool | 10,212 | 0–10,211 | 10,212 | inline |
| 2 | BoolArray | 6 | 10,213–10,218 | 10,219 | `0x175d8–0x17608` |
| 3 | Int | 1,144 | 10,220–11,363 | 11,364 | inline |
| 4 | IntArray | 155 | 11,365–11,519 | 11,520 | `0x17608–0x1a5d8` |
| 5 | Float | 76 | 11,521–11,596 | 11,597 | inline |
| 6 | FloatArray | 3 | 11,598–11,600 | 11,601 | `0x1a5d8–0x1a6b4` |
| 7 | Enum | 101 | 11,602–11,702 | 11,703 | inline |
| 8 | EnumArray | 14 | 11,704–11,717 | 11,718 | `0x1a6b4–0x1b4a4` |
| 11 | Vector3 | 16 | 11,721–11,736 | 11,737 | `0x1b4a4–0x1b564` |
| 15 | String32 | 1 | 11,741 | 11,742 | `0x1b564–0x1b584` |
| 17 | String64 | 30 | 11,744–11,773 | 11,774 | `0x1b584–0x1bd04` |
| 18 | String64Array | 3 | 11,775–11,777 | 11,778 | `0x1bd04–0x1c310` |
| 19 | Binary | 3 | 11,779–11,781 | 11,782 | `0x1c310–0x1c4ac` |
| 20 | BinaryArray | 2 | 11,783–11,784 | 11,785 | `0x1c4ac–0x1c504` |
| 21 | UInt | 87 | 11,786–11,872 | 11,873 | inline |
| 22 | UIntArray | 33 | 11,874–11,906 | 11,907 | `0x1c504–0x1caa4` |
| 23 | Int64 | 28 | 11,908–11,935 | 11,936 | `0x1caa4–0x1cb84` |
| 25 | UInt64 | 5 | 11,938–11,942 | 11,943 | `0x1cb84–0x1cbac` |
| 26 | UInt64Array | 4 | 11,944–11,947 | 11,948 | `0x1cbac–0x1d46c` |
| 28 | WString16Array | 2 | 11,950–11,951 | 11,952 | `0x1d46c–0x1d6f4` |

Sentinel-only ids: `9, 10, 12, 13, 14, 16, 24, 27, 29, 30, 31, 32`.

Byte-verified: the section counts sum to 11,925; every section's key set equals
the BYML's `SaveFileIndex == 0` key set for that type; all 32 sentinel records
are `{0, typeId}` in all three samples. The `recordStart`/`recordEnd` values in
the JSON are raw record indices, so a field's value word is at
`0x28 + 8*recordIndex + 4`.

## 5. Value encodings

`value` is 4 bytes. Scalars are inline; offsets are absolute file offsets.
The tail is contiguous: every non-scalar field's span starts at the previous
span's end; the last span ends exactly at EOF (`0x1d6fc`). This was checked for
all 305 offset-bearing fields in all three samples.

| Type | Record value | Tail layout | Status |
| --- | --- | --- | --- |
| Bool | `0`/`1` | none | byte-verified |
| Int | signed 32-bit | none | byte-verified |
| Float | binary32 | none | byte-verified |
| Enum | u32 member hash | none | byte-verified; labels Murmur3-verified |
| UInt | u32 | none | byte-verified |
| Int64 | absolute offset | signed 64-bit | byte-verified by pointer/span |
| UInt64 | absolute offset | unsigned 64-bit | byte-verified by pointer/span |
| Vector3 | absolute offset | `x,y,z` binary32 (12 B) | byte-verified by span |
| String32 | absolute offset | 32-byte NUL-padded UTF-8 | byte-verified by span |
| String64 | absolute offset | 64-byte NUL-padded UTF-8 | byte-verified by span |
| String64Array | absolute offset | `u32 count`, then `count` × 64 B | byte-verified by span |
| Binary | absolute offset | `u32 length`, then `length` bytes | layout/span byte-verified; payload meaning **inferred** |
| BinaryArray | absolute offset | `u32 count`, then `count` × u32 | layout verified; semantics **inferred** |
| WString16Array | absolute offset | `u32 count`, then `count` × 32 B | layout verified; UTF-16LE interpretation **inferred** |

### Arrays

For every array type:

```
count = u32le(offset)
element i at offset + 4 + i*elementSize
```

The declared capacity comes from the BYML:

- `TotalSize` for BoolArray, IntArray, FloatArray, EnumArray, String64Array,
  UIntArray, UInt64Array, WString16Array.
- `ArraySize` for BinaryArray.
- `OriginalSize` is the initial/minimum length and can be smaller; for example
  an IntArray has `OriginalSize: 1` and `TotalSize: 256`, and the file stores
  `count = 256`.

All 236 array fields had `count == TotalSize`/`ArraySize` in all three samples.
The JSON's `arrayLen` is that declared capacity.

Element sizes:

| Type | Element size | Notes |
| --- | ---: | --- |
| BoolArray | 8-byte tail record | `u32 count` + one `u32` bit mask. Counts observed are 5–10, so the mask fits one word; multi-word behavior is **unverified**. |
| IntArray | 4 | signed 32-bit |
| FloatArray | 4 | binary32 |
| EnumArray | 4 | member hash |
| String64Array | 64 | NUL-padded UTF-8 |
| BinaryArray | 4 | values are u32; they are not length-prefixed blobs. Element meaning **inferred**. |
| UIntArray | 4 | unsigned 32-bit |
| UInt64Array | 8 | unsigned 64-bit |
| WString16Array | 32 | 16 UTF-16 code units; the samples are all zero bytes, so the encoding is **inferred**. |

`Binary` is a single length-prefixed blob. `BinaryArray` is **not** an array of
such blobs: its span arithmetic is `4 + 4*count`, and the samples contain ten
u32 zeros per field. Do not treat those words as pointers without evidence.
The first `Binary` is 404 bytes in the three scrubbed samples (`u32 400` plus
400 bytes); a report that the first span is variable in real played saves
(length word 2,088–2,496) has not been re-measured here and stays
**inferred/open**, listed in §10.

## 6. Reconstruction formulas

Given a buffer `b`:

```
isContainer(b) = len(b) >= 40 && b[0..4] == 04 03 02 01
revision       = u32le(b, 4)
tail           = u32le(b, 8)
records        = (tail - 40) / 8          // must divide exactly

key(i)         = u32le(b, 40 + 8*i)
value(i)       = u32le(b, 44 + 8*i)
dataOffset(i)  = 44 + 8*i                  // the value word itself

fieldOffset(i) = value(i)                   // for offset types
arrayCount(i)  = u32le(b, fieldOffset(i))
arrayItem(i,j) = fieldOffset(i) + 4 + j*elementSize
```

The header's `dataOffset` is not derived from the record count: it is stored.
`tail = 40 + 8*11958 = 95,704` for the verified progress file.

## 7. Integrity and checksum

No checksum was found. A probe over all three progress and all three caption
samples tested:

- the classic OoT `u16` byte-sum in a 0x2000-byte block header;
- CRC32, Adler32, FNV-1a-32, byte-sum, and 32-bit word-sum over the whole file,
  header+table, table, and tail;
- every stored u32 against those digests;
- every stored u32 against CRC32 of the bytes preceding it.

Result: no candidate reproduced a stored value. The progress footer's
`120564` is file size − 8; the caption footer's value is `0`. Neither is
explained by the probes. Treat both as opaque and preserve them.

## 8. Version gate

The revision is at header `0x04` and in the schema asset. The loader exposes:

```dart
schema.validateRevision(headerRevision); // throws SchemaRevisionMismatch
```

For revision `2982123` the schema is authoritative. For any other revision:

- do not guess field meanings from this schema;
- do not rewrite the header to make it match;
- open read-only and report the mismatch.

The schema JSON is gated independently (`schemaRevision` and
`schemaRevisionHex`); a mismatch between the two is a corrupt asset.

## 9. Unknown-byte preservation

The editor must be byte-preserving by default. The safe rules are:

1. **Never reorder, insert, or delete records.** A field's identity is its
   hash, but its position is part of the file. Patch only the 4-byte value word
   of the field you intend to change.
2. **Never change the header** except a deliberate, researched operation. In
   particular, bytes `0x0c–0x27` are zero in every sample and must stay zero.
3. **Preserve sentinels and the footer verbatim.** They are not editable
   fields; `{0, 0}` or a changed footer value is likely corruption.
4. **For inline scalars**, write little-endian bytes in place.
5. **For fixed-size strings**, write within the 32/64-byte span, keep a NUL
   terminator, and preserve bytes after the first NUL unless the user asks to
   clear them.
6. **For arrays**, keep the stored `count` at its declared capacity. Edit
   existing elements only. Do not append or shrink the tail unless the whole
   tail, every pointer, and the header data offset are rebuilt together.
7. **For `Binary`**, changing the length requires rebuilding the tail and all
   subsequent absolute pointers. This is out of scope for a field edit.
8. **Preserve unknown fields and unknown tail bytes.** The schema says which
   hashes exist; it does not say that every byte is understood.
9. **No checksum to fix.** Do not invent one.

## 10. What is verified vs inferred

Byte-verified:

- 40-byte header, magic, revision, data offset, reserved zeros;
- 8-byte record shape and 11,958 records;
- 32 sentinel records and 20 section counts;
- 11,925 field hashes and their raw record positions;
- all 236 array counts;
- scalar widths and every offset type's span;
- 2,499 enum-member hashes (75 unique tables, 1,257 unique members);
- the tail is contiguous and ends at EOF.

Inferred / unresolved:

- field **names** for 8,317 fields (hash-only in the JSON);
- BoolArray bit masks wider than one u32 (none observed);
- the meaning of the bytes inside `Binary` payloads (the span is verified, the
  contents are not);
- BinaryArray element meaning;
- WString16Array UTF-16LE interpretation (samples are zero);
- the first `Binary` span's length in real played saves (a report puts it at
  2,088–2,496 bytes, not the 404 bytes the samples show; not re-measured here);
- the footer's meaning;
- `SaveFileIndex` 1/2/3 field layouts beyond the BYML mapping;
- whether a future revision reorders the record table.

## 11. Regenerating the schema

```
dart run tool/gen_schema.dart /path/to/GameDataList.Product.110.byml > /tmp/gamedata.json
sha256sum assets/schema/gamedata_110.json /tmp/gamedata.json
```

The tool embeds the verified record-key order from the three samples so it can
emit exact `recordIndex` values without reading a save. It never copies a save
or a BYML into the repository.
