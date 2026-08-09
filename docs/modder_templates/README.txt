ACF slot metadata templates
===========================

These five files are the source of truth for the "ACF Config Files for Modders"
download published on the ACF Nexus page under Miscellaneous Files. If you change
one here, re-zip and re-upload so the two do not drift apart.

Release\ACF_Slots_Config\ holds a working copy of the same five files, and the
v2.0 zip was built from there. The two are byte-identical as of that build - keep
them that way, and prefer editing here since only this folder is in git.

A mod author takes the file matching the slot they are using, drops it next to
their pak in Content\Paks\mods\, and edits it. Every key is documented inside the
file itself; the templates are meant to be read top to bottom by someone who has
never seen the format before, so the comments carry the explanations rather than
this README.


What the templates cover as of v2.0
-----------------------------------

  Name / PlainDesc / AbilityDescOrange / WarningDesc / SpecialDesc
  BaseCamo                    one flat value applied everywhere
  Camo<Surface>               27 surfaces x 5 stances, the real per-terrain grid
  INFAmmoFlag                 infinite ammo, every weapon
  INFAmmoWeapon               infinite ammo, only the weapons named
  AnimalsSA                   steady aim
  INFSuppressor               suppressor never wears out
  SilentSteps                 silent footsteps

Still listed but NOT read by ACF: the movement, health and life-recovery
multipliers at the bottom of each file. They are written down so the format does
not have to change when those features arrive, and leaving them in causes no harm.


Things that bite, and are easy to undo by accident
--------------------------------------------------

NO TRAILING COMMENTS. Only lines that START with ; or # are ignored. A comment
after a value becomes part of the value, and the ability flags scan for any digit
1-9 - so "INFAmmoFlag=0  ; set to 1 to enable" reads as ON. An earlier draft of
these templates shipped exactly that mistake on every ability.

THE KEY IS BaseCamo, NOT Camo. Renamed before the templates were first published,
to keep the flat value distinct from the per-terrain CamoWater / CamoGrass /
CamoRoomBlue family in the same file. There is no fallback to the old name: a
file using Camo= has its value silently ignored, which is exactly the confusion
the rename avoids.

ALL 27 SURFACES ARE PRESENT. Earlier templates listed 24 - NO_CAMOUFLAGE,
ROOM_NO_CAMOUFLAGE and OBJ_OLIVEGREEN were missing. The first two are "nothing
matches here" defaults and stay out deliberately; OBJ_OLIVEGREEN was an oversight
and is now in as CamoObjOliveGreen. A full per-camo block is 135 bytes: 27
backgrounds x 5 stance variants.


Slot 65 is not the same as the other four
-----------------------------------------

ACF_Slot65.txt carries a caveat block the others do not, covering two real
differences on that slot:

  * Concealment values do not apply. ACF reads BaseCamo and the grid correctly and
    the game overrides them - slot 5 conceals as Tiger Stripe regardless. Known
    issue, cause not yet found. Everything else on the slot works.
  * Name is capped at 15 characters. The slot borrows a menu row the game only
    ever labelled "UNLOCKED", and the buffer behind that word holds 15. A longer
    name is ignored rather than truncated and the row falls back to "ACF Mod 5".

If either changes, that block is the thing to update - it is the only part of the
five files that is not identical apart from the slot number.
