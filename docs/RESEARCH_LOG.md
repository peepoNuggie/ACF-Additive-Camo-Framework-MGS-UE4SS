# ACF — Additive Camo Framework (MGS Delta / UE4SS)

A UE4SS-based mod framework for **Metal Gear Solid Delta: Snake Eater** that lets modders **add** new camouflage/uniform/facepaint options as new content — like DLC — rather than replacing existing ones. The goal: a modeler packages their own mesh/texture as a `.pak`, and it shows up as a new, genuine, equippable option in the game's normal camo menu.

Status: **active reverse-engineering. Partially working.**

| | |
|---|---|
| ✅ **Custom camo asset renders in-game** | `forcecamo 0 60` draws our packaged `Camouf_60_asset`. Note: vanilla **does** ship a `Camouf_60_asset` (it points at `Gavs_Suit` meshes = the Crocodile Suit), so this proves we can **override** a vanilla package with custom content — not that we can add a new one |
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

## Uninstall behaviour (tested)

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
