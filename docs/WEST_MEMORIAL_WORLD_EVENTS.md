# Westgate memorial and autonomous incidents

The cemetery is now centered at (-650, 1740), in its own 780 × 700 plot west of Harbor. Three road segments join Market Street and Dock Street through a western loop. The old western collision boundary was extended with the land. No scene transition is involved. Road geometry remains in HarborRoadLayout, so ambient lanes and the minimap use the same definitions.

The lot has 36 decorative tombs, 14 trees, benches, a central aisle and solid perimeter walls with a northern gate. The existing mortician API remains available. The letter collectible uses Player.collectibles_found, and is included in CollectibleCatalog.

HarborWorldEvents runs on game time, independently of player proximity. Five mourners walk in, pause for a 25-second ceremony, then walk out. Subsequent ceremonies wait 180–320 seconds. One city incident can run alongside one ceremony; incidents wait 100–180 seconds between attempts. A failed dispatch defers the occurrence instead of creating extra emergency vehicles.

Incidents currently use authored locations: a bag theft near the laundry with a fleeing pedestrian, and a refuse-bin fire near the freight depot. Event selection and timing are random. Both call the real depot director/pool. Ambient crimes belong to their NPC target, do not add player stars, and can be arrested without arresting Dante. The NPC representation is lightweight; it is not a citywide economy or persistent population simulation.

Completed incidents release their targets; the existing crew/vehicle return logic handles the service units. Events have a 150-second lifetime cap. Resident visual updates are culled at distance while movement and event clocks continue.

Validation: test_cemetery_world_events.gd covers road/gate clearance, actual guest movement, ceremony/departure lifecycle, real service dispatch, incident budget and no player wanted changes. test_police_fair_arrest.gd also checks arresting an ambient suspect instead of Dante. capture_cemetery_location.gd captures the actual Vulkan scene and the ceremony. No player save slots are written.
