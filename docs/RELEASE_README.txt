================================================================================
  ACF - Additive Camo Framework  v1.0
  Metal Gear Solid Delta: Snake Eater
================================================================================

ACF adds new camouflage slots to the game instead of replacing existing ones.

Camo mods normally overwrite a vanilla uniform's textures, so you lose the
original and can only ever run one such mod at a time. ACF gives modders four
genuinely new slots, so their camo sits alongside every vanilla one - selectable
in the Survival Viewer and displayed in the Camouflage Collection, with nothing
overwritten.

ACF on its own adds four EMPTY slots. You also need camo mods that support it.


--------------------------------------------------------------------------------
REQUIREMENTS
--------------------------------------------------------------------------------

  * Metal Gear Solid Delta: Snake Eater (Steam)
  * UE4SS  -  https://github.com/UE4SS-RE/RE-UE4SS/releases
             Install and confirm it works before installing ACF.
             If the UE4SS console does not appear in game, ACF will not run.


--------------------------------------------------------------------------------
INSTALLING
--------------------------------------------------------------------------------

1. Extract this archive into your game folder, so that "MGSDelta" in the archive
   lands on top of the "MGSDelta" folder already there. Typically:

       ...\steamapps\common\MGSDelta\

   You should end up with:

       MGSDelta\Binaries\Win64\ue4ss\Mods\ACF-CPP\dlls\main.dll
       MGSDelta\Binaries\Win64\ue4ss\Mods\ACF\scripts\main.lua
       MGSDelta\Content\Paks\mods\ACF_Names_P.pak   (+ .ucas and .utoc)
       MGSDelta\Content\Paks\mods\ACF_SvThumb_P.pak (+ .ucas and .utoc)

   The .pak, .ucas and .utoc files travel together. If you copy only some of
   them, that pak will silently do nothing.

2. Open this file in a text editor:

       MGSDelta\Binaries\Win64\ue4ss\Mods\mods.txt

   Add these two lines at the end:

       ACF : 1
       ACF-CPP : 1

   Without them UE4SS will not load ACF at all. This is the step people miss.

3. Launch the game and load a save. The four slots appear on their own - there
   is nothing to run and no console command to type.


--------------------------------------------------------------------------------
WHAT YOU SHOULD SEE
--------------------------------------------------------------------------------

Survival Viewer  ->  Camouflage  ->  Uniform tab
    Four entries at the bottom of the list: ACF Mod 1 through ACF Mod 4.

Main Menu  ->  Extras  ->  Camouflage Collection
    The same four entries.

With no camo mods installed, selecting one shows Olive Drab. That is correct -
the slot exists but nothing has filled it yet.


--------------------------------------------------------------------------------
INSTALLING A CAMO MOD THAT SUPPORTS ACF
--------------------------------------------------------------------------------

Follow that mod's own instructions. Its files go in Content\Paks\mods\ alongside
ACF's.

Each mod occupies ONE numbered slot (1 to 4). ACF has four slots in total - that
is a hard limit of the game, not a choice.

  * If two mods use the same slot, only one of them will appear. Whichever pak
    the game loads last wins, and there is no error message.
  * Check which slot a mod uses before installing it, and do not install two
    mods that use the same one.
  * Some mod authors provide alternate downloads for different slots.


--------------------------------------------------------------------------------
UNINSTALLING
--------------------------------------------------------------------------------

Delete the files listed in step 1, and remove the two lines from mods.txt.

Saves made while ACF was installed keep the four slots listed in your menus even
after removal. They are harmless - selecting one just shows Olive Drab - but
they will not disappear on their own. Reinstalling ACF makes them work again.


--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------

Nothing appears at all
    Almost always the mods.txt step. Check both lines are present and spelled
    exactly as above.
    Then check UE4SS itself is working - its console should open in game.

The slots are there but a camo mod does not show
    Confirm the mod supports ACF and which slot it uses. Confirm all three of
    its pak files (.pak, .ucas, .utoc) were copied.
    If two mods share a slot, one will be invisible.

Slots show "-IT_EqAdditionalUniform2-2" instead of "ACF Mod 1"
    ACF_Names_P is missing or incomplete. Copy all three of its files.

Slots show letter badges (U.H, U.I) instead of the ACF icon
    ACF_SvThumb_P is missing or incomplete. Same fix.

Anything else
    UE4SS writes a log to MGSDelta\Binaries\Win64\ue4ss\UE4SS.log - lines from
    this mod are tagged [ACF]. Include it in a bug report.


--------------------------------------------------------------------------------
FOR MOD AUTHORS
--------------------------------------------------------------------------------

See MODDERS.txt for how to build a camo that targets an ACF slot.


--------------------------------------------------------------------------------
CREDITS AND NOTES
--------------------------------------------------------------------------------

ACF does not replace, overwrite or modify any vanilla camouflage.

It does override four small UI assets that the base game ships but never uses -
the placeholder name and icon for its own unused reserved uniform slots. Nothing
reachable in normal play is affected, and deleting ACF restores them exactly.
