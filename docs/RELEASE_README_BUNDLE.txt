================================================================================
  ACF - Additive Camo Framework  v1.0   [ALL-IN-ONE BUNDLE]
  Metal Gear Solid Delta: Snake Eater
================================================================================

This bundle contains ACF, UE4SS, and the MGS Delta UE4SS Fix, already set up.
Extract it and play - there is nothing to install or configure.


  >>> ALREADY HAVE UE4SS OR OTHER MODS INSTALLED?  DO NOT USE THIS BUNDLE. <<<

  It replaces mods.txt, which is the file that lists your enabled UE4SS mods.
  Extracting this over an existing setup will turn your other mods off.

  Download the standalone ACF archive instead - it contains only ACF and tells
  you which two lines to add to your own mods.txt.


--------------------------------------------------------------------------------
WHAT ACF DOES
--------------------------------------------------------------------------------

Camo mods normally overwrite a vanilla uniform's textures, so you lose the
original and can only run one at a time. ACF adds four genuinely NEW camouflage
slots, so a modded camo sits alongside every vanilla one - selectable in the
Survival Viewer, shown in the Camouflage Collection, with nothing overwritten.

ACF by itself adds four EMPTY slots. You also need camo mods that support it.


--------------------------------------------------------------------------------
INSTALLING
--------------------------------------------------------------------------------

1. Extract this archive into your game folder, so the "MGSDelta" folder in the
   archive lands on top of the "MGSDelta" folder already there. Typically:

       ...\steamapps\common\MGSDelta\

2. Launch the game and load a save.

That is all. UE4SS, the MGS Delta UE4SS Fix, the configuration and ACF are all
included and enabled.

A small console window opens alongside the game - that is UE4SS, and it is
normal. Closing it closes the game.


--------------------------------------------------------------------------------
WHAT YOU SHOULD SEE
--------------------------------------------------------------------------------

Survival Viewer  ->  Camouflage  ->  Uniform tab
    Four entries at the bottom: ACF Mod 1 through ACF Mod 4.

Main Menu  ->  Extras  ->  Camouflage Collection
    The same four entries.

With no camo mods installed, selecting one shows Olive Drab. That is correct -
the slot exists but nothing has filled it yet.


--------------------------------------------------------------------------------
INSTALLING A CAMO MOD THAT SUPPORTS ACF
--------------------------------------------------------------------------------

Follow that mod's own instructions. Its files go in Content\Paks\mods\ next to
ACF's.

Each mod takes ONE slot (1 to 4). Four is the total - a hard limit of the game,
not a choice.

  * If two mods use the same slot, only one appears. The pak the game loads last
    wins, silently, with no error.
  * Check which slot a mod uses before installing, and avoid installing two that
    use the same one.
  * Some authors offer alternate downloads for different slots.


--------------------------------------------------------------------------------
KNOWN ISSUES
--------------------------------------------------------------------------------

  * Four slots is the total, and collisions are silent - if two mods target the
    same slot, one simply does not appear.

  * Slot names are generic (ACF Mod 1-4), not the name of the mod filling them.

  * Camouflage percentage is not configurable yet - every ACF slot uses the
    default rather than a value the mod author picks.

  * Camo-related achievements are UNTESTED. Use at your own discretion.

  * A rare crash when switching camouflage was seen during development. It has
    not recurred since a fix, but it was never conclusively proven fixed. You may
    see a "Fatal Error" window - you can sometimes keep playing and saving as
    long as you do not dismiss it. UE4SS will write a crash dump.
    Please report it with UE4SS.log attached.

  * The mod ships with undocumented developer console commands. They are
    unsupported, and a couple misbehave - please do not report bugs from them.


--------------------------------------------------------------------------------
UNINSTALLING
--------------------------------------------------------------------------------

Delete these from your game folder:

    MGSDelta\Binaries\Win64\dwmapi.dll
    MGSDelta\Binaries\Win64\ue4ss\          (whole folder)
    MGSDelta\Content\Paks\mods\ACF_Names_P.*
    MGSDelta\Content\Paks\mods\ACF_SvThumb_P.*

Saves made while ACF was installed keep the four slots listed in your menus even
after removal. They are harmless - selecting one shows Olive Drab - but they do
not disappear on their own. Reinstalling ACF makes them work again.


--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------

No console window, nothing in game
    dwmapi.dll is missing or in the wrong place. It belongs in
    MGSDelta\Binaries\Win64\ next to MGSDelta-Win64-Shipping.exe, NOT inside the
    ue4ss folder.
    Some antivirus software quietly removes it - check your quarantine.

Console opens but no ACF slots
    Check MGSDelta\Binaries\Win64\ue4ss\Mods\mods.txt still contains
    "ACF : 1" and "ACF-CPP : 1".

Slots show "-IT_EqAdditionalUniform2-2" instead of "ACF Mod 1"
    ACF_Names_P is missing or incomplete. Its .pak, .ucas and .utoc must all be
    present - a pak missing one of the three silently does nothing.

Slots show letter badges (U.H, U.I) instead of the ACF icon
    ACF_SvThumb_P is missing or incomplete. Same fix.

Anything else
    UE4SS writes MGSDelta\Binaries\Win64\ue4ss\UE4SS.log - lines from this mod
    are tagged [ACF]. Include it in a bug report.


--------------------------------------------------------------------------------
CREDITS AND LICENCE
--------------------------------------------------------------------------------

UE4SS is included under the MIT licence - see UE4SS-LICENSE.txt.
    https://github.com/UE4SS-RE/RE-UE4SS

The MGS Delta UE4SS Fix by mattdavida is included - the signature UE4SS needs to
find the engine's object array in this game. UE4SS does not work here without it.
    https://github.com/mattdavida/MGS-Delta-UE4SS-Fix

The bundled ConsoleCommandsMod\Scripts\dump_object.lua carries a small local fix
(a crash when dumping certain bool properties) and so differs from the official
UE4SS release.

ACF does not replace, overwrite or modify any vanilla camouflage.

It does override four small UI assets the base game ships but never uses - the
placeholder name and icon for its own unused reserved uniform slots. Nothing
reachable in normal play is affected, and removing ACF restores them exactly.

For mod authors: see MODDERS.txt.
