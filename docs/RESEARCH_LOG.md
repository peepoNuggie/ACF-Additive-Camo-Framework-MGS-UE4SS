# ACF — Additive Camo Framework (MGS Delta / UE4SS)

A UE4SS-based mod framework for **Metal Gear Solid Delta: Snake Eater** that lets modders **add** new camouflage/uniform/facepaint options as new content — like DLC — rather than replacing existing ones. The goal: a modeler packages their own mesh/texture as a `.pak`, and it shows up as a new, genuine, equippable option in the game's normal camo menu.

Status: **working and released.** Four slots, 61–64, are fully functional. This log keeps the
reverse-engineering history including the dead ends, because most of the value is in knowing what
was already tried.

| | |
|---|---|
| ✅ Four addable slots, 61–64 | render, unlock automatically, and equip like any vanilla camo |
| ✅ Author-supplied **name** | via `Content/Paks/mods/ACF_Slot<ID>.txt`, both menus |
| ✅ Author-supplied **description** | native detour, Survival Viewer + Collection Viewer |
| ✅ Author-supplied **camouflage value** | real concealment, verified against enemy behavior |
| ✅ Author-supplied **per-terrain values** | the full 27-surface × 5-stance grid vanilla camos use |
| ✅ Custom thumbnails | inline DXT5 replacement in the CobraUI textures |
| ✅ Asset authoring + packaging pipeline | retoc → UAssetGUI → repak → retoc, documented below |
| ❌ More than four slots | hard limit, see below |
| ❌ The advertised stat keys | speed/health/effect multipliers are named in the template but not implemented |

**Four is a hard limit.** 61–64 are `GM_CAMOUF_ADDITIONAL_UNIFORM_2` through `_5`. Higher ids exist
in the enum but cannot be equipped: 65 is a download placeholder, 66 was an internal `MAX` sentinel,
67–69 are cardboard boxes. Raising the ceiling is *not* the blocker — ACF already calls
`ExpandCamouflageMax(100)` successfully. The blockers are that the native uniform value table is
exactly 70 entries with a live global immediately after it, and that per-id hardcoding is everywhere
(description loc keys stop at `AdditionalUniform5`, names and thumbnails are per-id).

Camo 60 is **not** an ACF slot — vanilla ships `Camouf_60_asset` pointing at the Crocodile Suit.
Early work used it to prove custom content could be packaged at all.

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
- Camos that change geometry also populate `SkeletalMeshAsset` (e.g. Sneaking Suit); pure recolors don't

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

## Correction: the "95 → 99 rows" result was corrupt, not a success

An earlier commit claimed DataTable row expansion worked. It did not. The four new row
names were inserted at NameMap indices 0-3, which **alias the first four existing row keys** —
the new rows were hijacking real ones. That is why they displayed as duplicate "CROCODILE SUIT"
entries. The build happened not to crash; it was never correct.

**The offline editing pipeline is sound** and is worth keeping:

```
dumpusmap (in game)                      -> Mappings.usmap from live reflection
UAssetGUI tojson <in> <out> VER_UE5_3 <mappingsNAME>   -> parsed rows
  (mappings must be the NAME, not a path — a path silently yields an opaque RawExport)
edit the JSON as raw UTF-8 text          -> reserializing mangles the Japanese loc keys
UAssetGUI fromjson ...                   -> .uasset/.uexp  (Windows paths ONLY; Bash
                                            /d/... paths fail silently, exit code 0)
repak pack -> retoc to-zen --version UE5_3
```

**The blocker is narrow:** `retoc to-zen` cannot add new names to a zen package's *local* name
map. Zen packages reference common names from a global table and store only package-unique ones
locally; `DT_CamouflageCollection`'s local map is 99 entries. Any appended row key lands at index
291 and the game dies at load with `ObjectSerializationError ... Bad name index 291/99`.

Ruled out: appending names at the end, inserting at the start, using row keys that already exist
in the global name table, and shipping the table as a legacy `.pak` (BPModLoaderMod mounts it but
only looks for a blueprint `ModActor`, so the override never applies).

Also corrected: `GM_CAMOUF_ADDITIONAL_UNIFORM_1` (camo 60) is the **Crocodile Suit**, a real DLC
uniform whose vanilla asset points at `Gavs_Suit` meshes — not an unused reserved slot. Overriding
it replaces real player content.

## ★★★ SOLVED: camos in the in-game Survival Viewer (equip menu)

ACF camos now appear in the actual equip menu, additively, with no vanilla camo replaced.

### Ownership lives in three copies, and only the first one matters

```
param_1 (REAL state)  ->  PTR_DAT_14c532038  ->  PTR_DAT_14c532020  ->  Mgs3GameData in the .sav
```

Both middle copies are **rebuilt from the real state before anything reads them**:

- `FUN_147a7cf60(param_1)` regenerates the `...038` block, and runs when the Survival Viewer
  opens — so writes to `...038` never survive to be displayed.
- `FUN_147ad1bb0(dst, size)` = `memcpy(020 + (dst - 038), dst, size)` copies `...038` into
  `...020`, which is only a save staging buffer.
- `FUN_147ab0db0` copies `...020` into the 19188-byte `Mgs3GameData` array at save time.

**The real ownership array is `param_1 + 0x3E84`, stride `0x50`, one `uint16` per
`ECamouflageType` id, `1` = owned.** Verified against two saves — the decoded owned list matched
the player's camos exactly both times, including correctly showing id 6 absent on the save where
that camo had not been picked up.

`param_1` cannot be read out of Ghidra: the only reference is `LEA R9,[FUN_147a7cf60]`, so it is
registered as a callback and the pointer exists only at run time. ACF hooks that function purely
to record it.

### Hard limit: five additive uniform slots

Confirmed by unlocking each id and checking the menu:

| id | enum | in the equip menu? |
|----|------|--------------------|
| 60 | `ADDITIONAL_UNIFORM_1` | yes — but it is the Crocodile Suit, real content |
| 61-64 | `ADDITIONAL_UNIFORM_2..5` | **yes — ACF's slots** |
| 65 | `DOWNLOAD` | no — written successfully, never lists |
| 66 | was `GM_CAMOUF_MAX` | no — sentinel, never a uniform |
| 67-69 | `EQ_CBOX_A/B/C` | no — cardboard boxes, already owned from the start |

Plus **52 (`BONSAI`)** and **53 (`USMX`)**: real enum entries the menu lists and names, with no
asset shipped. Supplying `Camouf_52_asset`/`Camouf_53_asset` should make them usable, the same way
slot 60 works. That would bring the total to **seven**.

**Granting an id with no matching `Camouf_<id>_asset` is a hard crash** when the player selects it.
Found the hard way with 52/53. `svunlock all` therefore covers 0-51 and 54-60 only.

### Techniques worth reusing

- **Page-protection traps** (`svwatch` / `svread`): `PAGE_READONLY` catches writes, `PAGE_NOACCESS`
  catches reads too. The handler records the faulting RIP plus the first return address inside the
  game module — essential, because the write usually comes from a CRT `memcpy` and the raw RIP is
  in the wrong module. It then single-steps the access through and re-arms. This is what revealed
  the viewer *writing* the table on open, proving it was a cache rather than the store.
- **Snapshot/diff** (`svsnap` / `svdiff`): copy the live block, act in game, diff. Shows every field
  an action touches instead of guessing which one matters.
- **UE4SS's own dumpers.** `GenerateSDK()` and `DumpAllObjects()` are Lua globals that write every
  class and `UFunction` to `ue4ss\CXXHeaderDump\` in ~1.6s. Hand-rolled reflection walks are
  unreliable on this build; these are C++ and bypass that entirely. This is how we established that
  **no `UFunction` grants ownership** — the acquire path is pure native C++.

### Dead ends, now closed for good

- Editing `Mgs3GameData` in the `.sav` — the game rejects the file, and no standard digest of the
  blob (CRC32/32C/BE, Adler32, FNV1a, XOR32, byte and word sums) is stored anywhere in it.
- Writing either mirror — both are rebuilt before anything reads them.
- The shipped debug menus (`m_debugUniformHasItem`, `m_debugForceEnableDlcItem`,
  `UpdateUniformAcquitionMap`) exist only as `Default__` CDOs in retail. Nothing constructs them.
- DLC is not a separate path: DLC camos (55-60) sit in the same array.

## ★★ SOLVED: custom thumbnails in the Survival Viewer

Slot thumbnails work. The trick is that it is an **override of existing art**, not a new asset.

Each reserved uniform slot already ships placeholder badge art ("U.H", "U.I", …) as a texture named
by number under `Plugins/CobraUI/Content/Textures/sv/camouflage/`:

| slot | camo id | texture |
|------|---------|---------|
| ACF Mod 1 | 61 | `9200220` |
| ACF Mod 2 | 62 | `9265756` |
| ACF Mod 3 | 63 | `9331292` |
| ACF Mod 4 | 64 | `9396828` |

All four are **256×128 DXT5**, stored inline in the `.uexp` (no `.ubulk`), laid out as:

```
113 bytes header  |  32768 bytes DXT5 payload  |  28 bytes trailer (width, height, then C1 83 2A 9E)
```

So replacing the art is a byte splice: keep the header and trailer, drop in the 32768 bytes that
follow a 256×128 DXT5 `.dds` file's 128-byte header. Then `repak pack` → `retoc to-zen --version
UE5_3` → drop in `Content/Paks/mods/`.

**Why this works when the earlier attempts did not.** Every previous thumbnail attempt shipped a
*new* texture, which the game then had to resolve by name — the same cooked-`AssetRegistry`
limitation that made `Camouf_72` impossible. Overriding an asset that is already registered skips
discovery completely.

**Verify the chunk ID.** IoStore finds assets by a hash of the package path, not by filename. The
modded chunk ID must be **identical** to vanilla's or the pak mounts and does nothing, silently:

```
retoc list --path pakchunk0-Windows.utoc   | findstr camouflage/9200220
retoc list --path mods/ACF_SvThumb_P.utoc  | findstr 9200220
```

**Caveat worth stating:** this is a replacement, not an addition. It only touches art that is
unreachable in vanilla (nothing unlocks those slots), and deleting the pak restores the game
exactly — but it is still an override, and two mods claiming the same slot texture will clash.

## Row names: chain mapped, fix still open

ACF rows in the Survival Viewer display the raw key `-IT_EqAdditionalUniform2-2`. The resolution
chain is now fully known:

```
uniform
  -> DT_Mgs3UniformToCobraUIKey  (/CobraUI/Data/SV/)
       ColumnA (ASCII)  = CobraUI key,  e.g. "ADDITIONAL2"
       ColumnB (UTF-16) = MGS3 loc key, e.g. "アイテム名定義-IT_EqAdditionalUniform2-2"
  -> MGS3InGameLocTable          (/CobraUI/Data/Localization/)
       maps that loc key to a numeric id
  -> the English text lives somewhere else again (not yet located)
```

**The gap is vanilla's.** `MGS3InGameLocTable` has 94 `IT_Eq*` keys covering every base camo and
nothing for `IT_EqAdditionalUniform1-5` — the reserved slots were wired to loc keys that were never
authored. It matches the `FPropData` dump exactly: base camos resolve, the DLC-era ones carry the
placeholder.

### Ruled out

- **No `.locres` files exist** in this game at all; localisation is DataTable-based.
- None of the 18 tables in `Content/Data/Localization` hold item or uniform display text. Check in
  **both ASCII and UTF-16** — an ASCII-only search gives a false negative, since UE stores these as
  UTF-16.
- Only `WeaponNameDataTable` exists; there is no uniform equivalent.
- `アイテム名定義` is not in the executable in either encoding.
- `MGS3InGameLocTable` stores keys back-to-back separated by binary — key→id, with no text to edit.
- **Runtime patching cannot work.** Four interception points were tried: writing the `FPropData`
  map, writing it every tick, writing `Name`+`SName`, and hooking `FindPropDataForSelectIndex` on
  the read path. The write always lands and the row never changes, because `FUN_1453d0c20` is the
  map's *destructor* (stride `0x98`, freeing four `FString`s per element at
  `+0x18/+0x28/+0x50/+0x68` = `Name`/`SName`/`Weight`/`Explain`) — the map is rebuilt on every open.

### Cheapest viable improvement, not yet tried

Edit `DT_Mgs3UniformToCobraUIKey` so `ADDITIONAL2-5`'s ColumnB points at loc keys that *do* resolve.
That gives real names, though vanilla words rather than "ACF Mod N". The replacement string differs
in length, so the export's `SerialSize` must be patched — UAssetGUI does that automatically, a raw
binary splice does not. Do **not** round-trip these tables through `tojson`/`fromjson`; that mangles
the Japanese keys.

## ★★ SOLVED: row names — exploit the loc fallback

Rows read `ACF Mod 1`–`ACF Mod 4` with no runtime code, no console command, and no vanilla camo
touched.

`MGS3InGameLocTable` has no entry for the reserved slots, so the game falls back to printing the
key with its `アイテム名定義` namespace stripped — which is why `-IT_EqAdditionalUniform2-2` appeared
on screen. That fallback renders **arbitrary text**, so the fix is to feed it the text we want
rather than fight it:

```
DT_Mgs3UniformToCobraUIKey  (/CobraUI/Data/SV/)
  ADDITIONAL2  ColumnB:  "アイテム名定義-IT_EqAdditionalUniform2-2"   ->  "アイテム名定義ACF Mod 1"
```

Namespace, then the display text, with no separator.

**The edit needs no resizing.** The original is 33 characters; `アイテム名定義ACF Mod 1` is 16. Pad with
17 trailing spaces and both are the same length, so it is a pure in-place byte swap in the `.uexp`
— no `SerialSize` or offset fields to patch, which is where `.uasset` edits normally break. Trailing
spaces are invisible in a left-aligned label.

Then `repak pack` → `retoc to-zen --version UE5_3` → `Content/Paks/mods/ACF_Names_P.*`, and verify
the chunk ID matches vanilla (`572e4e2cb06f28c1`) or the pak mounts and silently does nothing.

**Why data and not a runtime patch.** Four runtime interception points were tried and all failed:
writing the `FPropData` map, writing it every tick, writing `Name`+`SName`, and hooking
`FindPropDataForSelectIndex`. The map is rebuilt from this DataTable every time the viewer opens
(`FUN_1453d0c20` is its destructor), so any runtime edit is discarded. Fixing the table makes the
rebuild *produce* the right value instead of racing it.

`svkeymap` remains in main.lua as a diagnostic — it reads/writes the live
`Mgs3UniformCobraUiKeyMap` and is how this was proven before committing to a pak edit.

## Release contents

```
ACF.zip
└─ MGSDelta/
   ├─ Binaries/Win64/ue4ss/Mods/ACF-CPP/dlls/main.dll
   ├─ Binaries/Win64/ue4ss/Mods/ACF/scripts/main.lua
   └─ Content/Paks/mods/
        ACF_Names_P.{pak,utoc,ucas}     row labels
        ACF_SvThumb_P.{pak,utoc,ucas}   slot thumbnails
```

Plus a `mods.txt` edit (`ACF : 1`, `ACF-CPP : 1`) and UE4SS itself as a prerequisite.

## Uninstall behavior (tested)

Removing ACF completely — DLL, Lua and all paks — with a save that has slots 61-64 flagged owned:

- the game loads normally
- a camo that was equipped at save time reverts to Olive Drab on its own
- the four rows are still listed, because ownership lives in the save, not in any pak
- **selecting one does not crash** — it reverts to Olive Drab

So uninstalling is untidy but harmless. The leftover rows show raw loc keys and letter badges once
the cosmetic paks are gone. Worth a line in the install instructions; not a blocker.

**Correction to an earlier claim in these notes.** The Bonsai (52) / USMX (53) crash was attributed
to "owned camo with no asset". That is wrong — slots 61-64 are provably in exactly that state and
do not crash. Something else specific to 52/53 is responsible; they may lack a
`DT_UniformSortDelta` entry or a `DT_CamouflageCollection` row, which the reserved slots have. The
mitigation is unchanged (`svunlock all` skips both), but the reasoning behind it was not correct.

## ★★ SOLVED: descriptions in the Survival Viewer — detour a free function

Names and descriptions come from **different** systems; the loc-fallback trick above does not
transfer, because this key is built by the game from a constant rather than read from a table.

`FUN_145289f40` (Ghidra `0x145289F40`) is a free function:

```
FString* GetCaptionExplainText(FString* out, char tabType, int index)
```

For `tabType == 1` it builds a loc key from a **hardcoded switch on the id** — a Japanese
"uniform description resource" namespace plus a suffix — and resolves it with an empty fallback:

```
id 60      -> -AdditionalUniform1     (Crocodile, last vanilla)
id 61      -> -AdditionalUniform2     ACF slot 1
id 62..64  -> -AdditionalUniform3..5
```

Those four keys are well-formed but absent from the loc data, hence the blank panel. The same switch
explains why ids 34–51 all show identical text: they collapse onto one `-Download` key.

ACF detours the function and answers for 61–64 from the author's `Description=` line, falling
through to the original for everything else.

**A UE4SS `RegisterHook` on the UFunction is useless here.** It fires for Lua calls and never once
while the menu draws — 12 fires from a manual `svcap`, 0 from drawing the menu. That control test is
what proved the widget calls the native function directly. Run the equivalent test before trying to
hook any menu text.

**List index == camo id on this path**, confirmed against the switch. `GetCaptionText`'s index is
off by one from it — do not assume the two share an index.

**Encoding trap.** `dllmain.cpp` is UTF-8 with no BOM, so MSVC decodes non-ASCII string literals
using the system codepage. A Japanese loc key written literally was double-mangled by a save and
rendered as garbage in game. Any non-ASCII in C++ literals must use `\u` escapes; the Lua side
writes the namespace as byte escapes for the same reason.

## ★★★ SOLVED: real camouflage values — the native uniform table

ACF slots concealed exactly like Naked regardless of appearance. This was a gameplay bug, not a
presentation one, and the fix turned out to be a single byte.

`FUN_147A9D010` is the camouflage index calculator, reached from `FUN_147ACEC00` (the AOB used by
the [MGS3-Delta-Trainer](https://github.com/ANTIBigBoss/MGS3-Delta-Trainer)). It does:

```c
entry  = &DAT_1545218E0 + uniformId * 3;      // 0x18 bytes per entry
values = entry[1];                            // -> per-terrain block, +0x08 in the entry
index += *(char*)(values + terrainType * 5 + stanceColumn) * 10;
index += *(char*)((char*)entry + 0x16) * 10;  // flat, terrain-independent
```

- The uniform table is **70 entries**, `0x1545218E0` to `0x154521F78`, `0x18` stride. Ids 0–69 exist.
- The facepaint table is the same shape at `0x1545215E0`, ~31 entries.
- ACF ids 61–64 were never *missing* from it — they are **aliased to id 58's all-zero value block**,
  which is exactly why they concealed like Naked.
- The initializer `FUN_147A9E010` explicitly zeroes `+0x16`, and registers a system named
  `NewCamoufSystem` (matching the `?NewCamoufSystem` resource string at `0x149FF932F`).
- It does **not** populate `entry[1]`; that write goes through a cursor pointer, so Ghidra shows no
  write xref to the symbol. Do not go hunting for the populator — it is not needed.

**Gold's −100 is hardcoded for id 59 inside `FUN_147A9D010`, not table data.** That is why searching
memory for −100 never found anything. Gold's table row is unremarkable.

Ids 34–51 share one value block, matching their shared description.

Live values, useful for diagnostics:

| | |
|---|---|
| `DAT_1535C2064[player * 0x58]` | camo index x10 (the displayed percentage) |
| `0x1535BFB84` | terrain type in use |
| `0x1535BFBB0` | stance column in use |
| `0x1535BFB70` | final camo index |
| `PTR_DAT_14c532038[0x7AE]` | equipped uniform id, `[0x7AF]` facepaint |

**Verified against enemy behavior, not just the HUD** — on a save where a patrol runs past on load,
slot 62 at −5 got Snake spotted, slot 61 at +50 left him effectively invisible.

### The per-terrain grid

`entry[1]` points at **27 terrains x 5 stance columns = 135 signed bytes**.

**Terrain order is `EGsrMgs3CamoufType` order**, verified by dumping Snow (id 10): it peaks at
`WHITE` (90) with `ROOM_WHITE` next, and bottoms out at `ROOM_BLACK` (−35) and `BLACK` (−30). No
off-by-one. Those 27 names also ship as debug materials under `DebugCollisionAssets/Camo/Materials`.

**The five columns are stances**, proven by logging `0x1535BFBB0` while moving, not inferred:

```
0 standing        1 crouching        2 prone
3 wall, standing  4 wall, crouching
```

Column 0 is also read unconditionally as the baseline for the menu's delta display. Selection logic
in `FUN_147A9D010`: state `0x3b` picks group B (3/4) over group A (0/1/2); within A, state 3 and
not-`0xa9` gives 2; state 2 is the tiebreaker in **both** groups (0 vs 1, and 3 vs 4), which is why
it reads as a single crouch bit.

Tiger Stripe (id 1) on `GRASS`, as a worked example: `35 / 50 / 80 / 55 / 60`.

Surfaces are chosen by color and material, not by area — standing by a tree gives `SOIL_BROWN`,
then `OBJ_BROWN` pressed against the trunk, then `GRASS` a step away.

**How ACF uses it.** It allocates its own 135-byte block per slot, fills it from the author's
`ACF_Slot<ID>.txt`, and repoints `entry[1]` at it via `VirtualProtect`. Since ACF ids were aliased to
id 58's block, nothing of the game's is displaced. The flat byte at `+0x16` is written independently,
so `BaseCamo` works on its own and per-terrain lines are optional.

Verified in game by authoring a distinct value per stance on one surface and sweeping all five:
`SOIL_BROWN` returned exactly the authored `6/7/8/9/10`.

**The game applies its own modifiers on top.** The same terrain, stance and cell produced 360 at one
moment and 260 a minute later; wall-standing gave 390 then 440. Light level and time of day are the
presumed causes. This is correct behavior — it happens to vanilla camos too — and it means
`FINAL == cell x 10 + flat x 10` only holds when nothing else is in play.

## Known unresolved

Things understood well enough to write down, but deliberately not chased.

### Black (id 9) carries a flat value of 25; every other vanilla camo is 0

A `camotable` sweep of all 70 live entries found `+0x16` set to 25 for `GM_CAMOUF_BLACK` and 0 for
everything else, including Gold. The initializer provably zeroes the field for all 70, so
**something writes Black's 25 at runtime.**

This matters beyond curiosity, because ACF stores each slot's `BaseCamo` in that same byte:

- If the field is a **situational modifier slot** — written when conditions favour a camo, which
  would explain why it is added unconditionally while the condition lives in the writer — then
  something may eventually overwrite ACF's values.
- The leading hypothesis is a darkness or time-of-day bonus, since the observation was made in a
  single area and Black is the camo that would plausibly earn one.

Weak evidence against clobbering: ACF's values for 61–64 were still intact in a dump taken about
twelve minutes after install. One session in one area is not proof.

**Cheapest test if this is ever picked up:** run `camotable` in two areas with clearly different
lighting and compare Black's flat byte. If it changes, the field is dynamic. Watching Snow (10) in a
snowy area and Water (8) while swimming would confirm the situational reading outright rather than
resting on a single camo. If it does turn out to be dynamic, the honest fix is for ACF to stop
squatting in the byte and fold `BaseCamo` into the 135-byte grid it already owns.

### BaseCamo is an ACF invention, kept deliberately

No vanilla camo has a base value; a camo's entire strength is per-terrain. `BaseCamo` exists because
`+0x16` was the first writable byte found, and it is kept because it is a reasonable beginner option
— one number, no grid. The documentation says so plainly and tells authors to leave it at 0 when
using the grid, since the two add and the template prints real Tiger Stripe rows that would
otherwise silently double.

### The advertised stat keys are not implemented

`SpecialEffectFlag`, the movement/health/recovery multipliers and the infinite-ammo keys are listed
in the modder template so the file format does not have to change when they arrive. ACF ignores them
today. None of the camouflage research transfers — each is a separate hunt.

### Slots past four

Blocked, not impossible. The uniform value table is exactly 70 entries and `0x154521F78` is itself a
used global, so writing past entry 69 corrupts it — extending in place is out, and relocating or
shadowing the table is the realistic route. Ids 65–69 are taken (65 download placeholder, 66 an old
`MAX` sentinel, 67–69 cardboard boxes), and per-id hardcoding is pervasive: description loc keys stop
at `AdditionalUniform5`, and names and thumbnails are per-id too. The enum ceiling is *not* the
blocker — `ExpandCamouflageMax(100)` already succeeds.

## ★★ SOLVED: colored description lines

Vanilla entries such as Spider show a plain line followed by an orange one, and authors can now do
the same. **No new mechanism was needed** — the description widget is a rich text block, so a style
tag in the string ACF already supplies is honoured.

- Descriptions render through `UCobraRichTextBlock` (→ `UCommonRichTextBlock` → `URichTextBlock`),
  which resolves `<Tag>` markup against a `TextStyleSet` DataTable.
- The whole UI shares **one** style set, `/CobraUI/Data/RichText/RichTextStyleRowTemplate`, whose
  rows are the complete tag vocabulary:

  | tag | color |
  |---|---|
  | `<Default>` | plain |
  | `<Ability>` | orange |
  | `<Warning>` | red |
  | `<Special>` | yellow |

- **The close tag is `</>`, not `</Ability>`.** This cost a test cycle: `<Ability>` opened correctly
  and turned the text orange, but `</Ability>` was not recognized, printed literally, and the style
  ran to the end of the line. That looked at first like "markup is not supported", when in fact half
  of it had worked — the color change in the screenshot was the tell.
- `\n` in the string **does** produce a real line break in these widgets.
- HTML such as `<span color="#FF0000">` does nothing. Arbitrary colors would need a new row in that
  cooked DataTable, which cannot have rows added.

ACF exposes this as four plain keys rather than asking authors to learn the syntax —
`PlainDesc`, `AbilityDescOrange`, `WarningDesc`, `SpecialDesc` — assembled in that order by
`SlotMeta::ReadDescription`, skipping any that are blank or absent. `Description=` remains supported
and is used only when none of the four are present.

Confirmed working in the Camouflage Collection, which is the more surprising of the two: its
`DescryptionText` is a **loc key** (`ユニフォーム説明リソース-TIGER_STRIPE`), not literal text, so ACF's
description arrives through the missing-key fallback — and the widget still parses tags in it.

### Method notes worth reusing

- `UDataTableFunctionLibrary` is Blueprint-exposed, so `GetDataTableColumnAsString` and
  `GetDataTableRowNames` read any DataTable from Lua with no C++ and no memory work. **Out params
  are written into the table you pass in; the return value is `nil`.** Using the return value made
  both lookups look like empty tables.
- UE4SS wraps values in `RemoteUnrealParam`, sometimes more than one layer deep, and a wrapper
  prints as `RemoteUnrealParam: 0x...` rather than erroring. An early run reported
  "99 non-empty, 0 containing '<'" while testing the *wrapper's* text. `camodesc` now refuses to
  report counts if anything failed to unwrap.
- `FindFirstOf` picked a rich text block with no style set and reported that as though it settled
  the question. Most blocks on screen have no style set; take all of them.
- Reading the header dump first would have saved a cycle here: `whichtext` was written to identify
  the widget empirically, but `UCSVTabViewWidget::item_flavor_text` was already visible in
  `CobraUI.hpp` as a `UCobraRichTextBlock`.

### The uniform table entry is fully mapped, and holds no stats

Dumping all `0x18` bytes for Tiger Stripe (1, no ability), Sneaking Suit (12) and Spider (18):

```
+0x00   char*    camo name        "TIGER STRIPE"   "SNK_SUIT"   "SPIDER"
+0x08   int8_t*  the 27x5 per-terrain value block
+0x10   05 00 00 05 05 00         byte-for-byte identical on all three
+0x16   int8_t   flat value        ACF writes BaseCamo here
+0x17   00
```

The trailing eight bytes are the same whether or not the camo has a special ability, and the only
per-camo variation is the two pointers. **Uniform abilities are not data in this table.**

The name pointer was initially mistaken for a possible stats pointer. What ruled it out before
reading it was the spacing: 206 bytes across 11 entries, then 152 across 6, i.e. ~19-25 bytes each.
A struct has a fixed stride; uneven spacing is packed strings. Reading it as text confirmed that
rather than leaving it as an inference.

**Consequence for the advertised stat keys.** They cannot be implemented the way BaseCamo and the
per-terrain grid were - there is no table row to write. Spider's stealth-for-stamina and the
Sneaking Suit's effect are expressed in native code, consistent with Gold's -100 being hardcoded for
id 59 in `FUN_147A9D010`. Each key is its own hunt for the function that applies that effect, and
then a question of whether that function reads anything writable. Cost them individually; do not
group them with the terrain work.

**Also ruled out, from a suggestion worth recording so it is not retried:** `s_player` and `c_player`
do not exist in this game - neither name appears anywhere in the SDK dump. `BP_Player_C` is roughly
170 lines of skeletal mesh components and defense-target capsules, no stat or flag fields. There is
no `CamoufEffect`/ability enum or DataTable anywhere, and Spider appears only as a camo id and an
item id, never tied to a behavior.

## ★ TECHNIQUE: the binary carries the original MGS3 source tree

The legacy MGS3 code was compiled with assert/log calls that pass their own **source path and line
number** as arguments, and those strings survived into the shipping executable:

```
"Z:\CobraWIthIcs_20230930\UEProject\MGS3\source\game\gameover.c"
```

Extracting them gives **878 source filenames** — effectively a map of how the game's own code is
organized, by subsystem and by the programmer who owned it (`morita\player\`, `hatsu\enemy\`,
`arai\gauge\`, `nishida\`, ...).

**Why this matters more than any single find:** it converts "search the whole binary for the code
that does X" into "open the file that obviously owns X". For any future mechanic, name the file
first.

**The recipe.** Search Ghidra for the filename string, then read its XREFs: every referencing
instruction is an assert or log call, so each containing function is code from that file. This is
usually a handful of functions, not hundreds. `plg_it_optcmf.c` resolved to exactly two.

Extract the list with a plain string scan of the exe — no Ghidra needed:

```
grep -a -o 'source\[A-Za-z0-9_\]*\[A-Za-z0-9_]*\.[ch]' MGSDelta-Win64-Shipping.exe | sort -u
```

Files worth knowing about:

| area | file |
|---|---|
| camouflage gauge | `user\arai\gauge\camoufgauge.c` |
| Survival Viewer uniform tab | `user\mode\survivalviewer\sv_uniform.c`, `sv_uniform_viewer.c` |
| player life/stamina | `user\morita\player\plugin\system\plg_life.c` |
| player core | `user\morita\player\plugin\system\plg_core.c`, `player\command\ply_com.c` |
| optical camo (the Stealth item) | `user\morita\player\plugin\item\plg_it_optcmf.c` |
| enemy detection | `game\target.c`, `user\hatsu\enemy\ene_notice.c` |
| noise | `game\noise.c` |
| player stats / personal data | `game\personal.c` |

### What this says about the stat keys

**There is no uniform-effects module.** Nothing in the 878 files owns "what this uniform does" -
no `camouf_effect.c` or equivalent. Combined with the uniform table holding no stats, the conclusion
is that each ability is implemented at the site of its own mechanic: Spider's concealment in the
detection code, its stamina cost in the life system, movement modifiers in the player core.

So the advertised stat keys stay individual hunts - but bounded ones now. Each starts from a named
file rather than from the whole binary, which is a large reduction even though it is not a shortcut
to a table we can write.

`plg_it_optcmf.c` was checked and is the **Stealth item**, not the Spider uniform: `FUN_147c77570`
is an "Enter" state handler with no uniform test. Do not re-check it expecting camo abilities.

### Infinite ammo - traced three hops, not finished

Started from the observation that four different things grant infinite ammo (Infinity Face Paint,
Grenade camo, EZ Gun, RPG), so there is probably one shared mechanism rather than four.

The reflected consume path, found from exe strings rather than xref crawling:

```
UGsrEquipController::ReduceStockedAmmoCount(EGsrEquipId)
UGsrEquipController::ReduceLoadedAmmoCount(EGsrEquipId)
```

Located with `ufaddr` (see below) -> exec thunk `0x145A58620` -> real implementation
**`0x145C2A580`**.

**Neither branch of it has an infinite check - both decrement.** The guard that looked like one,
`FUN_145A6DB60`, is a plain classifier returning true for weapon kinds 1-9, i.e. "does not draw from
stocked ammo" (throwables). Static, nothing to do with what is worn. Do not re-read it hoping
otherwise.

So infinite ammo is decided **upstream**: the caller simply does not call reduce. Two ways on from
here, untried:

1. XREFs on `0x145C2A580` - who calls it, and what they test first.
2. `game\inventory.c`, which is the more likely home, because Delta runs the original MGS3 game code
   under a UE shell and the Infinity Face Paint is an original MGS3 feature. Its functions are
   contiguous at **`0x147A7A520`-`0x147A7C5A0`** (seven-plus of them). Its log operation names are
   `GM_InventoryDaemonStart`, `GM_ActiveItems`, `GM_ActiveWeapons` - none ammo-specific, so the
   function names give no shortcut and they need reading.

Ruled out along the way: `game\wp_mng.c` is the weapon MODEL manager (`GM_WeaponManagerTrigger`,
`NewAppearSight`, `SightDequeue`), never touches ammo counts.

Useful addresses confirmed here: `PTR_DAT_14c532038` resolves to `DAT_1535C21C0`, so the equipped
uniform is at a fixed `0x1535C296E` and the facepaint at `0x1535C296F`.

### `ufaddr` - locate any UFunction's native code by name

`ufaddr /Script/Pkg.Class:FunctionName` prints the live address and the Ghidra equivalent.

Reflection cannot INTERCEPT native work - a UE4SS hook on a UFunction fires only for Blueprint and
Lua callers, proven by the caption-getter control test. But the UFunction carries a pointer to its
native code, so it can LOCATE it. That converts "find this function in Ghidra" into a lookup by
name, and unlike a hardcoded offset it does not rot across game updates.

The address is normally the generic exec thunk, which unpacks parameters from the FFrame and calls
the real implementation - so expect one extra hop, as above.

### What the MGS3-Delta-Trainer does and does not give us

Source: https://github.com/ANTIBigBoss/MGS3-Delta-Trainer

**It cannot answer infinite ammo.** `MiscOffsets.InfiniteAmmoAndReloadSub = 4` exists and
`MiscManager.EnableInfAmmoAndReload()` NOPs four bytes over `0F B7 41 28`
(`movzx eax, word ptr [rcx+0x28]`), restoring those bytes to disable. But **there is no
`InfAmmoNoReload` entry in the AOB dictionary** - the pattern was never ported from the original
MGS3 trainer, so the feature cannot resolve an address. Do not treat it as a working reference.

Two things that looked like leads and are not:

- `MainPointerAddresses.SpecialItemsUsedSub = 2575` with the comment
  "Stealth = 1, Infinity FP = 2, Ez Gun = 4. Adding the totals tells what you used." This is a
  usage RECORD feeding the ending rank, not a switch that enables the effect.
- The trainer's ammo cheats (`ModifyMaxAmmo`, `ModifyCurrentAndMaxAmmo`) just poke values. They
  reach the same visible outcome by a different route and touch none of the game's own logic.

**It confirms two of our findings independently.** Its `calcuateCamoIndexOffset` AOB
(`48 83 EC 30 0F 29 74 24 20 48 8B F9 48 63 F2 E8`) is the function we reached from the camo index
work, and `MainPointerRegionOffset = 0xC532038` is our `PTR_DAT_14c532038`. Note its offsets are
SUBTRACTED from that base: camo at -974, facepaint at -973, matching our finding that facepaint sits
one byte after the uniform.

**Useful AOB anchors for stat keys we have not started.** These are worth keeping because each one
lands directly in the code for a mechanic the modder template advertises:

| AOB name | pattern | relevant to |
|---|---|---|
| `SnakeLifeRecovery` | `FF C7 83 FF 40 0F 8C 91` | `LifeRecoveryMultiplier` |
| `SnakeDamageMulti` | `00 8B 15 5C 1C AF 0B 0F BF C1 89 05 E7 BA AF 0B` | `HealthMultiplier` |
| `ActualSnakeDamageMulti` | `F6 C2 40 74 27 48 8B 05 00 00 00 04 0F BF 90 B4 07 00 00 ...` | damage taken |
| `GunReloadInstructions` | `66 39 72 2C 74 07 B9 01 00 00` | nearest ammo anchor |
| `PlayerStatusCheck` | `8B D1 B8 01 00 00 00 83 E1 1F D3 E0 8B CA 48 C1` | player state |

Weapon struct offsets seen in those instructions: `+0x28` and `+0x2C` are the 16-bit ammo fields
(the trainer uses `CurrentAmmoOffset = 0`, `MaxAmmoOffset = 2` from a per-weapon base).

**Practical consequence.** Health and life recovery now have direct anchors and are the cheapest of
the advertised stat keys to attempt. Infinite ammo has none and stays the most expensive - resume it
from the routes recorded above, not from the trainer.

### Infinite ammo, continued: two ammo systems, still unlocated

The Master Collection trainer (https://github.com/ANTIBigBoss/MGS3-Master-Collection-Trainer) HAS
the working pattern that Delta's port dropped:

```
InfAmmoNoReload = 66 85 C0 7E 29 66 FF C8 66 89 41 28
    test ax, ax / jle / dec ax / mov word ptr [rcx+0x28], ax
```

That exact sequence is NOT in Delta (recompiled, different register allocation), but the same
*shape* - test, conditional skip, store to `+0x28` - matches exactly one place in the Delta exe.

**Legacy consume: `FUN_147A7C530(uint weaponId, short amount)`**

```
weapon array  DAT_1535B7D20, stride 0x58, ids 0..0x82
  +0x00  stock ammo    decremented, clamped at 0
  +0x04  loaded ammo   decremented, clamped at 0
returns 1 consumed, 0 empty, -1 invalid id
```

No infinite check - it decrements unconditionally. And it has only **two** callers, both boss
plugins (`147CED2BC` in `plg_major.c`'s DamageCallback, and `148022919`). **So this is not the
general firing path**, despite being the only Delta site matching the MC shape. Do not treat it as
the main consume.

**The struct, from `GM_IV_SetCurrentWeapon` (`FUN_147A7BE40`, `inventory.c`):**

```
+0x24  flags (bit 0x1000 = chambered round)
+0x28  total stock       +0x2C  currently loaded       +0x2E  magazine capacity
```

`GM_IV_SetCurrentWeapon` refills `+0x2C` from `+0x2E`, clamped to `+0x28`. HUD mirrors live at
`PTR_DAT_14c532038 + 0x704` (weapon id), `+0x708`, `+0x70C` (loaded).

**Conclusion so far: Delta has two ammo systems.** The legacy one above survives for old boss
scripts; normal firing almost certainly goes through the UE side,
`UGsrEquipController::ReduceStockedAmmoCount` at `0x145C2A580`, which also has no infinite check.
So the condition is upstream of that, in its callers.

**Resume from:** XREFs on `0x145C2A580`. That is the one route not yet walked.

Enumerable inventory operations, for reference - none is a consume, so names give no shortcut:
`GM_IV_SetCurrentWeapon`, `GM_IV_SetCurrentItem`, `GM_IV_SendActiveWeaponSlot`,
`GM_IV_SendActiveItemSlot`, `GM_IV_WeaponDirectEatFood`.

**Method note.** Binary signature searches against the exe from the shell were far cheaper than
Ghidra round-trips for narrowing candidates - `grep -aobUP` with `\xNN` escapes and `(?s).{0,N}`
gaps took a list of 610 possible sites down to 1. Use that to pick the target BEFORE opening Ghidra.
