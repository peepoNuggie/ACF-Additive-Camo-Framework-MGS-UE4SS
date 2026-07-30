# ACF — Additive Camo Framework

A UE4SS mod for **Metal Gear Solid Delta: Snake Eater** that adds four genuinely new
camouflage slots to the game instead of overwriting existing ones.

Camo mods for this game normally replace a vanilla uniform's textures in place. You lose the
original, and you can only run one such mod at a time. ACF gives modders four real slots, so a
modded camo sits alongside every vanilla uniform — selectable in the Survival Viewer, shown in the
Camouflage Collection, with nothing overwritten.

**ACF is a framework.** On its own it adds four empty slots; camo mods fill them.

---

## Status

**v1.0** — feature complete.

| | |
|---|---|
| Slots | 4 (camo IDs 61–64) |
| Survival Viewer | listed, named, icons, selectable |
| Camouflage Collection | listed, named, icons |
| Setup | automatic — no console commands |
| Saves | works on a fresh install, mid-save, or a brand new game |
| Vanilla content | untouched |
| Uninstall | tested, non-destructive |

---

## How it works

Three separate problems had to be solved, and none of them were where they first appeared to be.

### Getting a camo into the equip menu

Ownership is not stored where the save file suggests. It lives in a chain of three copies:

```
param_1 (real state)  ->  PTR_DAT_14c532038  ->  PTR_DAT_14c532020  ->  Mgs3GameData in the .sav
```

Both middle copies are **rebuilt from the real state before anything reads them** —
`FUN_147a7cf60` regenerates one when the Survival Viewer opens, and `FUN_147ad1bb0` copies that
into the save staging buffer. Writing either is silently undone.

The real store is an array at **`param_1 + 0x3E84`, stride `0x50`**, one `uint16` per
`ECamouflageType`. `param_1` is a static global, so ACF computes it directly and sets the flag
there every tick.

Editing `Mgs3GameData` in the `.sav` does not work — the game rejects the file, and no standard
digest of the blob is stored anywhere in it.

### Making the row readable

`MGS3InGameLocTable` has 94 `IT_Eq*` keys covering every base camo and **nothing** for the reserved
slots — the game shipped wired to loc keys nobody authored. So the menu falls back to printing the
key with its `アイテム名定義` namespace stripped, which is why a raw ID appeared on screen.

That fallback renders arbitrary text, so ACF feeds it the text we want: `DT_Mgs3UniformToCobraUIKey`
stores the namespace followed directly by the display name. The replacement is padded to the
original's exact character count, making it an in-place byte swap with no serialisation sizes to
patch.

### Icons

Each reserved slot already ships placeholder badge art as a numerically-named texture. ACF
overrides the pixel data in place — same dimensions, same format, so again no resizing.

This works where earlier attempts failed because it **overrides an asset the cooked
`AssetRegistry` already knows about**. Genuinely new assets are not resolvable by name in this
game, which is the limitation that shaped the whole design.

Full working notes, including the dead ends, are in [docs/RESEARCH_LOG.md](docs/RESEARCH_LOG.md).

---

## Repository layout

```
MyCPPMods/ACF/src/dllmain.cpp   the C++ mod — ownership, asset-lookup detour, registration
Mods/ACF/scripts/main.lua       the Lua mod — Collection Viewer unlock, diagnostics
docs/                           release docs, modder guide, research log
RE-UE4SS/                       UE4SS (pinned)
```

## Building

Requires Visual Studio 2022+ and CMake.

```
cmake --build build --config Game__Shipping__Win64 --target ACF
```

Then copy the output over the deployed mod:

```
build/MyCPPMods/ACF/Game__Shipping__Win64/ACF.dll
  ->  <game>/Binaries/Win64/ue4ss/Mods/ACF-CPP/dlls/main.dll
```

The game must be closed — the DLL is locked while it runs. Lua changes need a full game restart
unless `EnableAutoReloadingLuaMods` is enabled in `UE4SS-settings.ini`.

---

## For mod authors

Ship a `CamouflageAssetType` named `Camouf_<ID>_asset` at `/Game/Maps/AssetCamouflage/`, where
`<ID>` is 61–64. ACF handles unlocking, naming and icons.

Full guide, including the asset-rename trap that silently overrides the asset you cloned:
**[docs/MODDERS.txt](docs/MODDERS.txt)**

---

## Known limitations and issues

- **Four slots.** A hard limit of the game — those are the reserved uniform entries it already
  knows about. Higher IDs exist in the enum but can never be equipped.
- **Collisions are silent.** Two mods on the same slot means one disappears, with no error.
- **Slot names are generic** (`ACF Mod 1`–`4`), not the name of the mod filling them. A mod can
  override its own slot icon, but not yet its name.
- **Camouflage percentage is not configurable.** Every ACF slot currently uses the default rather
  than a value the mod author chooses.
- **Camo-related achievements are untested.** Use at your own discretion until someone confirms.
- **Uninstalling leaves empty rows** in saves made while it was installed. Harmless — selecting one
  shows Olive Drab — but they do not clear on their own. Reinstalling makes them work again.
- **Rare crash when switching camouflage.** Seen during development and not reproduced since a fix,
  but never conclusively proven fixed. A "Fatal Error" window may appear that you can sometimes
  survive by not dismissing it, and UE4SS will write a crash dump. Please attach `UE4SS.log` to any
  report — lines from this mod are tagged `[ACF]`.
- **Undocumented debug commands ship in `main.lua`.** These are the console commands used to build
  the mod. Unsupported, and a couple misbehave: unlocking the unused Bonsai/USMX camo IDs crashes
  the game, and the memory-watch commands tank the frame rate while active.

---

## Planned

- **Facepaint slots** — a parallel system to uniforms that looks like it should work the same way.
  Not yet investigated.
- **Two possible extra slots** — the game has two unused uniform entries ("Bonsai" and "USMX") the
  menu already lists and names. Filling them would take ACF from four slots to six. Currently
  unsafe: unlocking them without art attached crashes, and the cause is not understood.
- **Per-mod names, icons and descriptions**, so the list reads "Ocelot's Uniform" rather than
  "ACF Mod 2".
- **Slot collision detection** — at minimum a warning in the log.
- **Author-chosen camouflage percentage.**
- **More than 4–6 slots** — by far the hardest of these, and may not be possible.

---

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) — **`experimental-latest`**, not the
  tagged 3.0.1 release
- [MGS Delta UE4SS Fix](https://github.com/mattdavida/MGS-Delta-UE4SS-Fix) — required; UE4SS cannot
  locate the engine's object array in this game without it

> **Tested against:** UE4SS `v3.0.1 Beta #0`, git SHA **`c838a8ac`**.
> `experimental-latest` is a rolling tag, so a newer download may behave differently. If you hit a
> problem, the SHA is printed at the top of `UE4SS.log` — please include it in a report.

Both are hard requirements. A bundle including both, with `mods.txt` already configured, is
available on the [Nexus page](https://www.nexusmods.com/metalgearsoliddeltasnakeeater/mods/235).

---

## Support

Bug reports and pull requests are welcome here on GitHub.

Discord: **peepoNuggie**

---

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT)
- [MGS Delta UE4SS Fix](https://github.com/mattdavida/MGS-Delta-UE4SS-Fix) by mattdavida
- Tooling: [retoc](https://github.com/trumank/retoc),
  [repak](https://github.com/trumank/repak),
  [UAssetGUI](https://github.com/atenfyr/UAssetGUI),
  [FModel](https://fmodel.app/)

See [LICENSE](LICENSE).
