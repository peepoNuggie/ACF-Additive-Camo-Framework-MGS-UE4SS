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
8. **`CamouflageAssetType`** (`/Script/MGS3`, extends `PrimaryDataAsset`) — the actual asset class. Fields: `MaterialAsset`, `SkeletalMeshAsset`, `StaticMeshAsset`, `MeshAssetLocalOffset`, `MeshAssetSocket`, `CINSkeletalMeshAsset` (all maps). **Confirmed real asset location** (via `FindAllOf("CamouflageAssetType")` on a live game — no FModel needed): a camo's asset is named **`Camouf_<ID>_asset`**, living at **`/Game/Maps/AssetCamouflage/`** (e.g. `/Game/Maps/AssetCamouflage/Camouf_5_asset`). The `_asset` suffix matches a `bNeedSuffix` flag seen on the internal lookup-cache struct. Conditional equipment-removal flags (unrelated to camo ID) live in a sibling `/Game/Maps/AssetMisc/` folder instead.
9. **`BPModLoaderMod`** (built into UE4SS) auto-mounts any `.pak`/`.utoc`/`.ucas` dropped in `Content/Paks/LogicMods/` — no custom mounting code needed
10. **`CamouflageAssetType`'s real schema** (confirmed via FModel JSON export): `MaterialAsset` is a `TMap<MODEL_PART_TYPE, { MaterialMap: TMap<SlotName, MaterialInstanceConstant> }>`. Camos that don't change body shape (e.g. `Splitter`, ID 5) only populate `MaterialAsset`; camos with custom geometry (e.g. `Sneaking`, ID 12) also populate `SkeletalMeshAsset` (`TMap<MODEL_PART_TYPE, SkeletalMesh>`). Within a material instance, almost all texture parameters point at shared base-body textures — only **`BaseColor_NonVT`** holds the camo-specific diffuse texture.

## Asset-authoring pipeline (creating a real new camo's visuals)

This game ships assets in UE5's IoStore format (`.pak`+`.utoc`+`.ucas`, with `.pak` nearly empty and real content in `.ucas`). Confirmed working toolchain, all standalone (no Unreal Engine install needed):

1. **[retoc](https://github.com/trumank/retoc)** — `retoc.exe to-legacy <Paks-folder> <output-dir> --version UE5_3 -f "<name-filter>"` extracts real assets from the game (or a mod's own pak) into classic Legacy `.uasset`/`.uexp`/`.ubulk` files UAssetGUI can open. **Must point at the whole `Content/Paks` folder**, not a single `.utoc` — the shared script-objects data lives in a separate `global.utoc` and extraction fails without it. (Do NOT use `retoc get`/`unpack` for this — those produce Zen-format files UAssetGUI can't open directly.)
2. **[UAssetGUI](https://github.com/atenfyr/UAssetGUI)** — GUI editor for the extracted Legacy files. To rename/clone an asset: edit its **Name Map** entries (the asset's own short name + full package path, found by searching the Name Map list) and, for anything referencing other assets (a material's texture, a DataAsset's material references), edit the corresponding **Import Data** rows (an import's `ObjectName` + its `OuterIndex` package row) to point at the new relocated asset instead. Save with Ctrl+S (Save As has been unreliable at creating files in not-yet-existing folders — just move/rename the file afterward instead).
3. **[repak](https://github.com/trumank/repak)** — `repak.exe pack <staging-dir> <output.pak>` packs the edited loose files (mirroring the game's own folder structure, e.g. `<staging-dir>/MGSDelta/Content/...`) into a plain legacy `.pak`.
4. **retoc again** — `retoc.exe to-zen <input.pak> <output.utoc> --version UE5_3` converts that legacy pak into the real IoStore `.utoc`/`.ucas` pair.
5. Drop the resulting `.pak`/`.utoc`/`.ucas` trio into `Content/Paks/mods/` (or `LogicMods/`).

All tools confirmed working end-to-end for cloning a real camo (`Camouf_12_asset`, vanilla Sneaking Suit) into a new one (`Camouf_72_asset`) with relocated textures/materials — see git history for the full worked example. Extracted/staged game assets live in a gitignored `WorkInProgress/` folder and are never committed (copyrighted content).

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
⚠️ **Correction**: `UE4PairingCamouflageManager:UpdateCamouflageByNoPairing` (previously called "the confirmed visual apply function") is actually a **temporary preview/debug override** — the name says "NoPairing," and it reverts on pause or area transition. It is NOT the real equip pipeline. This was caught late in a session that had built significant test infrastructure around it — see project notes for the full correction and its implications.
✅ Real asset-naming convention found (`Camouf_<ID>` / `Facepaint_<ID>`) — likely still real (the underlying cache genuinely updates), but which function triggers it during *real* gameplay equip is now unconfirmed, not just assumed
✅ Real asset location + exact filename confirmed: `/Game/Maps/AssetCamouflage/Camouf_<ID>_asset` (a `CamouflageAssetType` `PrimaryDataAsset`)
✅ Full real `CamouflageAssetType`/`MaterialInstanceConstant` schema confirmed with real populated data
✅ Complete standalone asset-authoring toolchain confirmed working (retoc + UAssetGUI + repak) — extract, edit, pack, and deploy a cloned/modified real camo asset
✅ First full test asset built: `Camouf_72_asset` cloned from vanilla Sneaking Suit (ID 12), with new relocated textures/materials, packaged and deployed to `Content/Paks/LogicMods/`
✅ Found and fixed a real asset-cloning bug: UAssetGUI's **Name Map** rename alone is insufficient — **General Information → PackageName** is a separate hidden field that must also be edited, or the IoStore chunk ID collides with the original asset (confirmed via `retoc list --path` chunk-ID comparison before/after)

⚠️ **Significant open problem, still unresolved — the real equip code path is unidentified**: `forcecamo 0 72` (via the preview-only function above) never loads the new asset. Hooking `DataAssetHelper:LoadDataAsset`, `GsrCollectionItemController:CreateItem`, and `GsrCollectionItemController:ItemNameToItemId` directly (UE4SS `RegisterHook`) — then equipping camo/facepaint/item/weapon changes through the **real in-game menus** — produced zero hook fires across all three, confirmed via direct `UE4SS.log` inspection. So none of these four candidate functions (the three hooked, plus the preview function) are the real equip mechanism. A fourth hook target, `BP_CamouflageCollectionSnake:OnChangeItem`, failed to even register (wrong path guess, not yet corrected). The real native code path remains unidentified — next steps are either more hook-hunting (try `OnChangeItem` with a corrected path, or `GsrPlayer:OnChangeCamouflage`/`GsrDirtyManager:ChangeCamouflage` as hooks rather than direct calls) or static disassembly (Ghidra, already in the toolkit, unused so far).

❌ Not yet done: wiring the Lua save-unlock call to run automatically after the C++ mod's registration (currently two separate manual steps)
❌ Not yet done: a data-driven registration list (currently a single hardcoded test entry in `on_update()`)
❌ Not yet confirmed: whether a newly-registered camo shows up in the in-game TAB menu at all (independent of visual rendering) — still unconfirmed across all attempts so far
❌ Not yet resolved: the current test asset (`Camouf_72_asset`) uses texture data extracted from a third-party Nexus mod ("Immersive Sneaking Suit") — fine for private testing, but should not be publicly distributed without confirming that mod's redistribution permissions, or rebuilt with vanilla-only texture data for public release

## Tools used

Git, CMake, Visual Studio 2026 (v143 toolset), [FModel](https://fmodel.app/) with the community `.usmap` mapping file for this game (readable structure/properties; full decompiled Blueprint graph logic is not recoverable even with the mapping file in a cooked build), UE4SS's own live reflection console commands for in-game inspection, and the asset-authoring pipeline: [retoc](https://github.com/trumank/retoc), [UAssetGUI](https://github.com/atenfyr/UAssetGUI), and [repak](https://github.com/trumank/repak) (see [Asset-authoring pipeline](#asset-authoring-pipeline-creating-a-real-new-camos-visuals) above).
