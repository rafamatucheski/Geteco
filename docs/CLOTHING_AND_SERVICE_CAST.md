# Clothing and service cast

HarborClothingShops binds the north frontage at District/NorthFrontage3 and the
existing SnowOutfitters after the mountain tunnel to separate ClothingRoom3D
rooms under the existing interior manager. This reuses its door sensors, camera,
exterior return, police exterior marker and dialogue input locking. The minimap
draws shirt icons for these entrances. The old F-key invisible thermal upgrade
is replaced by the actual clothing catalog.

OutfitCatalog.cold_protection is shared by ClothingStore and the mountain cold
controller: arctic .8, trench .6, lumberjack .35, classic .15, lighter clothes
.0–.25. Changing clothes updates the thermal flag. Existing saved legacy coat
flags remain supported until the player changes outfit. Protection reduces
temperature drain and does not restore heat. Both interior metadata types count
as shelter. Existing outfit ownership and equipped-id save fields remain in use.

Citizen and winter hood silhouettes were tightened. ServiceUniformDetails adds
face, proportions, radio, pockets and role-specific details to the actual police,
firefighter and paramedic rigs. Civilian drivers vary their clothing/proportions;
ejected taxi drivers additionally wear a work cap and identification badge.
This is incremental mesh detailing, not a full replacement of every rig.

Tests: test_clothing_shops runs the actual world and mountain loading, purchase,
equip, money, protection drain, and both interior returns. Real Vulkan screenshot
is D:/geteco/clothing-shop-interior.png. test_harbor_citizen_routines and
test_police_fair_arrest also pass. Long play sessions and every legacy shop scene
are not covered. The existing ObjectDB teardown warning still occurs in some runs.
