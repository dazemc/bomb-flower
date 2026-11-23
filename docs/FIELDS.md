# Bomb Flower — editor-relevant fields

This is a human index into `assets/schema/gamedata_110.json`. It lists the
fields whose meaning is strongly supported by a verified name, the BYML's
struct defaults, or the Longshot host code. It is not a complete field list:
8,317 of the 11,925 on-disk fields have no recovered name and are emitted with
`"name": null` (see `docs/SAVE-FORMAT.md` §1).

Column meanings:

- **Hash** — `Murmur3_x86_32(full name, seed 0)`, the on-disk record key.
- **Type / section** — from the BYML; section is the sentinel id.
- **Default** — the BYML default, not a value read from a sample.
- **Source** — how the name was identified:
  - `host` — a named constant in `host/oot_state_tap.c`;
  - `struct` — a member of the BYML `Struct` default table, with both the
    member-name hash and the full-field hash checked;
  - `string` — a readable name in the game's string corpus, accepted only when
    its Murmur3 equals the field hash.

`sf=0` means `progress.sav`; `sf=-1` means declared at runtime and **not
serialized**; `sf=2` means `caption.sav`. Only `sf=0` rows are editable in
`progress.sav`.

## Player status and resources

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | ---: | --- |
| `PlayerStatus.Life` | `0x31AB5580` | Int / 3 | 12 | host |
| `PlayerStatus.MaxLife` | `0xFBE01DA1` | Int / 3 | 12 | host |
| `PlayerStatus.MP` | `0x76B18200` | Int / 3 | 0 | struct |
| `PlayerStatus.MPMax` | `0x12D63A97` | Int / 3 | 0 | struct |
| `PlayerStatus.CurrentRupee` | `0xA77921D7` | Int / 3 | 0 | host |
| `PlayerStatus.DiveDepth` | `0x61466C21` | Float / 5 | 3.0 | struct |
| `PlayerStatus.NayruLoveTime` | `0x4B60E31D` | Float / 5 | 0.0 | struct |
| `PlayerStatus.IsDefenseUP` | `0x56BBE07C` | Bool / 1 | false | struct |
| `PlayerStatus.IsEquipAgonyStone` | `0x58BDA396` | Bool / 1 | false | struct |
| `PlayerStatus.WeaponSwordGiantLife` | `0xBDF672C2` | Int / 3 | 8 | struct |

`PlayerStatus.Life` and `MaxLife` are quarter hearts in the host bridge
(`host/oot_state_tap.c` says “life/max_life in quarter hearts”), so the default
12 is three hearts. The editor must not silently convert to whole hearts.

No `PlayerStatus.MaxRupee`, wallet level, or rupee-capacity field was found.
`PlayerStatus.CurrentRupee` is the stored rupee count; do not clamp it to an
invented maximum.

## Position and rotation

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `Player_Pos_For_Map` | `0x960AD56A` | Vector3 / 11 | (0, 0, 0) | prefix |
| `Player_Rot_For_Map` | `0xA4AEE8CD` | Float / 5 | 0.0 | host |

These are the saved map position and facing used by the host bridge. They are
the fields an editor should use.

The following similarly named fields are **runtime-only** and are not in
`progress.sav`:

| Field | Hash | Type / section | Saved? |
| --- | --- | --- | --- |
| `PlayerStatus.CurrentPos` | `0x307D7D97` | Vector3 / 11 | no (`sf=-1`) |
| `PlayerStatus.CurrentDir` | `0xE052AF3C` | Vector3 / 11 | no (`sf=-1`) |
| `Npc_TimeSignal.Hour` | `0x20DE11CA` | Int / 3 | no (`sf=-1`) |
| `Npc_TimeSignal.Minute` | `0xB704A9B1` | Int / 3 | no (`sf=-1`) |

They are present in `declaredNotSaved` so `byHash` can resolve them, but a save
editor must not present them as disk fields.

## Equipment

The seven equipment slots are `String64`, not numeric item ids. A string is
empty by default; the editor should treat the contents as asset/identifier text
and preserve trailing bytes.

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `PlayerStatus.EquipWeapon` | `0xA95A3521` | String64 / 17 | `""` | struct |
| `PlayerStatus.EquipShield` | `0xEE463235` | String64 / 17 | `""` | struct |
| `PlayerStatus.EquipHeadArmor` | `0x59D9C7B3` | String64 / 17 | `""` | struct |
| `PlayerStatus.EquipArmor` | `0x008D7F0C` | String64 / 17 | `""` | struct |
| `PlayerStatus.EquipBoot` | `0xD107A85D` | String64 / 17 | `""` | struct |
| `PlayerStatus.EquipOcarina` | `0xB72CD3FC` | String64 / 17 | `""` | struct |
| `PlayerStatus.EquipHandArmor` | `0x7CE1CB81` | String64 / 17 | `""` | struct |
| `PlayerStatus.AnotherEraEquipWeapon` | `0xA1F7EE2B` | String64 / 17 | `""` | struct |
| `PlayerStatus.AnotherEraEquipShield` | `0x2342B619` | String64 / 17 | `""` | struct |
| `PlayerStatus.IsActiveHeadArmor` | `0xC27C80FB` | Bool / 1 | false | struct |
| `PlayerStatus.IsActiveGlassTruth` | `0x0187AAA2` | Bool / 1 | false | **runtime-only** |

## Bottles

Each bottle has a 13-member enum table and an `IsValid` flag. The table is
shared by all five bottles; `Empty` has hash `3194609225`.

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `PlayerStatus.AssignableItem.BottleInfo.BottleA.BottleItem` | `0x7D48DF76` | Enum / 7 | Empty | struct |
| `…BottleB.BottleItem` | `0x1EDD164A` | Enum / 7 | Empty | struct |
| `…BottleC.BottleItem` | `0xB80C70A8` | Enum / 7 | Empty | struct |
| `…BottleD.BottleItem` | `0xE4C1B1FC` | Enum / 7 | Empty | struct |
| `…BottleE.BottleItem` | `0x365E1953` | Enum / 7 | Empty | struct |
| `…BottleA.IsValid` | `0xF39CE410` | Bool / 1 | false | struct |

Enum labels (source order): `Empty`, `RedPotion`, `GreenPotion`,
`BluePotion`, `BlueFire`, `Fish`, `Letter`, `BigPoe`, `Poe`, `Bug`, `Fairy`,
`MaxMilk`, `HalfMilk`. The JSON contains every member hash.

## Progression: stones, sages, beans, minigames

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | ---: | --- |
| `AllSage_AwakeSageCount` | `0xBF5F1321` | Int / 3 | 5 | string |
| `AllSage_MeetSheikCount` | `0xC96DDD27` | Int / 3 | 0 | string |
| `DoorOfTime_GetStoneCount` | `0x9B63BC70` | Int / 3 | 2 | string |
| `Get_MagicBeans` | `0x2E6921C4` | Int / 3 | 0 | string |
| `MiniGame_Fishing_RecordFishSize_Adult` | `0xE1420C94` | Int / 3 | 45 | string |
| `MiniGame_Fishing_RecordFishSize_Child` | `0x88C51151` | Int / 3 | 40 | string |
| `MiniGame_HorseRace_BestTime` | `0x084655F8` | Float / 5 | 0.0 | string |

The sacred-stone and sage quests are otherwise encoded as many named `Bool`
flags such as `ForestTemple_SageOfForest_*`, `Get_StoneOfWater_*`, and
`HavePlayedEvent.Dm_MelodyGet_*`. There is no single “medallion bitmask” field
with a verified name; do not invent one.

## Dungeon items and keys

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `DungeonInfo.FireTemple.IsGetBossKey` | `0xB72D73DF` | Bool / 1 | false | string |
| `DungeonInfo.FireTemple.IsGetMap` | `0x5B3AC0BA` | Bool / 1 | false | string |
| `DungeonInfo.FireTemple.IsGetCompass` | `0x0AA068B6` | Bool / 1 | false | string |
| `FireTemple_GetSmallKey_01` | `0x57771BBD` | Bool / 1 | false | string |

Only five `DungeonInfo.*` item flags have verified names in this revision
(Dodongo Cavern compass; Fire Temple map/compass/boss key; Water Temple
compass). Small keys are per-room `*_GetSmallKey_*` flags, not a single
inventory count. `DungeonInfo.*.BossRetryNum` fields are declared with
`SaveFileIndex -1` (runtime-only) and are not in `progress.sav`.

## Songs and ocarina

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `Sequence_CurrentBanc` | `0x1D6189DA` | String64 / 17 | `""` | host |
| `Sequence_IsChildhood` | `0xCEA220D3` | Bool / 1 | true | host |
| `Sequence_IsLoadingBanc` | `0xEF2B60C2` | Bool / 1 | false | **runtime-only** |
| `HavePlayedEvent.Dm_MelodyGet_Saria` | `0x35307FEB` | Bool / 1 | false | string |
| `HavePlayedEvent.Dm_MelodyGet_Fire` | `0x00A58FEE` | Bool / 1 | false | string |
| `HavePlayedEvent.Dm_MelodyGet_Epona` | `0xDB8433F7` | Bool / 1 | false | string |
| `HavePlayedEvent.Dm_MelodyGet_Storm` | `0x9E1EFBA1` | Bool / 1 | false | string |
| `HavePlayedEvent.Dm_MelodyGet_Zelda` | `0x2CD669E8` | Bool / 1 | false | string |
| `HavePlayedEvent.Dm_MelodyGet_Spilit` | `0xA7BB21FB` | Bool / 1 | false | string |
| `ActionGuide_IsEnd.OcarinaSongEstimate` | `0xC0F73567` | Bool / 1 | false | struct |

There is no single “songs learned” bitmask with a verified name. The six
`Dm_MelodyGet_*` flags above are the clearest song-progress fields; treat them
as individual flags. `Spilit` is the source spelling of the Spirit melody.

## Collectibles and flags

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `HaveEncountered_Token` | `0x31A83410` | Bool / 1 | false | string |
| `GatheringTokenGold_FirstTalk` | `0x439D9D91` | Bool / 1 | false | string |
| `InsideTheDekuTree_Heart_Container_Obtained` | `0x98CA7AAB` | Bool / 1 | false | string |
| `Field_TunnelTooSmall_FirstDo` | `0x00480C86` | Bool / 1 | true | string |

Gold Skulltula progress is spread across `GatheringTokenGold_*`,
`*_GetReward*`, and `HaveTalked_Special.*` flags. There is **no field named**
`GoldSkull`, `GSFlag`, `Lens`, `Tunic`, `Medallion`, `KokiriEmerald`, or
`ZoraSapphire` in the verified name set. Absence of a name is not proof that a
concept is absent from the save; it means the hash-only field could not be
identified.

The three samples have 10,212 `Bool` fields. 3,443 of them have verified names
(the rest are hash-only). Named examples include `IsVisitLocation.*` (35),
`ActionGuide_IsEnd.*` (53), and `HavePlayedNaviBalloonMessage.*` (512).

## Time and dates

`Npc_TimeSignal.Hour` / `.Minute` / `.HourAMPM` are runtime-only (`sf=-1`).
The saved date is in `caption.sav` (`SaveFileIndex 2`), not `progress.sav`:

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `CaptionData.Date.Hour` | `0x23F3D75E` | Int / declared | 0 | struct |
| `CaptionData.Date.Minute` | `0x27853BF7` | Int / declared | 0 | struct |
| `CaptionData.Date.Second` | `0x5EE50BED` | Int / declared | 0 | struct |
| `CaptionData.Date.Day` | `0xBD46F485` | Int / declared | 0 | struct |

`CaptionData.Date` itself is a `Struct` with `SaveFileIndex -1`; its members
are `SaveFileIndex 2`. `caption.sav` has its own 79-record container and is
outside the current `progress.sav` field list.

## Save identity and host-demo fields

| Field | Hash | Type / section | Default | Source |
| --- | --- | --- | --- | --- |
| `Sequence_CurrentBanc` | `0x1D6189DA` | String64 / 17 | `""` | host |
| `Sequence_IsChildhood` | `0xCEA220D3` | Bool / 1 | true | host |
| `PlayerStatus.Life` | `0x31AB5580` | Int / 3 | 12 | host |
| `PlayerStatus.MaxLife` | `0xFBE01DA1` | Int / 3 | 12 | host |
| `PlayerStatus.CurrentRupee` | `0xA77921D7` | Int / 3 | 0 | host |
| `Player_Rot_For_Map` | `0xA4AEE8CD` | Float / 5 | 0.0 | host |

These seven names are the constants in `host/oot_state_tap.c` lines 35–41. The
schema's `byHash` resolves all seven, including the runtime-only
`Sequence_IsLoadingBanc`.

## How to look up a field

```dart
final schema = await GameDataSchema.load(() => readJson());
final life = schema.byNameOnDisk('PlayerStatus.Life');
final field = schema.byHashOnDisk(0x31AB5580);
final runtime = schema.byHash(0xEF2B60C2); // declaredNotSaved
```

Use `byNameOnDisk`/`byHashOnDisk` for edits; they never return runtime-only or
`Bool64bitKey` entries. Use `byHash` only when you explicitly want the wider
declaration set.

## What is still unidentified

- 8,317 of 11,925 on-disk fields (mostly `Bool` map state) have no name.
- 11,657 `Bool64bitKey` declarations are listed separately; they are not in
  `progress.sav` and have no recovered names.
- No verified names for wallet capacity, medallions, spiritual stones as a
  group, Gold Skulltula count, lens/tunic state, or a single song mask.
- `BinaryArray` element meaning and multi-word `BoolArray` masks are inferred
  or unobserved.
- The progress footer's value `120564` has no established meaning.

Do not manufacture a field for a concept that has no verified hash. The
`unresolved` block exists so the UI can say “hash-only field” honestly.
