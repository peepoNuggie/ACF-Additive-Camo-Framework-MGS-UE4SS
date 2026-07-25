# ACF — Additive Camo Framework (MGS Delta / UE4SS)

A UE4SS-based mod framework for **Metal Gear Solid Delta: Snake Eater** that lets modders **add** new camouflage/uniform/facepaint options as new content — like DLC — rather than replacing existing ones. The goal: a modeler packages their own mesh/texture as a `.pak`, and it shows up as a new, genuine, equippable option in the game's normal camo menu.

Status: **active reverse-engineering + framework development, not yet feature-complete.** See [Current status](#current-status) below before assuming anything here works end-to-end yet.

## Environment

- Game: MGS Delta (UE 5.3, Windows, Steam)
- UE4SS pinned to commit `c838a8ac` (required — other versions won't load against this game)
- Two mods, built from this repo:
  - **Lua mod** `ACF` — `ue4ss/Mods/ACF/scripts/main.lua` — console commands used for live testing/reverse-engineering and the save-unlock step
  - **C++ mod** `ACF-CPP` — built from `MyCPPMods/ACF/src/dllmain.cpp`, deployed as `ue4ss/Mods/ACF-CPP/dlls/main.dll`

## Build & deploy

```
cmake --build build --config CasePreserving__Debug__Win64 --target ACF
```

Then copy `build/MyCPPMods/ACF/CasePreserving__Debug__Win64/ACF.dll` to the game's `ue4ss/Mods/ACF-CPP/dlls/main.dll` (game must be fully closed first), then relaunch.

Build notes:
- CMake generator: `Visual Studio 18 2026` with `-T v143` toolset
- The pinned RE-UE4SS commit needed two small local patches to compile with current MSVC (`FNameEntryId`/`uint32_t` conversion fixes in `NameTypes.hpp` and `GUI/Dumpers.cpp`) — these are local-only and don't affect the shipped mod DLL

## Confirmed working game architecture

The chain from a camo's data identity to its rendered appearance, reverse-engineered via FModel + live UE4SS reflection:

1. **`ECamouflageType`** (enum, `/Script/MGS3`) — ~71 vanilla entries (e.g. `GM_CAMOUF_NORMAL`, `GM_CAMOUF_TIGER_STRIPE`)
2. **`EItemName`** (enum, `/Script/MGS3`) — the real "item identity" system; camos are actually items (e.g. `IT_EqNaked`, `IT_EqTigerStripe`)
3. **`DT_CamouflageCollection`** (DataTable, `/CobraUI/Data/Collection/Camouflage/DT_CamouflageCollection`) — 95 rows (includes facepaints/other equipment). Row fields include `CamouflageType`, `FacePaintType`, `ItemType`, `DescryptionText` (sic), `IsShowLockDescryptionText` (sic), `IsHiddenItem`, `IsAdditionalItem`, `IsMaskItem`
4. **`GsrCollectionItemController:ItemNameToItemId`** converts `EItemName` → **`EGsrItemId`** (`/Script/Gsr`)
5. **`BP_CamouflageCollectionSnake`** — the character actor holding per-body-part `SkeletalMeshComponent`s, a `GroupInfoComponent`, and a `GsrCollectionItemController`
6. **`UE4PairingCamouflageManager:UpdateCamouflageByNoPairing(facepaint, camo)`** — the confirmed real visual-apply function (found via the TAB-menu widget `sv_camouflage`)
7. **`DataAssetHelper`** (`/Script/MGS3`, reached via `UE4PairingCamouflageManager.DataAssetHelper`) — the real mesh/texture loader. **Confirmed via live A/B test**: it loads assets by searching for a name matching the pattern **`"Camouf_" + <camo ID>`** (and `"Facepaint_" + <facepaint ID>` for facepaints). Switching camo IDs live (`forcecamo 0 5`) visibly changed a cached entry's name from `Camouf_0` to `Camouf_5`. This is the actual missing piece for rendering a new camo's visuals — independent of the `DT_CamouflageCollection` table.
8. **`BPModLoaderMod`** (built into UE4SS) auto-mounts any `.pak`/`.utoc`/`.ucas` dropped in `Content/Paks/LogicMods/` — no custom mounting code needed

### Unlocking (separate from visual apply)

`UserProfileSaveGame` has `CamouflageList`/`FacePaintList` (`TArray<bool>`). Confirmed safe technique: single-item array append via plain Lua array syntax (`camoList[#camoList + 1] = true`). Do **not** bulk-iterate this array.

## Known UE4SS bug (this pinned build)

UE4SS's local `TMap` reimplementation is unreliable for **bulk reads** — confirmed via three independent methods all failing around row 63-64 of a 95-row DataTable (raw range-for iteration, `GetKeys()`, and even `GetDataTableRowNames`). **Rule: never bulk-iterate a `TMap` or a large `TArray`. Only single-key lookups / single-index access are safe.**

Related: `FName` construction defaults to `FNAME_Add` (creates a new entry), not `FNAME_Find`. To look up an *existing* name, always pass `FNAME_Find` explicitly, e.g. `FName(STR("IT_EqNaked"), FNAME_Find)`.

The built-in `ConsoleCommandsMod`'s `dump_object` console command is very useful for live reflection dumps (`dump_object <output.txt> <ObjectOrClassName> [Property] [Index]...`), but has a bug where dumping certain `BoolProperty` fields inside a struct throws (`attempt to call a nil value (method 'GetFieldMask')`) — this happens *after* whatever fields were listed before it print successfully, so partial dumps are still useful, but no `.txt` file gets saved when it crashes (the crash happens before the file-write step).

## Confirmed dead ends (do not retry without new evidence)

- `GsrDirtyManager.OverrideCamouflageType` — writes/reads correctly but does not visually apply anything; likely a network sync flag only
- `GsrDirtyManager:ChangeCamouflage(camo, bChangeMesh)` — runs without error, no visible effect
- `GsrPlayer:OnChangeCamouflage(...)` — runs without error, no visible effect
- `UE4PairingCamouflageManager:SetItem(...)` + `RefreshCamouflageBP(...)` — no visible effect
- Native console command `UnlockAllCamouflage` via `KismetSystemLibrary:ExecuteConsoleCommand` — runs without error but does not actually unlock anything
- Guessing `DT_CamouflageCollection` row names from `EItemName` strings (e.g. `IT_EqLeaf`, `IT_EqNaked`) — real row names in this table are **not** simply the `EItemName` enum strings; still unknown
- `BP_GsrEquipDataAssetHelper_C` (`/Game/Gsr/Blueprints/Equip/BP_GsrEquipDataAssetHelper`) — holds `EquipDataTable`/`GunDataTable`/`ThrowableDataTable`/`BlastDataTable`/etc. Looks like a **gameplay-stats system** (ammo, damage, capacity), not a mesh/texture lookup — likely unrelated to visuals
- Indexing a property directly off a **UClass** object (rather than a live spawned instance) via UE4SS Lua returns a `TrivialObject` placeholder with no real data — always resolve an actual live instance first (e.g. via `FindFirstOf` or a known property chain from another live object)
- Registering new `DT_CamouflageCollection` rows (with `CamouflageType` + `ItemType` set) does **not** make a new camo appear in the in-game TAB menu, and calling `UpdateCamouflageByNoPairing` with the new ID just silently falls back to default — both are explained by the `Camouf_<ID>` naming-convention finding above: no asset exists matching that name yet

## Current status

✅ Enum registration (`ECamouflageType`, `EItemName`, `EGsrItemId`) — confirmed via logs, correct sizes, no duplicates
✅ `DT_CamouflageCollection` row creation with unlock flags — confirmed via logs
✅ Save-file unlock array append (Lua) — confirmed, `CamouflageList` grows correctly
✅ Visual apply function identified and proven on vanilla camos
✅ Real asset-naming convention found (`Camouf_<ID>` / `Facepaint_<ID>`) — the actual missing piece for rendering

🔄 In progress: locating a real vanilla asset matching e.g. `Camouf_5` in the game's content (FModel), to learn its exact path/type/naming so a custom `Camouf_<newID>` asset can be built and packaged for a new camo to actually render

❌ Not yet done: wiring the Lua save-unlock call to run automatically after the C++ mod's registration (currently two separate manual steps)
❌ Not yet done: a data-driven registration list (currently a single hardcoded test entry in `on_update()`)
❌ Not yet confirmed: whether a newly-registered camo shows up in the in-game TAB menu at all (independent of visual rendering) — still unconfirmed across all attempts so far

## Tools used

Git, CMake, Visual Studio 2026 (v143 toolset), [FModel](https://fmodel.app/) with the community `.usmap` mapping file for this game (readable structure/properties; full decompiled Blueprint graph logic is not recoverable even with the mapping file in a cooked build), and UE4SS's own live reflection console commands for in-game inspection.
