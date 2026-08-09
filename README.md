# ACF — Additive Camo Framework

A UE4SS mod for **Metal Gear Solid Delta: Snake Eater** that adds five genuinely new
camouflage slots to the game instead of overwriting existing ones.

Camo mods for this game normally replace a vanilla uniform's textures in place. You lose the
original, and you can only run one such mod at a time. ACF gives modders five real slots, so a
modded camo sits alongside every vanilla uniform — selectable in the Survival Viewer, shown in the
Camouflage Collection, with nothing overwritten.

**ACF is a framework.** On its own it adds five empty slots; camo mods fill them.

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

### Branches

| | |
|---|---|
| **`main`** | The released code. Matches the current Nexus download, tagged `v2.0`. Read this one if you want to know how the shipping mod works. |
| **`experimental`** | Where development happens. Everything in `main` plus whatever is being built next. Expect it to be ahead, and expect it to break. |

Anything landing in `experimental` reaches `main` when it ships. If you are filing an issue, say which
branch you were on — a bug in `experimental` may already be known, and a bug in `main` is in
everyone's download.

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

**Recommended, not required:** [RRACF — Companion Tool for
ACF](https://www.nexusmods.com/metalgearsoliddeltasnakeeater/mods/236)
([source](https://github.com/peepoNuggie/RRACF-Companion-Tool-for-ACF)) turns any existing replacer
camo mod into an ACF slot mod and writes its `ACF_Slot<ID>.txt` for you.

That matters whether or not you make mods. Most camo mods for this game overwrite a vanilla uniform
— RRACF moves one onto a free ACF slot instead, so you keep the original *and* can run several at
once. Authors can use it to ship a slot-ready release; players can use it on mods they have already
downloaded.

ACF works fine without it, and everything it does can be done by hand with retoc and repak as
described in [docs/MODDERS.txt](docs/MODDERS.txt) — RRACF just does it in one step.

---

## For mod authors

Ship a `CamouflageAssetType` named `Camouf_<ID>_asset` at `/Game/Maps/AssetCamouflage/`, where
`<ID>` is 61–65. ACF handles unlocking and icons.

> **Slot 5 (id 65) is new in v2.0.** It lists, equips, renders, auto-unlocks, takes your name and
> description, and has its own thumbnail — with two differences. Its **concealment values do not
> work**: `BaseCamo` and the per-terrain grid are read correctly and overridden by the game, so it
> conceals as Tiger Stripe whatever you write (slots 1–4 are unaffected; see Known limitations).
> And its name field holds a
> maximum of **15 characters**. A longer `Name=` is ignored rather than cut short and the row falls
> back to `ACF Mod 5`. Slots 61–64 have no such limit.

To name your slot, describe it and give it a real camouflage value, ship a plain text file beside
your pak at `Content/Paks/mods/ACF_Slot<ID>.txt`:

```
Name=Ocelot's Uniform
PlainDesc=Worn by the young Ocelot.
AbilityDescOrange=Draws faster from the hip.
BaseCamo=0
```

Ready-made templates are in [docs/modder_templates/](docs/modder_templates/), one per slot. Run
`acfslots` in the console to see exactly what ACF read from your file, and to be told about any
line it could not parse.

Full guide, including the asset-rename trap that silently overrides the asset you cloned:
**[docs/MODDERS.txt](docs/MODDERS.txt)**

---

## Status

Latest release is **v2.0**.

| | |
|---|---|
| Slots | 5 (camo IDs 61–65) |
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

Slot 5 resolves differently. That table's rows are keyed by uniform name and it has no row for the
DOWNLOAD slot, so the lookup returns nothing and the game prints the uniform's own name — which is
literally `UNLOCKED`. Adding a live entry under that key is all it needs, and the 15-character
limit comes from the buffer behind that word.

### Icons

Each slot already ships placeholder badge art as a numerically-named texture, and ACF overrides
those textures. It works where earlier attempts failed because it **overrides an asset the cooked
`AssetRegistry` already knows about**. Genuinely new assets are not resolvable by name in this
game, which is the limitation that shaped the whole design.

Two constraints follow, and both took a while to learn. The texture has to be one the game
**already loads** — the row stores a hard `UObject` pointer, not a path, so an unused texture can
never be used no matter how correctly it is packed. And every slot needs its **own** number even
where the art is identical, or replacing one slot's thumbnail would change another's.

### Getting a fifth slot at all

The Survival Viewer's list builder had id 65 hardcoded as a skip, and a loop bound of 66. ACF
patches both, after verifying every byte site against what was mapped so a game update degrades
this to a log line rather than corrupted code. The slot's resource record also ships
uninitialised — 61–64 all share one generic record — so ACF copies slot 64's across.

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

- **Five slots.** Four are the reserved uniform entries the game already knows about; the fifth is
  the DOWNLOAD slot, which the Survival Viewer's list builder explicitly skipped until ACF patched
  it out. Beyond that the game's own tables run out: ids 66–69 are missing from the resource map
  entirely, and the uniform value table holds exactly 70 entries with a live global immediately
  after it, so going further means relocating that table rather than extending it.
- **Slot 5 ignores `BaseCamo` and per-terrain values.** ACF reads them from the file correctly, and
  the game overrides them: slot 5 conceals as Tiger Stripe regardless of what an author writes.
  Measured — a grid set to 31/41/51 on brown soil returned Tiger Stripe's 30/60/75, and `BaseCamo`
  contributed nothing. **Slots 1–4 are unaffected and work correctly.** The cause is not yet known.
  Everything else on slot 5 works, because the abilities read the uniform byte directly rather than
  through the concealment table: name, description, thumbnail, `INFAmmoFlag`, `INFAmmoWeapon`,
  `AnimalsSA`, `INFSuppressor` and `SilentSteps` all behave as on slots 1–4. Use slots 1–4 if
  concealment matters to your mod.
- **Slot 5's name is capped at 15 characters.** It borrows a menu row the game only ever labelled
  `UNLOCKED`, and the buffer behind that word holds 15 and no more. A longer name is ignored rather
  than truncated. Slots 1–4 have no such limit.
- **Collisions are silent.** Two mods on the same slot means one disappears, with no error — though
  ACF does warn in the log when two `ACF_Slot<ID>.txt` files claim the same slot.
- **A slot with no metadata file keeps a generic name** (`ACF Mod 1`–`5`). That is the fallback, not
  a limitation — authors supply their own via `ACF_Slot<ID>.txt`.
- **Several documented metadata keys do nothing yet** — the movement, health and recovery
  multipliers. They are listed in the modder template so the file format does not have to change
  when they arrive, and ACF ignores them today. (The five ability keys — `INFAmmoFlag`,
  `INFAmmoWeapon`, `AnimalsSA`, `INFSuppressor` and `SilentSteps` — have since been implemented and
  do work.)
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

- **More than five slots.** The fifth is done. Past it the game's tables run out: ids 66–69 are
  absent from the resource map, and the uniform value table holds exactly 70 entries with a live
  global immediately after it, so going further means relocating that table rather than extending
  it. Ids 66 and 67 are not candidates in any case — 66 was a sentinel value and 67 is a cardboard
  box the player owns from the start.
- **Automatic slotting**, so an author ships one mod instead of five slot variants and ACF assigns
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
