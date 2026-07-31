ACF slot metadata templates
===========================

These four files are the source of truth for the "ACF Config Files for Modders"
download published on the ACF Nexus page under Miscellaneous Files. If you change
one here, re-zip and re-upload so the two do not drift apart.

A mod author takes the file matching the slot they are using, drops it next to
their pak in Content\Paks\mods\, and edits the three lines at the top:

    Name=          shown in the Survival Viewer and the Camouflage Collection
    Description=   shown in both menus
    BaseCamo=      a real camouflage value, added to the index the game computes

Everything below those in the file is DELIBERATELY NOT SUPPORTED YET - special
effects, movement and health multipliers, and the per-terrain values such as
CamoWater and CamoGrass. They are written down so the format does not have to
change when those features arrive. ACF ignores them, and leaving them in a file
causes no harm.

The key is BaseCamo, not Camo. It was renamed before the templates were first
published, to keep the flat value distinct from the per-terrain CamoWater /
CamoGrass / CamoRoomBlue family listed in the same file. There is no fallback to
the old name: a file using Camo= will have its value silently ignored, which is
exactly the confusion the rename avoids.

Per-terrain note for whoever implements it later: the game has 27 background
types and five stance variants each, so a full per-camo block is 135 bytes. The
template lists 24 of the 27 - NO_CAMOUFLAGE, ROOM_NO_CAMOUFLAGE and
OBJ_OLIVEGREEN are absent. The first two are "nothing matches here" defaults and
are reasonable to leave out; OBJ_OLIVEGREEN looks like an oversight and should
probably be added when the feature lands.
