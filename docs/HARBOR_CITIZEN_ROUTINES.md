# Harbor citizens and foot patrols

The six central blocks now use closed sidewalk circuits. Three additional
itineraries join pairs of blocks through crossings resolved from the live road
graph. Open routes in neighboring districts retain their existing behavior;
they must not be closed blindly across buildings or carriageways.

Harbor walkers use six civilian archetypes, extra facial/clothing pieces, four
hair variants and additional silhouette variation. Paired residents share a
direction and slow down when their companion falls behind. These accessories
use the existing articulated rig and viewport culling; they add no physics bodies.

At a crossing, pedestrians request passage, wait for permission and check nearby
vehicle motion before committing. A pedestrian already on the road finishes
crossing if the phase changes. This does not guarantee protection against a
player deliberately accelerating into an occupied crossing.

Two real PoliceOfficer-derived patrols walk the central sidewalks. A reported
crime or a wanted suspect entering the 430-pixel police sight range requires
unobstructed sight before engagement. Existing warning, surrender duration and
armed-response rules apply. A patrol already on the street checks for an active
wanted suspect four times per second, while a new crime still triggers an
immediate check. Sight loss for eight seconds or cleared wanted status ends the
engagement.
No civilian wearing a cosmetic police uniform is spawned by the HarborWalker pool.

Validation: tests/test_harbor_citizen_routines.gd loads the actual world, checks
closed-route wrap, 14 graph-derived connections, 32 loop walkers, two officers,
crime perception with/without a wall, red/green crossing entry and committed
crossing completion. Its screenshot is a staged lineup of runtime citizen rigs.
tests/test_police_fair_arrest.gd also passes. Long-duration congestion and full
district traversal are not covered by these checks. The world retains its known
ObjectDB teardown warning; the editor scan also reports unrelated malformed
LandmarksV2.tscn and FleetShowcasePhase2.tscn prototype scenes.
