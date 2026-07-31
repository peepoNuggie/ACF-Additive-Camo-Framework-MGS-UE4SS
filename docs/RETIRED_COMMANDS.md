# Retired ACF diagnostics

Two archives, both from 2026-07-31, both kept verbatim with original line numbers:

- [`retired_commands.lua`](retired_commands.lua) — 35 console commands removed from `main.lua`.
  Never loaded.
- [`retired_cpp_diagnostics.txt`](retired_cpp_diagnostics.txt) — the C++ side: whole namespaces
  (`GaugeTrace`, `LegacyData`, `CamoSource`), several probe functions, and the bridge branches that
  served the retired commands. Not compiled.

The C++ removals mattered more than tidiness. `GaugeTrace` registered a **global ProcessEvent
callback** with UE4SS and is the prime suspect for a hot-reload crash that appeared while it was
installed; `LegacyData` held a live detour on the legacy data dispatcher that every query in the
game passes through. Neither earned its keep once P3 was solved.

They were removed because the questions they existed to answer are settled, not because they were
sloppy. Several are recorded here specifically as **negative results**: knowing that a mechanism is
*not* how the game works saved days, and would be lost if the code simply vanished.

Nothing here is needed to run ACF. What remains in `main.lua` is the 25 commands that either serve
players, or are still the fastest way to diagnose a real bug report.

---

## Retired because the mechanism turned out not to be the one the game uses

These are the valuable ones. Each proves a dead end.

| command | what it tried | why it is retired |
|---|---|---|
| `findunlock` | hunt the game's own "acquire camo" function so unlocking could go through it | No such reachable function. Ownership is a flag in the legacy store at `state + 0x3E84`, written directly. |
| `svcheck` | work out which save field drives the Survival Viewer | It is none of the UE-side save fields. The viewer reads the legacy store. |
| `findsavefuncs` | find what flushes the profile to disk, to persist edits | Abandoned with save-file editing entirely — the game rejects an edited `.sav`. |
| `unlockcamo`, `unlocknew`, `unlockindex`, `unlockviewerkey`, `unlockcamoflag`, `unlockcamovanillacmd`, `checksave` | seven different ways to unlock a camo through UE-side save data | All superseded. ACF unlocks automatically: C++ writes the legacy store, Lua writes `UnlockCamouflageMap`. `unlockcamovanillacmd` calls the game's own `UnlockAllCamouflage`, which is a no-op. |
| `svcap` | call the menu's `GetCaptionText` / `GetCaptionExplainText` to find the description source | Answered P2. The description is built from a hardcoded switch in `FUN_145289f40`, not from data. |
| `svexplain` | hook that UFunction and answer for ACF's rows | **Proved a hook cannot work.** It fired 12 times for Lua calls and never once while the menu drew — the widget reaches the native function directly. Worth remembering before hooking any menu UFunction. |
| `camoval` | read the live camouflage percentage from the struct the debug printer uses | That struct at `+0xCD4` is a debug mirror the shipping build never fills. Exactly one instruction in the binary touches it — the debug printer's own read. |
| `camobase` | read the camo base value off the save state at `+0x2F88` | Wrong object. `+0x2F88` belongs to the *player* object, and even there it is not the base. |
| `findcamo` | search the running game for the per-camo value table | Superseded by `camotable`. What it found was a menu-filled buffer, not the table — index 0 read 0 where Olive Drab must be 10. |
| `svarena` | follow the pointers in each camo record into the legacy data arena | The arena is a resource *string* table — path and short name per camo, no numeric field. |
| `findtex` | test whether a brand-new texture package can be loaded | Answered; thumbnails ship as an in-place override pak instead. |
| `tryload` | test whether each `Camouf_<id>_asset` can be loaded | Answered, and the asset-redirect detour handles the gap now. |

## Retired as one-off discovery tools

Used once to find a class, offset or function that is now recorded in the code.

`registerhooks`, `realequip`, `realequip2`, `findcamowidget`, `findcamocollection`,
`findrealclasspaths`, `scanprobe`, `findassethelper`, `dumpfunc`, `findsortdatatable`,
`getcamobyindex`, `findtabview`, `findpropfunc`, `findbuttons`, `findcamotabview`,
`refreshcamomenu`

Two are worth a note:

- **`hookbuttoncreate`** — tried to hook widget construction to catch rows being built. Never fired:
  creation is native, not Blueprint. Same lesson as `svexplain`.
- **`findpropfunc`** — how we established that `Find*`/`Get*` row functions live on
  `CSVTabViewWidget` and not `CPropMenuBaseState`. That fact is now a comment in `main.lua`.

---

## What replaced them

| retired area | what does the job now |
|---|---|
| unlocking (7 commands) | automatic — C++ `LiveStore` plus the Lua collection-unlock timer |
| finding the camo value | `camotable`, which dumps the game's real per-camo table |
| row/name inspection | `svrows` and `acfslots` |
| description hunting | settled; ACF detours `FUN_145289f40` |

## Commands kept

Player-facing: `acfhelp`, `acfslots`, `svrows`, `camotable`.

Everything else in `main.lua` is a developer tool. Some are genuinely disruptive — `svwatch` and
`svread` arm page traps and will make the game stutter badly — so they are worth gating behind a
dev marker before release rather than leaving in a player's reach.
