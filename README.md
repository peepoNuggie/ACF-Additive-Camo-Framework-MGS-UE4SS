# ACF — Additive Camo Framework (MGS Delta / UE4SS)

A UE4SS-based mod framework for **Metal Gear Solid Delta: Snake Eater** that lets modders **add** new camouflage/uniform/facepaint options as new content — like DLC — rather than replacing existing ones. The goal: a modeler packages their own mesh/texture as a `.pak`, and it shows up as a new, genuine, equippable option in the game's normal camo menu.

Status: **active reverse-engineering. Partially working.**

| | |
|---|---|
| ✅ **Custom camo asset renders in-game** | `forcecamo 0 60` draws our packaged `Camouf_60_asset` — camo 60 has no vanilla visuals, so it can only be ours |
| ✅ New camo appears in the **Collection Viewer** | confirmed by A/B test — the row vanishes when the mod is disabled |
| ✅ Enum + DataTable registration at runtime | `ECamouflageType`, `EItemName`, `EGsrItemId`, `DT_CamouflageCollection`, `DT_UniformSortDelta` |
| ✅ Custom asset authoring + packaging pipeline | retoc → UAssetGUI → repak → retoc, fully documented below |
| ❌ New camo in the **TAB equip menu** | blocked — different system, native-only, see [The equip menu problem](#the-equip-menu-problem) |
| ⚠️ Only **one** row can be added at runtime | `AddRow` deletes as it inserts; use reserved slots or a pre-authored table |

**Camo 60 (`GM_CAMOUF_ADDITIONAL_UNIFORM_1`) is currently the only slot that renders.** The `66` ceiling (`GM_CAMOUF_MAX`) is compiled into native machine code — raising it in the `UEnum` at runtime provably does nothing, so IDs above 65 can never be unlocked.

Slots 61-65 were expected to work the same way as 60. **They do not**, and two hypotheses for why have been tested and disproven:

| Hypothesis | Test | Result |
|---|---|---|
| The `Camouf_<ID>_asset` is the only missing piece | Byte-patched `Camouf_60_asset` into 61-65 (all 15 chars, so all offsets stay valid), packed as one pak, verified **distinct chunk IDs** via `retoc list` | ❌ 61-65 still dead |
| A `DT_CamouflageCollection` row is required to render | Spent the single available runtime `AddRow` on camo 61 (`collection rows 95 → 96`, sort row added, enum reused correctly) | ❌ 61 still dead |

So neither the asset nor the row is what makes 60 special. The open question is what the camo-ID → asset lookup actually consults, and whether 61-65 are ever *asked for* in the first place. Next test is `loadasset Camouf_60_asset` vs `loadasset Camouf_61_asset`, which splits "our asset can't load" from "the game never requests it".

Note that the reserved slots are **not** uniformly pre-provisioned: only 60 has a vanilla `DT_CamouflageCollection` row (`IT_EqAdditionalUniform2`) and sort entry. 61-65 have an enum entry and nothing else.

**The single most important thing to understand about this codebase:** `DT_CamouflageCollection` drives the **Collection Viewer** (the Extras gallery that shows camos on a posed model), *not* the in-game TAB equip menu. They are separate systems with separate data sources. A large amount of early work was spent editing that table and concluding "nothing happened" while looking at the wrong screen.

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
5. Drop the resulting `.pak`/`.utoc`/`.ucas` trio into `Content/Paks/mods/`. **Not `LogicMods/`** — the game mounts either, but `BPModLoaderMod` scans `LogicMods` expecting a `ModActor` Blueprint in every pak and spams `ModClass ... is not valid` for pure content paks.

### Extracting a *mod's* assets rather than the base game's

`to-legacy` pointed at the whole `Content/Paks` folder returns the **base-game** version of a file even when an installed mod overrides that path. To get the mod's actual data, copy the mod's `.pak`/`.ucas`/`.utoc` **plus** the game's `global.utoc`/`global.ucas` into an isolated folder and extract from there — isolation removes the vanilla copy, and `global` is required or extraction fails with `ScriptObjects not found`.

**Verify with a checksum, never file size.** A texture reskin at the same resolution and format is byte-for-byte the same *size* as the original. We shipped vanilla textures for days on the strength of a matching size.

All tools confirmed working end-to-end for cloning a real camo (`Camouf_12_asset`, vanilla Sneaking Suit) into a new one (`Camouf_72_asset`) with relocated textures/materials — see git history for the full worked example. Extracted/staged game assets live in a gitignored `WorkInProgress/` folder and are never committed (copyrighted content).

### Unlocking (separate from visual apply)

`UserProfileSaveGame` has `CamouflageList`/`FacePaintList` (`TArray<bool>`). Confirmed safe technique: single-item array append via plain Lua array syntax (`camoList[#camoList + 1] = true`). Do **not** bulk-iterate this array.

## Tooling notes

The built-in `ConsoleCommandsMod`'s `dump_object` command is invaluable for live reflection dumps (`dump_object <output.txt> <ObjectOrClassName> [Property] [Index]...`), but ships with two bugs that abort a dump partway:

- `BoolProperty` inside a struct → `attempt to call a nil value (method 'GetFieldMask')`
- `ObjectProperty` on some classes → same for `GetPropertyClass`

Both are one-line fixes in the deployed `ue4ss/Mods/ConsoleCommandsMod/Scripts/dump_object.lua` (guard the call with `Property.X ~= nil`). Worth patching locally — note that when it aborts, the `.txt` file is never written, so only the console output survives.

Reading `UE4SS.log` directly is far more reliable than copying console output, which truncates.

## Confirmed dead ends (do not retry without new evidence)

- `GsrDirtyManager.OverrideCamouflageType` — reads/writes fine but applies nothing visually; likely a network sync flag
- `GsrPlayer:OnChangeCamouflage(...)` — runs without error, no visible effect
- `UE4PairingCamouflageManager:SetItem(...)` + `RefreshCamouflageBP(...)` — no visible effect
- `UnlockAllCamouflage` console command via `KismetSystemLibrary:ExecuteConsoleCommand` — runs, unlocks nothing
- `BP_GsrEquipDataAssetHelper_C` — holds `EquipDataTable`/`GunDataTable`/`ThrowableDataTable`/`BlastDataTable`. A gameplay-stats system (ammo, damage, capacity), unrelated to visuals
- **All save-based unlock mechanisms.** `CamouflageList` direct index-write, `UnlockCamouflageMap:Add()`, and `UnlockCamouflageCollectionViewerMap:Add()` were each tested against both a complete vanilla reserved row (`GM_CAMOUF_ADDITIONAL_UNIFORM_1`) and a real vanilla camo ID. All succeeded without error; none affected menu visibility. `UserProfileSaveGame` has no separate inventory/possession array.
- `GetCamouflageByIndex` — never fires when hooked, even during real browsing. Likely `BlueprintPure` and inlined at compile time.

### Corrections to earlier conclusions

Two things previously recorded as dead ends were wrong, and cost significant time:

- **`GsrDirtyManager:ChangeCamouflage`** was dismissed after being called with a guessed two-parameter signature `(camo, bChangeMesh)`. The real signature is **one int**, and it *does* fire during real menu-driven equips. Wrong signature, not a dead function.
- **`DT_CamouflageCollection` row names** were assumed not to match `EItemName` strings. They do — `IT_EqNaked` is literally the first row key. The lookups failed because of the UE4SS `TMap` read bug, not because the names were wrong.

## What works

**Runtime registration** (`MyCPPMods/ACF/src/dllmain.cpp`). On load, ACF appends entries to `ECamouflageType`, `EItemName` and `EGsrItemId`, then adds rows to `DT_CamouflageCollection` and `DT_UniformSortDelta`. Adding a camo is one line in the `camos[]` table.

Verified by disabling the mod (rename `main.dll`) and confirming the new Collection Viewer row disappears — so the entry is genuinely ours, not a vanilla reserved slot.

**Asset authoring pipeline** — extract, edit, repack and deploy real game assets. See [Asset-authoring pipeline](#asset-authoring-pipeline-creating-a-real-new-camos-visuals).

**Confirmed asset conventions:**
- A camo's visuals live in `/Game/Maps/AssetCamouflage/Camouf_<ID>_asset`, a `CamouflageAssetType` (a `PrimaryDataAsset`)
- `MaterialAsset` maps body part → material slot → `MaterialInstanceConstant`
- Only `BaseColor_NonVT` carries the camo-specific texture; every other texture parameter points at shared base-body assets
- Camos that change geometry also populate `SkeletalMeshAsset` (e.g. Sneaking Suit); pure recolours don't

## What doesn't work yet

**Rows register blank.** Cloning an existing row as a template fails because `DataTable::FindRowUnchecked` returns null for every row name tried — UE4SS's `TMap` reads are broken on this build. Registered rows therefore have no `Thumbnail`, `DisplayName`, `AssetID`, `ModelAsset` or `FaceOption`. A blank row still produces a visible Collection Viewer slot, but it can't display properly. Fixing it means building those fields by hand (`FString`/`FText`/soft object refs) rather than copying them.

**Only one of two registered camos appeared.** Both logged full success with distinct item types. Unresolved — there's a deliberately-ordered experiment in `on_update()` to distinguish the candidate causes.

<a name="the-equip-menu-problem"></a>
## The equip menu problem

The TAB equip menu does **not** read `DT_CamouflageCollection`. Ghidra disassembly shows it reads two chained `TMap`s on a `CSVTabViewWidget` instance:

```
+0x798:  TMap<int32 SelectIndex, UObject* Button>    (stride 0x18)
+0x748:  TMap<UObject* Button, FPropData>            (stride 0x98)
```

So: **slot index → live button widget → item data**. The list is a set of runtime-spawned `CPropButtonBase` widgets, not table rows.

Key addresses (this build; absolute, image base `0x140000000`):

| Thing | Address |
|---|---|
| `FindPropDataForSelectIndex` impl | `FUN_1453c7f40` |
| key helper (index → button) | `FUN_1453c7de0` |
| native function table (18 entries) | `14af6ac60` – `14af6ad80` |
| table registrar | `FUN_1453c3440` |
| `CPropButtonBase::StaticClass()` | `FUN_14523b2b0` |

**None of the 18 registered functions populates those maps** — the writer is unexported native code, and hasn't been located.

**Why hooking can't reach it:** UE4SS `RegisterHook` only intercepts Unreal's VM/`ProcessEvent` dispatch. Native C++ calling native C++ bypasses it entirely. All three `CSVTabViewWidget` hooks registered successfully and never fired during real menu use, while Blueprint-invoked functions (`GsrDirtyManager:ChangeCamouflage`, `BP_Player:OnChangeCamouflageApply`) fired correctly with real parameter values. Widget-construction hooks (`UserWidget:Construct`, `UMG:CreateWidget`) also never fired — the buttons' *class* is Blueprint (`sv_tab_switch_item_C`) but their *creation* is native.

Remaining options: a PolyHook native detour on the real function address (PolyHook is already a UE4SS dependency; would need signature scanning rather than hardcoded addresses), or writing into the TMaps directly from C++ (offsets known, but the values are live widget objects that would have to be constructed and wired correctly).

## Gotchas worth knowing

- **`UpdateCamouflageByNoPairing` is a preview-only debug function.** It reverts on pause or area change. It is *not* the equip pipeline, despite visibly changing the model. Test infrastructure was built around it before this was noticed.
- **Never iterate a `TMap`.** Range-for over `DataTable::GetRowMap()` **hard-crashes the game**, even breaking after the first element. TMap *writes* (`AddRow`) work fine; reads and iteration do not.
- **Never trust `ForEachFunction`/`ForEachProperty`.** `UClass::FuncMap` is a `TMap`, so enumeration silently omits functions — it hid six real ones. Use `StaticFindObject("/Script/Pkg.Class:FuncName")` instead.
- **`FName` defaults to `FNAME_Add`,** which creates a new entry. Pass `FNAME_Find` to look one up — though note neither mode made `FindRowUnchecked` work here.
- **Reading a property off a `UClass` gives a `TrivialObject` placeholder** with no data. Always resolve a live instance first.
- **UAssetGUI renames need two edits.** The **Name Map** entries *and* **General Information → PackageName**. Miss the latter and the IoStore chunk ID collides with the original asset, silently overriding it instead of creating a new one.
- **Licensing:** the current test asset reuses textures from a third-party Nexus mod. Fine for local testing; must be rebuilt from vanilla-only content before any public release.

## Tools used

Git, CMake, Visual Studio 2026 (v143 toolset), [FModel](https://fmodel.app/) with the community `.usmap` mapping file for this game (readable structure/properties; full decompiled Blueprint graph logic is not recoverable even with the mapping file in a cooked build), UE4SS's own live reflection console commands for in-game inspection, and the asset-authoring pipeline: [retoc](https://github.com/trumank/retoc), [UAssetGUI](https://github.com/atenfyr/UAssetGUI), and [repak](https://github.com/trumank/repak) (see [Asset-authoring pipeline](#asset-authoring-pipeline-creating-a-real-new-camos-visuals) above).
