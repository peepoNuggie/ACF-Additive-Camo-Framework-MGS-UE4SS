# ACF — Additive Camo Framework

A UE4SS mod for **Metal Gear Solid Delta: Snake Eater** that adds four genuinely new
camouflage slots to the game instead of overwriting existing ones.

Camo mods for this game normally replace a vanilla uniform's textures in place. You lose the
original, and you can only run one such mod at a time. ACF gives modders four real slots, so a
modded camo sits alongside every vanilla uniform — selectable in the Survival Viewer, shown in the
Camouflage Collection, with nothing overwritten.

**ACF is a framework.** On its own it adds four empty slots; camo mods fill them.

> ### Downloads are on Nexus, not here
>
> **[Download ACF on Nexus Mods](https://www.nexusmods.com/metalgearsoliddeltasnakeeater/mods/235)**
>
> This repository holds **source code only**. There are no ready-to-install files here, and the
> automatic "Source code (zip)" archives GitHub attaches to tags will **not** work if you extract
> them into your game — they are the project, not the mod.
>
> Nexus carries the packaged builds, install instructions, and an all-in-one option that includes
> UE4SS and the fix for you.

---

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) — **`experimental-latest`**, not the
  tagged 3.0.1 release
- [MGS Delta UE4SS Fix](https://github.com/mattdavida/MGS-Delta-UE4SS-Fix) — required; UE4SS cannot
  locate the engine's object array in this game without it

> **Tested against:** UE4SS `v3.0.1 Beta #0`, git SHA **`c838a8ac`**.
> `experimental-latest` is a rolling tag, so a newer download may behave differently. If you hit a
> problem, the SHA is printed at the top of `UE4SS.log` — please include it in a report.

Both are hard requirements. The [Nexus page](https://www.nexusmods.com/metalgearsoliddeltasnakeeater/mods/235)
offers an all-in-one download that includes both, with `mods.txt` already configured — that is the
recommended route for anyone who would rather not set UE4SS up by hand.

**Optional, for mod authors:** [RRACF — Companion Tool for
ACF](https://www.nexusmods.com/metalgearsoliddeltasnakeeater/mods/236)
([source](https://github.com/peepoNuggie/RRACF-Companion-Tool-for-ACF)) converts an existing
replacer camo mod into an ACF slot mod and writes the `ACF_Slot<ID>.txt` for you. Not needed to
*play* with ACF — only to build for it, and everything it does can be done by hand with retoc and
repak as described in [docs/MODDERS.txt](docs/MODDERS.txt).

---

## For mod authors

Ship a `CamouflageAssetType` named `Camouf_<ID>_asset` at `/Game/Maps/AssetCamouflage/`, where
`<ID>` is 61–64. ACF handles unlocking and icons.

> **A fifth slot, id 65, exists in `main` but is experimental.** It lists, equips and renders
> custom art, and honours the same metadata file as the others. It is not in the v1.1 download, it
> needs the `slotpatch` console command to appear, and its row still shows the game's own name and
> thumbnail rather than yours. Build for 61–64 unless you are testing.

To name your slot, describe it and give it a real camouflage value, ship a plain text file beside
your pak at `Content/Paks/mods/ACF_Slot<ID>.txt`:

```
Name=Ocelot's Uniform
PlainDesc=Worn by the young Ocelot.
AbilityDescOrange=Draws faster from the hip.
BaseCamo=0
```

Ready-made templates are in [docs/modder_templates/](docs/modder_templates/) — four for the real
slots, plus `ACF_Slot65.txt` marked experimental. Run `acfslots` in the console to see exactly what
ACF read from your file, and to be told about any line it could not parse.

Full guide, including the asset-rename trap that silently overrides the asset you cloned:
**[docs/MODDERS.txt](docs/MODDERS.txt)**

---

## Status

Latest release is **v1.1**. This describes `main`, which is ahead of it.

| | |
|---|---|
| Slots | 4 (camo IDs 61–64), plus an experimental 5th at 65 |
| Survival Viewer | listed, named, described, icons, selectable |
| Camouflage Collection | listed, named, described, icons |
| Author-supplied metadata | name, description and camouflage value, via a `.txt` beside the pak |
| Per-terrain values | the full 27-surface × 5-stance grid vanilla camos use |
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
original's exact character count, making it an in-place byte swap with no serialization sizes to
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

## Known limitations and issues

- **Four slots, shipped.** Those are the reserved uniform entries the game already knows about. A
  fifth (id 65) works in `main` behind the `slotpatch` command but is experimental — see above.
  Beyond that the game's own tables run out: the uniform value table holds exactly 70 entries with
  a live global immediately after it, and ids 66–69 are missing from the resource map entirely.
- **Collisions are silent.** Two mods on the same slot means one disappears, with no error — though
  ACF does warn in the log when two `ACF_Slot<ID>.txt` files claim the same slot.
- **A slot with no metadata file keeps a generic name** (`ACF Mod 1`–`4`). That is the fallback, not
  a limitation — authors supply their own via `ACF_Slot<ID>.txt`.
- **Several documented metadata keys do nothing yet** — the movement, health and recovery
  multipliers. They are listed in the modder template so the file format does not have to change
  when they arrive, and ACF ignores them today. (Infinite ammo and steady aim have since been
  implemented and do work.)
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

## Ideas being looked at

No commitments and no ordering — these are open problems, some of which may turn out to be
impossible.

- **More than five slots.** A fifth (id 65) now works behind `slotpatch`; finishing it means giving
  it a proper name and thumbnail, which the other four get from a row map that has no entry for it.
  Past that the game's tables run out: ids 66–69 are absent from the resource map, and the uniform
  value table holds exactly 70 entries with a live global immediately after it, so going further
  means relocating that table rather than extending it.
- **Automatic slotting**, so an author ships one mod instead of four slot variants and ACF assigns
  a free slot.
- **Facepaint slots** — a parallel system whose table sits directly below the uniform one, same
  layout.
- **The stat keys** already named in the modder template.

Two unused uniform entries ("Bonsai" and "USMX") are *not* a route to extra slots — unlocking them
without art attached crashes, and that path has been set aside.

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
