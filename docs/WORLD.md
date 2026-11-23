# Verified world and actor catalogues

Bomb Flower ships two generated, deterministic JSON catalogues:

- `assets/world/scenes.json` — map, base-scene, start-position and dungeon
  identities.
- `assets/catalogue/actors.json` — the game strings and labels used by
  Longshot's inventory editor.

Both are factual metadata: names, keys, coordinates and source citations. They
contain no ROMs, `.byml`, `.romfs`, artwork, textures, save files or other game
binaries. Longshot remains read-only; generation only reads its C headers and
the validated scratch extraction.

## What is verified

| Fact | Count | Evidence |
|---|---:|---|
| Map identity strings (`Sequence_CurrentBanc`) | 80 | `GameBancInfo.Product.111.rstbl.byml.zs`, the 80 `GameBancParam/*.bgyml` folders, and `host/oot_area_names.c:1-8` |
| Base scene strings | 62 | derived by removing the `_Child`, `_Adult`, `_Alternative` and `_MQ` suffixes from the 80 maps |
| Named start positions | 415 | `Banc/BancBasedResource/StartPos.byml.zs`; 45 have an empty name and are the `(default)` entry |
| Pause-menu dungeon maps | 10 | the ten N64 dungeon maps, mapped to Longshot `Banc` folders; eight have a boss heart container (`host/oot_heart_containers.c:121-124`) |
| Scene/map pairs seen in sample saves | 3 | `kokiri-start`, `castle-gate`, `market-entrance` caption/progress saves |
| Inventory-editor actor/item rows | 86 | `gpu/vk/oot_cheat_items.h:1-110` |

The three observed identities are:

| Save | `caption.sav` scene @684 | `caption.sav` map @748 | `Sequence_CurrentBanc` |
|---|---|---|---|
| `kokiri-start` | `KokiriForest` | `KokiriForest/KokiriForest_Child` | `KokiriForest_Child` |
| `castle-gate` | `HyruleField` | `HyruleField/HyruleField_Child` | `HyruleField_Child` |
| `market-entrance` | `Market` | `Market/Market_Child` | `Market_Child` |

`host/control.c:1869-1898` reads the two caption strings; `host/oot_state_tap.c:35-36`
identifies `Sequence_CurrentBanc` as a `String64`. In all three saves, the map
path is exactly `scene + "/" + banc`.

## What is not verified

- **No numeric remake scene-id space.** The remake save stores strings. N64
  scene ids `0x00`–`0x64` are a separate, non-applicable glossary; do not write
  them into a Longshot save.
- **No verified remake pause-menu order.** `dungeonIndex` is catalogue order,
  following the ten N64 pause-menu dungeon maps as a display convention. It is
  not a claim about the remake's menu order.
- **Unknown strings are not validated by the game.** The layout parser accepts
  any printable string; whether the game accepts an unknown map is untested.
  The 77 maps not seen in a sample save are known from game data, not verified
  in a save.
- **Two dungeon maps have mini-bosses, not boss heart containers.** Bottom of
  the Well (`DeadHandStage`, Dead Hand) and Ice Cavern (`WolfosWhiteStage`,
  White Wolfos) are in the ten dungeon list, but `hasBossHeartContainer` is
  false. The other eight have a boss and a boss heart container.
- **Labels are editor labels.** Actor display names come from the first
  `OOT_ITEM` argument, not from the game's localized message files.
- **The N64 item table is not shipped.** `/tmp/opencode/catalogue/items/items.json`
  is N64-only (`applicable_to_longshot: false`) and is deliberately absent from
  app code and assets.

## Validation rules

`WorldCatalogue.validateMapPath(String)` implements the `RANGES.md` policy:

1. **known** — an exact one of the 80 map keys, an exact one of the 62 base
   scenes, or an exact `baseScene/mapKey` path such as
   `KokiriForest/KokiriForest_Child`.
2. **unknownWarn** — any other non-numeric string. The layout may accept it,
   but a UI must not present it as verified.
3. **rejectedNumericId** — a purely decimal id (`42`, `-1`) or a `0x`-prefixed
   hex id (`0x55`), because those are N64-style scene ids in a string field.

The 64-byte caption field width is enforced by the caption layout, not by this
membership check. `WorldCatalogue.search` is case- and diacritic-insensitive
over map keys and display names. `ActorCatalogue.withEquipment` accepts only an
exact, well-formed equipment string; `isValidEquipmentString` and
`isValidActorString` reject SQL fragments, punctuation and unknown names.

`MapEntry` intentionally has the product name. Import the library with a
prefix (`as world`) when `dart:core`'s `MapEntry` is also in scope.

## Citations

Longshot (read-only):

- `host/oot_area_names.c:1-8`, `:13-98`, `:100-126` — 80 English map labels,
  suffix stripping and fallback spelling.
- `host/control.c:1869-1898` — `caption.sav` scene at 684 and map at 748.
- `host/oot_state_tap.c:35-36` — `Sequence_CurrentBanc` as a `String64`.
- `host/oot_heart_containers.c:121-124` — the eight dungeons with a boss heart
  container.
- `gpu/vk/oot_cheat_items.h:1-110` — 86 `OOT_ITEM(label, pouch name, kind)`
  rows.
- `work/dump/romfs/RSDB/GameBancInfo.Product.111.rstbl.byml.zs` — the 80
  `GameBancInfo` row ids.
- `work/dump/romfs/Banc/GameBancParam/*.game__banc__GameBancParam.bgyml` — the
  80 map folder names.
- `work/dump/romfs/Banc/BancBasedResource/StartPos.byml.zs` — 415 start
  positions with `Trans` and `Rot`.
- `assets/saves/*/slot_00/{caption,progress}.sav` — the three observations.

Catalogue extraction:

- `/tmp/opencode/catalogue/scenes/scenes.longshot.json` — validated extraction
  (80 maps, 62 base scenes, 415 starts, 10 dungeons, 3 observations).
- `/tmp/opencode/catalogue/scenes/RANGES.md` — sections 1.3, 2, 3.1, 3.2 and 6:
  string identities, validation policy and the uncertainty list.

## Regeneration

From the repository root:

```sh
dart run tool/gen_catalogues.dart \
  --scenes /tmp/opencode/catalogue/scenes/scenes.longshot.json \
  --area-names /home/daze/GitHub/Longshot/host/oot_area_names.c \
  --cheat-items /home/daze/GitHub/Longshot/gpu/vk/oot_cheat_items.h \
  --heart-containers /home/daze/GitHub/Longshot/host/oot_heart_containers.c \
  --out assets
```

The generator rejects count drift, duplicate keys, unknown references,
display-name disagreement with `oot_area_names.c`, and a boss-dungeon set that
does not match the heart-container list. Output has sorted object keys and one
trailing newline, so two runs produce identical `sha256sum` output.
