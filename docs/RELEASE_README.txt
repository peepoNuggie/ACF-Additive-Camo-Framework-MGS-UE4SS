================================================================================
  ACF - Additive Camo Framework  v2.0
  Metal Gear Solid Delta: Snake Eater
================================================================================

ACF adds new camouflage slots to the game instead of replacing existing ones.

Camo mods normally overwrite a vanilla uniform's textures, so you lose the
original and can only ever run one such mod at a time. ACF gives modders five
genuinely new slots, so their camo sits alongside every vanilla one - selectable
in the Survival Viewer and displayed in the Camouflage Collection, with nothing
overwritten.

ACF on its own adds five EMPTY slots. You also need camo mods that support it.


--------------------------------------------------------------------------------
NEW IN v2.0
--------------------------------------------------------------------------------

A FIFTH SLOT. ACF had four; it now has five. The fifth is a slot the game itself
reserved and then never finished - its equip menu skipped the entry outright, so
it could not be selected at all until ACF patched that out. It lists, equips,
renders, unlocks itself and takes an author's name, description and thumbnail
exactly like the others.

One caveat, and it is worth reading if you are choosing a slot: slot 5 ignores
the concealment values a mod author sets. It conceals as Tiger Stripe whatever
the mod asks for. Slots 1 to 4 are unaffected. Everything else on slot 5 works.
This is a known issue and is being worked on.

REAL PER-TERRAIN CAMOUFLAGE. A slot used to have one concealment number applied
everywhere. It can now have a different value for each of the 27 surfaces the
game recognises AND each of five stances - which is how vanilla camos actually
work, and why Water works underwater and going prone in grass helps. A mod can
now be genuinely good in the swamp and genuinely bad on snow, instead of being
uniformly better or worse than bare skin.

TWO NEW ABILITIES a camo mod can grant:

  * INFSuppressor - your suppressor never wears out
  * SilentSteps   - your footsteps make no noise

Both mirror abilities vanilla camos already have, so neither is new to the game -
they are simply available to modded slots now. That brings the total to five,
alongside infinite ammo for all weapons, infinite ammo for chosen weapons, and
the steady aim that Animals camo gives.

As always, none of this needs anything from you. Mods that use these features
get them; mods that do not behave exactly as before.


--------------------------------------------------------------------------------
NEW IN v1.1
--------------------------------------------------------------------------------

A slot can now present the mod filling it, instead of a generic label. If the
camo mod you install ships an ACF_Slot<ID>.txt file, its author can set:

  * the NAME shown in both menus, instead of "ACF Mod 1"
  * the DESCRIPTION shown beneath it
  * the CAMOUFLAGE VALUE - a real one, not a label

The camouflage value is the significant one. It is added to the camouflage index
the game calculates, so terrain, stance and grass still apply on top exactly as
they do for a vanilla camo. A slot that claims to hide you better actually does,
and guards react accordingly.

None of this requires anything from you. Mods that ship the file get it; mods
that do not keep the old generic behavior.


--------------------------------------------------------------------------------
REQUIREMENTS
--------------------------------------------------------------------------------

  * Metal Gear Solid Delta: Snake Eater (Steam)

  * UE4SS  -  the "experimental-latest" download, NOT the tagged 3.0.1 release
        https://github.com/UE4SS-RE/RE-UE4SS/releases

        ACF was built and tested against UE4SS v3.0.1 Beta #0, git SHA c838a8ac.
        "experimental-latest" is a rolling build, so a newer download may behave
        differently. The version and SHA are printed at the top of UE4SS.log -
        please include them in any bug report.

  * MGS Delta UE4SS Fix  (REQUIRED - UE4SS does not work in this game without it)
        https://github.com/mattdavida/MGS-Delta-UE4SS-Fix

        Stock UE4SS cannot locate the engine's object array in MGS Delta. This
        fix supplies the signature it needs. Copy its UE4SS_Signatures folder to:

            MGSDelta\Binaries\Win64\ue4ss\UE4SS_Signatures\

        so you end up with ...\ue4ss\UE4SS_Signatures\GUObjectArray.lua

Install UE4SS and the fix together, and confirm the UE4SS console appears when
you launch the game, BEFORE installing ACF. If the console does not appear, ACF
will not run either - fix that first.

Prefer to skip all of this? Download the all-in-one bundle instead: it includes
UE4SS and the fix, already configured.


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

3. Launch the game and load a save. The five slots appear on their own - there
   is nothing to run and no console command to type.


--------------------------------------------------------------------------------
WHAT YOU SHOULD SEE
--------------------------------------------------------------------------------

Survival Viewer  ->  Camouflage  ->  Uniform tab
    Five entries at the bottom of the list: ACF Mod 1 through ACF Mod 5.

Main Menu  ->  Extras  ->  Camouflage Collection
    The same five entries.

With no camo mods installed, selecting one shows Olive Drab. That is correct -
the slot exists but nothing has filled it yet.

Once a camo mod that supports ACF is installed, its slot may show the author's
own name, description and camouflage value in place of the generic entry. That
depends on the mod shipping an ACF_Slot<ID>.txt file; not every mod will.


--------------------------------------------------------------------------------
INSTALLING A CAMO MOD THAT SUPPORTS ACF
--------------------------------------------------------------------------------

Follow that mod's own instructions. Its files go in Content\Paks\mods\ alongside
ACF's.

Each mod occupies ONE numbered slot (1 to 5). ACF has five slots in total - that
is a hard limit of the game, not a choice.

  * If two mods use the same slot, only one of them will appear. Whichever pak
    the game loads last wins, and there is no error message.
  * Check which slot a mod uses before installing it, and do not install two
    mods that use the same one.
  * Some mod authors provide alternate downloads for different slots.


--------------------------------------------------------------------------------
KNOWN ISSUES
--------------------------------------------------------------------------------

  * Five slots is the total, and collisions are silent - if two mods target the
    same slot, one simply does not appear.

  * A slot only shows a custom name, description and camouflage value if the mod
    filling it ships an ACF_Slot<ID>.txt. Otherwise it stays "ACF Mod N" with no
    camouflage bonus. That is the mod's choice, not a fault in ACF.

  * SLOT 5 IGNORES THE CONCEALMENT VALUES a mod sets. It conceals as Tiger Stripe
    whatever the mod asks for. Slots 1 to 4 are unaffected and honour both the
    flat value and the per-terrain grid. Everything else on slot 5 works normally.
    Being worked on.

  * Rarely, hovering a slot in the Survival Viewer briefly shows another camo's
    model. Cosmetic only; the camo you equip is unaffected.

  * Camo-related achievements are UNTESTED. Use at your own discretion.

  * A rare crash when switching camouflage was seen during development. It has
    not recurred since a fix, but it was never conclusively proven fixed. You may
    see a "Fatal Error" window - you can sometimes keep playing and saving as
    long as you do not dismiss it. UE4SS will write a crash dump.
    Please report it with UE4SS.log attached.

  * The mod includes developer console commands, listed by typing acfhelp. They
    are diagnostic tools, not features. The ones marked SLOW in that list arm
    memory traps and will make the game stutter badly until you run
    "svwatch off" - that is expected, not a bug. Please do not report issues
    caused by running them.


--------------------------------------------------------------------------------
UNINSTALLING
--------------------------------------------------------------------------------

Delete the files listed in step 1, and remove the two lines from mods.txt.

Saves made while ACF was installed keep the five slots listed in your menus even
after removal. They are harmless - selecting one just shows Olive Drab - but
they will not disappear on their own. Reinstalling ACF makes them work again.


--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------

No UE4SS console window at all
    Either UE4SS is not installed correctly, or the MGS Delta UE4SS Fix is
    missing. Confirm this file exists:

        MGSDelta\Binaries\Win64\ue4ss\UE4SS_Signatures\GUObjectArray.lua

    Without it UE4SS cannot start properly in this game, and nothing that
    depends on it - including ACF - will load.

Console appears, but nothing from ACF
    Almost always the mods.txt step. Check both lines are present and spelled
    exactly as above.

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

See MODDERS.txt for how to build a camo that targets an ACF slot, including how
to give it your own name, description and camouflage value.

Ready-made metadata templates are on the ACF Nexus page under MISCELLANEOUS
FILES, as "ACF Config Files for Modders".


--------------------------------------------------------------------------------
CREDITS AND NOTES
--------------------------------------------------------------------------------

ACF does not replace, overwrite or modify any vanilla camouflage.

It does override six small UI assets the base game ships but never uses: the five
placeholder thumbnails for its own unused reserved uniform slots, and the table
holding their placeholder names. Nothing reachable in normal play is affected,
and deleting ACF restores them exactly.
