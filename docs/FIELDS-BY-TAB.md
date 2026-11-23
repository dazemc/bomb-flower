# Bomb Flower — fields by editor tab

This describes the generated field catalogue in `assets/fields/groups.json`,
produced from the hash-verified schema `assets/schema/gamedata_110.json` by
`tool/gen_field_groups.dart`, and what v1 actually surfaces. Player/World,
Inventory, Equipment and Resources edit verified save fields; Overview is a
read-only summary; Progression, Dungeons, Collectibles and Flags are
**read-only gap panels** that report the verified counts; Advanced Data is the
raw hex view behind its unlock gate; Settings edits application preferences, not
save fields.

The generator derives every membership from the schema's real `name` values. It
does not type hashes by hand and never invents a label. A group member is always
an on-disk field whose name, type, section, and record position the schema
verified.

## The honest count

Of the **11,925** fields serialized in `progress.sav`:

- **3,608** have a recovered, Murmur3-verified name.
- **8,317** have `"name": null`. They are reachable only through the
  **Advanced Data** hex view, by hash. No tab may fabricate labels for them.
- **1,220** additional declarations have `SaveFileIndex -1`; they are runtime-only
  and are **not in `progress.sav`**.
- **11,657** `Bool64bitKey` declarations are absent from disk entirely.

The flags gap panel therefore reports **10,212** Bool fields: **3,443 named** and
**6,769 hash-only**. Advanced Data accounts for all **8,317** unnamed fields,
including the 6,769 Bools, and lists the **7** opaque binary/wide-string hashes.

The schema has no `MaxRupee`, wallet level, Gold Skulltula total, medallion mask,
numeric equipment ids, per-item ammo counts, saved spawn/entrance scalar, or
saved camera scalar. Absence of a name is not proof that a concept is absent
from the save; it means no hash could be identified.

## Tab summary

Counts are distinct named fields, except flags/advanced where the hash-only count
is shown. "Memberships" can exceed distinct fields when a field appears in more
than one group on the same tab.

| Tab id | Groups | Named | Hash-only | Provenance mix | v1 surface |
| --- | ---: | ---: | ---: | --- | --- |
| `overview` | 1 | 10 | 0 | observed | read-only (summary) |
| `playerWorld` | 3 | 13 | 0 | observed, inferred | editable |
| `inventory` | 4 | 71 | 0 | verified, inferred | editable |
| `equipment` | 3 | 24 | 0 | verified, inferred | editable |
| `resources` | 5 | 19 | 0 | verified, inferred | editable |
| `progression` | 8 | 297 | 0 | observed, inferred | read-only (gap panel) |
| `dungeons` | 7 | 42 | 0 | inferred | read-only (gap panel) |
| `collectibles` | 6 | 159 | 0 | inferred | read-only (gap panel) |
| `flags` | 1 | 3,443 | 6,769 | observed | read-only (gap panel) |
| `advanced` | 1 | 0 | 8,317 | inferred | read-only (hex; unlock gate) |
| `settings` | 1 | 0 | 0 | verified | no save fields |

Provenance means:

- `observed` — the decoded value differs across `kokiri-start`, `castle-gate`,
  and `market-entrance`. This is extra evidence, not a name source.
- `verified` — the name is backed by host code or the BYML struct table, and the
  schema verified name, type, and record position.
- `inferred` — the name preimage is hash-verified, but the semantic meaning is
  inferred from the name pattern only; it is not confirmed by host code or the
  struct table.

A group carries the strongest evidence any member supports. Each `FieldRef` in
`groups.json` carries its own more precise `provenance` value. A group can be
`observed` while some members are only `inferred`; do not present the group tag
to the user as a per-field guarantee.

## Grouping rules

These are the generator's documented rules. The order of tabs is the
`EditorTabGroup` enum order; field lists are sorted by name.

- Exact-name groups: the generator looks the name up with
  `GameDataSchema.byNameOnDisk` and fails if the name is absent or runtime-only.
- Prefix/pattern groups: a field is included when its non-null name matches one
  documented regular expression and matches no documented exclusion.
- All groups exclude `name: null`, `presentOnDisk: false`, and `SaveFileIndex`
  other than `0`.
- `playerWorld`: exact `Player_*`, `Sequence_*`, `DungeonRoom`, UI map markers,
  and `WarpPoint_*` names listed in the tab.
- `inventory`:
  - `^IsGet\.(Item_|Weapon_|Armor_|Pouch_)` (47)
  - `^PouchData\.` plus `PlayerStatus.AssignableItem.Adult|Child` (3)
  - `^PlayerStatus\.AssignableItem\.BottleInfo\..*\.(BottleItem|IsValid)$` (10)
  - `(Quiver|BulletBag|BombBag|DekuNutsPouch|DekuStickPouch|ScrubBusinessSeed|GoldScale|ShilverScale)`
    excluding `^IsGet\.` and `^ActionGuide_IsEnd\.`, plus `Get_MagicBeans` and
    `PlayerStatus.WeaponSwordGiantLife` (11)
- `equipment`: `^PlayerStatus\.(Equip|AnotherEraEquip)`,
  `^IsGet\.(Weapon_|Armor_)`, and four exact state names.
- `resources`: exact health/magic/rupee/count names, plus
  `(Quiver|BulletBag|BombBag|GoldScale|ShilverScale)` excluding `^IsGet\.` and
  `^ActionGuide_IsEnd\.`.
- `progression`: `^HavePlayedEvent\.`, `^Get_`, `^IsGet\.`,
  `^(AllSage_|SageOf|Step_SageOf|Meet_GreatFairy)`,
  `(StoneOfForest|StoneOfFire|StoneOfWater|DoorOfTime_GetStoneCount)`,
  `^DoorOfTime_`, and
  `(Dm_MelodyGet_|IsGet\.Item_Melody_|^Item_Melody_|HavePlayedGetEvent\.Item_Melody_)`.
  The medallion rule `(?i)medallion` matches zero names and is represented as an
  empty placeholder group.
- `dungeons`: one group is derived programmatically per captured
  `^DungeonInfo\.([^.]+)\.` name. Other groups match
  `(SmallKey|_Get_SmallKey)`, `(DefeatBoss|BossOut)`,
  `(GetDungeonMap|_GetMap$|IsGetMap$|_Mapicon$|MapIcon_Flag$)` (excluding
  `^DungeonInfo\.` and `^MiniGame`), and `_Heart_Container_Obtained`.
- `collectibles`: `(GatheringTokenGold|HaveEncountered_Token|TokenCounterAppeared|Item_Token_Gold)`,
  `(HeartPiece|Heart_Piece)`, `MagicBean`,
  `(BigPoe|Bottle_Poe|GuidePoe_|IsRespawnAtGuidePoeRuins)`, `Fishing`, and
  `(BestScore|NewScore|BestTime|RecordFish|RecordWithSinkingLure|OnceUpdateRecord|IsNewRecord)`.
- `flags`: every `Bool` with a name, plus a count of every unnamed `Bool`.
  Bucket prefix is the first `.` segment, else the first `_` segment, else
  `(other)`.
- `advanced`: counts of all unnamed fields by `SaveType`, plus every on-disk
  `Binary`, `BinaryArray`, or `WString16Array` hash with no name.
- `settings`: empty by design.

## Overview

**Read-only (10).** `PlayerStatus.Life`, `MaxLife`, `MP`, `MPMax`,
`CurrentRupee`; `Sequence_CurrentBanc`, `Sequence_IsChildhood`;
`AllSage_AwakeSageCount`, `DoorOfTime_GetStoneCount`, `Get_MagicBeans`.

v1's Overview is a read-only summary over this catalogue; it never edits a
field. The same fields are edited in Resources and Player & World where those
tabs expose them, not here.

Life and MaxLife are **quarter-hearts**: default 12 = three hearts. Do not
silently convert to whole hearts. There is no stored rupee maximum.

**Read-only / not available.** `Sequence_IsLoadingBanc`,
`PlayerStatus.CurrentPos`, and `PlayerStatus.CurrentDir` are runtime-only
(`SaveFileIndex -1`) and are not in `progress.sav`. No wallet-capacity or
medallion-count scalar exists.

## Player & World

**Editable (13).**

- Position/rotation: `Player_Pos_For_Map` (Vector3), `Player_Rot_For_Map`
  (Float). Both were observed to differ across the three samples.
- Scene/age/room: `Sequence_CurrentBanc` (String64), `Sequence_IsChildhood`
  (Bool), `DungeonRoom` (Int).
- Map markers: `UI_FieldMapPlayerAreaNo`, `UI_DungeonMapPlayerAreaNo`,
  `IsSettingMapPlayerIconAnchor`, `MapIconDeactivateByAreaActor`,
  `WarpPoint_DreamWorld.Pos`, `WarpPoint_DreamWorld.LocationName`,
  `WarpPoint_FaroreWind.Pos`, `WarpPoint_FaroreWind.LocationName`.

`Sequence_CurrentBanc` is a map/banc string; validate it against
`assets/world/scenes.json` where possible instead of offering free text.

**Read-only / unavailable.** No dedicated saved spawn, start, or entrance
scalar has a verified name. No saved camera scalar has a verified name.
`PlayerStatus.CurrentPos`, `PlayerStatus.CurrentDir`, and
`Sequence_IsLoadingBanc` are runtime-only and must not be presented as disk
fields.

## Inventory

**Editable (71 distinct).**

- Acquisition (47): every verified
  `IsGet.Item_*`, `IsGet.Weapon_*`, `IsGet.Armor_*`, and `IsGet.Pouch_*` flag.
  These are acquisition booleans, not counts.
- Pouch (3): `PouchData.Item_Token_Gold.StockNum`,
  `PlayerStatus.AssignableItem.Adult`, `.Child`.
- Bottles (10): all five `BottleA`–`BottleE` `BottleItem` enums and all five
  `IsValid` flags. The shared enum table has 13 members: `Empty`, `RedPotion`,
  `GreenPotion`, `BluePotion`, `BlueFire`, `Fish`, `Letter`, `BigPoe`, `Poe`,
  `Bug`, `Fairy`, `MaxMilk`, `HalfMilk`.
- Ammo/capacity and counts (11): quiver, bullet-bag, bomb-bag, Deku-nut/stick
  pouch, Scrub-business-seed, Gold Scale, and Silver Scale acquisition flags;
  `Get_MagicBeans`; `PlayerStatus.WeaponSwordGiantLife`.

**Read-only / unavailable.** Only three stock/count values are named: gold
tokens, magic beans, and giant-sword life. There is no verified per-item stock
table, no arrow count, no bomb count, no Deku-stick/nut count, and no wallet
capacity. Pouch contents other than bottles have no verified names.

Names containing the word `Item` that are **not** inventory state are
intentionally excluded from this tab: the non-`IsGet` `Item_Melody_*` and
`HavePlayedGetEvent.Item_Melody_*` fields are song/cutscene flags in
Progression, and the `Market_*` / `Npc_*` `Item_Bottle_TutorialEvent` fields are
shop/tutorial events. They match the word pattern but would mislead a user
looking for an item count. The `IsGet.Item_Melody_*` rows remain in acquisition
because they are genuine `IsGet` acquisition flags (and also appear in
Progression's `IsGet` view).

## Equipment

**Editable (24).**

- Slots (9): `PlayerStatus.EquipWeapon`, `EquipShield`, `EquipHeadArmor`,
  `EquipArmor`, `EquipBoot`, `EquipOcarina`, `EquipHandArmor`,
  `AnotherEraEquipWeapon`, `AnotherEraEquipShield`.
- Acquisition (11): `IsGet.Weapon_*` and `IsGet.Armor_*`.
- State (4): `PlayerStatus.IsActiveHeadArmor`, `IsEquipAgonyStone`,
  `IsDefenseUP`, `WeaponSwordGiantLife`.

**Read-only / unavailable.** Slots are `String64` asset/identifier text, not
numeric item ids. There is no equipment enum and no verified gauntlet field.
`PlayerStatus.IsActiveGlassTruth` is runtime-only (`SaveFileIndex -1`) and is
excluded.

## Resources

**Editable (19).**

- Health (3): `Life`, `MaxLife`, `IsGet.Item_FairyBless_DefenseDouble`.
- Magic (4): `MP`, `MPMax`, `IsGet.Item_FairyBless_MP`, `..._MPDouble`.
- Rupees (1): `CurrentRupee`.
- Counts (4): `Get_MagicBeans`, `PouchData.Item_Token_Gold.StockNum`,
  `PlayerStatus.WeaponSwordGiantLife`,
  `DreamBossStage_WeaponSwordGiantLife`.
- Capacity upgrades (7): quiver, bullet-bag, bomb-bag, and scale flags outside
  the `IsGet.*` namespace.

**Read-only / unavailable.** No `MaxRupee`, wallet level, or rupee-capacity
field exists. Do not clamp `CurrentRupee` to an invented maximum.
`NaviChat_MaxRupee_Displayed` is a UI-message flag, and
`HappyMaskSaleMan_..._FullWallet` is an event flag; neither stores capacity.
There are no arrow/bomb/ammo count fields.

## Progression

**Read-only (297 distinct; 335 group memberships).** These fields are not
editable from the Progression tab in v1; the tab is a gap panel with the
verified count; the only raw path is Advanced Data's hex view (behind its unlock
gate), and this tab offers no editor.

- `HavePlayedEvent.*` (164)
- `Get_*` (19)
- `IsGet.*` (47)
- `AllSage_*`, `SageOf*`, `Step_SageOf*`, `Meet_GreatFairy*` (30)
- Stone-quest flags and `DoorOfTime_GetStoneCount` (51)
- `DoorOfTime_*` (3)
- Melody/song flags (21)
- Medallions (0)

Memberships exceed distinct fields because the stone, melody, and `IsGet`
views overlap the event/get groups. A future editor must de-duplicate by hash
if it combines groups.

**Read-only / unavailable.** There is no medallion bitmask and no single
songs-learned mask. The six `HavePlayedEvent.Dm_MelodyGet_*` fields are the
clearest individual song flags. Stone progress is spread across flags and
dialogue flags. The 164 event flags mix true progression with room, cutscene,
and hint state; do not label the whole group "quests complete".

## Dungeons

**Read-only (42 distinct).** These fields are not editable from the Dungeons
tab in v1; the tab is a gap panel with the verified count; the only raw path is
Advanced Data's hex view (behind its unlock gate), and this tab offers no
editor.

- Named `DungeonInfo.*` item flags (5), grouped per dungeon:
  - `DodongoCavern` (1): compass
  - `FireTemple` (3): map, compass, boss key
  - `WaterTemple` (1): compass
- Small keys (25): every verified `*_GetSmallKey` / `*_Get_SmallKey` flag,
  including the four Gerudo Fortress keys.
- Boss flags (5): `DefeatBoss` / `BossOut` flags.
- Map items (6): verified map/map-icon flags outside `DungeonInfo`.
- Heart containers (1): `InsideTheDekuTree_Heart_Container_Obtained`.

**Read-only / unavailable.** Only three dungeons have named `DungeonInfo.*`
item flags in this revision. `DungeonInfo.*.BossRetryNum` declarations are
runtime-only (`SaveFileIndex -1`) and are not in `progress.sav`. Small keys are
per-room flags, not one inventory count. Only one heart-container flag is named;
do not infer the rest.

## Collectibles

**Read-only (159 distinct; 166 group memberships).** These fields are not
editable from the Collectibles tab in v1; the tab is a gap panel with the
verified count; the only raw path is Advanced Data's hex view (behind its unlock
gate), and this tab offers no editor.

- Gold Skulltula/token fields (20): the stock counter plus
  `GatheringTokenGold*`, `HaveEncountered_Token`, and token-counter flags.
- Heart pieces (10): `HeartPiece` / `Heart_Piece` flags. Boss heart containers
  are in Dungeons.
- Magic beans (17): `Get_MagicBeans` plus soil and hint flags.
- Poes (20): Big Poe defeats, Guide Poe progress, and Poe bottle flags.
- Fishing (70): every verified `Fishing` field, including tutorials, weather,
  and pond state.
- Scores/best times (29): hit-target scores, horse-race and Dampe times,
  running-race times, fishing records, and new-record flags.

**Read-only / unavailable.** There is no Gold Skulltula total-count field; the
closest stored count is `PouchData.Item_Token_Gold.StockNum`. There is no Big
Poe count field; the ten Hyrule Field defeats are individual flags. There is no
aggregate heart-piece count. Fishing and score rows overlap; group counts are
memberships, not a partition.

## Flags

**Read-only (3,443 named Bool fields).** These fields are not editable from
the Flags tab in v1; the tab is a gap panel with the verified count; the only
raw path is Advanced Data's hex view (behind its unlock gate), and this tab
offers no editor.

The gap panel reports **178 named prefix buckets** plus a hash-only bucket. The
largest prefixes are `HavePlayedNaviBalloonMessage` (512), `HaveTalked_Special`
(402), `HavePlayedEvent` (165), `Npc` (163), `MiniGame` (147), and
`InsideJabuJabuBelly` (107). Use `flagBuckets`, `flagBucket(prefix)`, and
`flagFieldsUnder(prefix)` in `FieldGroupsCatalogue`; do not render all 10,212
rows inline.

**Read-only / raw-only (6,769 hash-only Bools).** These have no name and are
reachable only by hash in Advanced/raw. The `flags.unnamedBool` bucket carries
their count. `BoolArray` is a separate wire type: six fields total, one named
(`MiniGame_CatchCucco_PutsInFence`) and five hash-only; they are counted in
Advanced, not in the Bool bucket.

## Advanced

**Read-only hex (0 named).** The Advanced Data tab is the raw hex view.
Inspection is read-only until the explicit **Unlock editing** toggle is on;
even then each write is mediated through the engine and confined to named,
editable field spans, and a byte outside them is restored. The four gap-panel
field sets are inspectable here as raw bytes.

**Read-only / raw-only (8,317 hash-only).** Counts by wire type:

| Type | Unnamed |
| --- | ---: |
| Bool | 6,769 |
| Int | 1,033 |
| IntArray | 155 |
| Enum | 88 |
| UInt | 83 |
| Float | 61 |
| UIntArray | 33 |
| Int64 | 28 |
| String64 | 17 |
| EnumArray | 14 |
| Vector3 | 8 |
| BoolArray | 5 |
| UInt64 | 5 |
| UInt64Array | 4 |
| Binary | 3 |
| FloatArray | 3 |
| String64Array | 3 |
| BinaryArray | 2 |
| WString16Array | 2 |
| String32 | 1 |

**Opaque hashes (7).** These are presented by hash only:

| Hash | Type | Record |
| --- | --- | ---: |
| `0x1ca26dd7` | Binary | 11781 |
| `0x3339df55` | Binary | 11780 |
| `0x70d7c5cb` | Binary | 11779 |
| `0xbbf85fd5` | BinaryArray | 11783 |
| `0xc180adf7` | BinaryArray | 11784 |
| `0x61312875` | WString16Array | 11951 |
| `0xd2ddb868` | WString16Array | 11950 |

Changing a `Binary` length requires rebuilding the tail and every subsequent
absolute pointer; that is out of scope for a curated field edit. `BinaryArray`
element meaning and `WString16Array` UTF-16LE interpretation are unverified.

## Settings

**Editable in `progress.sav`: none.** This tab edits application preferences.
The schema contains `OptionData.*` enum tables but no `OptionData` field records;
`option.sav` is declared in the container map, but its fields were not extracted.
There is no save-field group to render, and the UI must not invent settings keys.
