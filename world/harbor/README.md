# Breakwater — isolated harbor district

Open `res://world/harbor/HarborPreview.tscn` in Godot and press **F6**.
The existing main menu and districts are not replaced. No commit is made by this task.

## Explore

- Start in an overview; choose **Explorar a pé** or **Dirigir**.
- WASD: walk/drive; Shift: sprint; E: normal vehicle entry/exit.
- Tab: overview / active player camera.
- 1: market, 2: civic neighborhood, 3: waterfront, 4: Northbank,
  5: railway viaduct, 6: tunnel, 7: pedestrian alleys, 8: local streets,
  9: Map 2 highway, N: northern expansion, 0: full overview.
- T: follow the actual train; the camera holds at the portal while it is underground.
- Mouse wheel and middle-button drag: inspect the overview.
- The **Dirigir** button is a review shortcut: it places the player next to the
  preview car and calls the existing vehicle-entry implementation.
- **Ir ao cais** is another review shortcut: it places the player on land at the
  ship-access route's start. Walk onto the gangway with WASD; this button does not
  teleport the player aboard. The ship remains moored and cannot be driven.
- Service-building doors open automatically when approached on foot and close
  after departure. Garage shutters also recognize a player-driven car, not idle
  parked cars or ambient traffic. These doors do not yet transfer into interiors.

## Authored composition

Foundry Avenue has a northern built frontage. Westgate has rowhouses, a diner,
laundry and a garage apron. The central block combines a market hall and public
plaza; Union Garden joins housing and the clinic. The eastern blocks transition
to cold storage, freight offices and a loading yard. Quay Boulevard overlooks a
moored container ship, working-quay equipment and animated water.

Foundry Bridge crosses the harbor channel to Northbank: a civic/business quarter,
maritime museum, aquarium, cinema, neighborhood shops, housing and a waterfront
promenade. Its pylons and lateral barriers stay outside the usable road/sidewalk deck.

Exchange Lane and Courtyard Lane subdivide Northbank with narrower, 72px local
streets; both connect at each end. The grocery/cinema lots and their accesses were
refitted before inserting the southern street. Two paved pedestrian alleys pass
between the western houses and connect the north sidewalk to Market Street via
the courtyard. They are walkable shortcuts, not lanes for civilian traffic.

Northgate adds four developed blocks with sixteen buildings: homes, workshops,
shops, a lodge, community hall and a fire-station exterior with a clear apron.
The three north/south streets continue through the former district boundary;
the old invisible northern cap has been removed, not merely painted over.

There are 49 solid buildings, 45 explicit access strips, twenty authored road
segments, 40 directed lanes and 38 junctions. Building shadows are included in setbacks.
Physical water boundaries, crane bases, buildings, fountain, benches and cargo
stacks are distinct from the traversable paving. Freight passes through the city
on a viaduct with four grade-separated road crossings, then descends a long ramp
into the East Cut tunnel. Each locomotive/wagon disappears independently at the
portal and reemerges from the western tunnel after a closed underground return.
Pillars avoid roads, sidewalks, buildings and their accesses. There are **no
at-grade road/rail crossings** in this composition.

All twenty road segments use the existing UnifiedRoadNetwork2D graph and surfaces.
HarborRoadNetwork replaces the generic rectangular grass background and adds
local edge finishing from the exposed union of the existing road/junction surfaces.
It caches that boundary by routing revision, outlines curb and outside sidewalk,
and preserves openings for crossings and authored accesses. It does not install
guard rails around the streets or draw internal seams across junction asphalt.
HarborSafety derives crossing references from the graph, then reuses the existing
crossing areas and traffic signal controller. Its composition-specific override
classifies actual road/rail intersections by elevation and audits physical supports,
without inventing a future district handoff.
The preview's small `HarborController` subclass aggregates occupancy across the
arms of one junction, scoped to its own graph: an empty crosswalk must not erase
another arm's active pedestrian demand. The shared production controller is untouched.
New reservations also respect the head of the queue on the same approaching lane.
A deterministic two-car probe reproduced a rear car reserving first, leaving the
front car waiting for the reservation and the rear car waiting for spacing. The
local override rejects that rear-first request, preserves the current owner's
renewal, and admits the following car after the leader clears the junction.
The local crossing subclass allows the exact active junction-reservation owner to
clear the exit zebra before pedestrian permission is granted. Other vehicles still
stop; this prevents circular waiting between an occupied junction and its exit zebra.
The preview Player explicitly uses layer 4 and the pedestrian group so the real
crossing Area2D can detect it; merely painting zebras would not provide this behavior.

## What is actually running

- 28 catalog traffic vehicles navigate real generated lanes and junction connectors.
- 39 articulated pedestrians walk audited sidewalk/courtyard routes; four pause
  at outdoor destinations. These are not simulated visits inside buildings.
- A local AmbientTrain subclass follows the elevated/tunnel freight route with six
  wagons, individual tunnel clipping and height-dependent drawing order.
- The existing Player and PlayerCar supply walking, interaction and driving.
- Functional pedestrian crossing areas publish requests to junction control.

## Validation

Run the scripts with `godot --headless --path <project> --script res://tests/<script>`:

- `test_harbor_road_contract.gd`: no validation errors, no open-end exemptions,
  all generated lanes reachable in the directed graph, emergency route plans across the bridge.
- `test_harbor_district.gd`: full scene, all three districts' building/sidewalk setbacks,
  physical asphalt probes (2,391 in this layout), access and destination probes, real car
  drive from parking to Dock Street.
- `test_harbor_alleys.gd`: 143 probes using the actual player's shape, 12 actual
  player collision sweeps, clear paving, sidewalk endpoints and elevated-rail separation.
- `test_harbor_road_edges.gd`: closed curb/sidewalk contours, absence of internal
  seams, access openings and cache reuse; also checks a curved-road junction fixture.
- `test_harbor_bridge.gd`: actual PlayerCar drives across the channel in both
  directions; checks road clearance and water collisions outside the bridge.
- `test_harbor_gateway.gd`: future-connection contract, two same-direction lanes
  per carriageway, actual player-car driving and traffic-AI round trips using the
  temporary return. The next map is not loaded or teleported to by this test.
- `test_harbor_life.gd`: live traffic handoffs, a complete actual train circuit,
  independent wagon disappearance/reemergence, pillar/roof clearance, pedestrians
  outside roads/buildings/tree trunks, and actual destination pauses. Four additional
  production-AI trips enter, traverse and leave both local streets in both directions,
  with their vehicle envelopes checked for static obstacles. Test spawns first satisfy
  the real factory's junction/occupancy checks; cars are not teleported along the route.
- `test_harbor_safety.gd`: real player/crossing detection and junction demand,
  plus traffic stopping/resuming, four elevated crossings and physical road clearance
  beneath the viaduct.
- `test_harbor_ship_access.gd`: ordinary Player input boards from the quay;
  real-body sweeps exercise the deck circuit and return, with water/solid probes
  and actual pistol projectiles in a clear corridor and against cargo.
- `test_harbor_entrances.gd`: real Player approaches and leaves seven doors,
  observes intermediate animation states, verifies physical facades stay solid,
  outside-return markers and the absence of invented destination transfers.
  Additional gun-store/morgue fixtures exercise styles not yet placed in this map.

`tests/capture_harbor_preview.gd` requires a real renderer, not `--headless`, and
writes review PNGs under `D:/geteco/`. It also waits for the actual running train
to approach and enter East Cut, capturing both moments without moving the actor.
It does not change scene authoring.
`tests/capture_harbor_ship.gd` also requires a real renderer. It starts on the
land-side quay using the documented review button and walks the normal Player
through the complete authored itinerary using input, saving ship/boarding/bow
images under `D:/geteco/`; it does not teleport the actor aboard.

## Facade doors / interior handoff

All HarborBuilding business lettering is removed from rendering (including the
inherited vector IML letters); business_name remains authoring metadata. Roofs,
facades, colors and non-textual emblems distinguish services. This change does
not remove review UI, road signage or dialogue text from unrelated systems.

Seven animated doors serve five existing buildings: Garage, Police, Clinic,
MotorWorkshop and the three NorthFireStation bays. Garage and firehouse use
rolling shutters; police/hospital use sliding panels. The hospital's entire
facade faces its actual northern access, rather than putting a door on a roof.
Gun-store and morgue variants are supported, but no new lots were invented.

HarborEntrance inherits the existing BuildingEntrance and reuses its scene,
signals, sensor and public open_door/close_door/request_interaction API. The
local subclass removes textual prompts/static door art, animates open_amount,
and exposes get_entrance_state with global threshold/approach/outward geometry.
Each entrance has an OutsideReturn marker and stable destination_id. No shared
Player, BuildingEntrance, ProceduralBuilding or interior-manager code is changed.

interior_available=false deliberately keeps BuildingSolid intact and suppresses
destination_requested. These are animated exterior doors, not enterable rooms.
The integration prompt is [PROMPT_ANTIGRAVITY_INTERIORES.md](PROMPT_ANTIGRAVITY_INTERIORES.md).
It identifies the existing purple Maciota rig in JagerNPC.gd, requires animated
room activity and conversational NPCs, and rejects empty exit-only rooms without
trapping the player. No interiors, missions or new purchases are implemented here.

`tests/capture_harbor_entrances.gd` uses the real renderer and normal Player input
to capture closed, opening and open doors across all five building types, then
verifies closure after departure. Images are under D:/geteco/harbor-door-*.png.
Final door-stage validation passed: seven authored doors plus two separate
gun-store/morgue fixtures, nine intermediate opening/closing animations and
nine preserved building solids. Normal Player movement covered 1,510.4px with
zero destination requests. A real PlayerCar stayed ignored while parked, opened
the garage when driven, and no longer held it open after driver departure.
District, alleys and ship-access regressions also passed on the final sources.
Logs: D:/geteco/harbor-door-entrances-final.log and
D:/geteco/harbor-door-test_harbor_{district,alleys,ship_access}.log.
The previously documented general-traffic failure is still open; this stage
does not claim a new all-suite pass or change the traffic controller.

## Walkable ship / future mission locations

The Northstar has a 40px pedestrian gangway at y=1762, between the crane bases
and accommodation block. Its sides and deck perimeter have physical rails.
Eighteen container footprints are shared between drawing and collision, leaving
longitudinal work aisles and an exterior circuit to the bow and stern.
Only the hull/gangway footprint is removed from the channel collision; drawing
a bridge without opening the water collider would not permit boarding.
Waterfront audits must now combine `water_collision_rects` with
`water_collision_polygons`; the rectangle list alone no longer describes the
entire water boundary around the irregular hull.

`Waterfront.get_ship_access_data()` describes geometry in Waterfront-local space:
`gangway_bounds: Rect2`, `hull_polygon` and `deck_polygon: PackedVector2Array`,
`obstacles` and `cargo_obstacles: Array[Rect2]`, `walk_route: PackedVector2Array`,
plus guard-rail geometry and `future_markers: Dictionary[String, Vector2]`.
The generated Marker2D children live under `Waterfront/ShipWaypoints`:
`GangwayEntry`, `ShipLanding`, `CargoInspection`, `BowLookout`, `AftAssembly`.
Convert these local points with `Waterfront.to_global()` when integrating actors.
`mission_integrated` and `ship_pilotable` are both explicitly false. The markers
are possible future mission locations, not an implemented NPC navigation system.

The boarding contract passed with 641 actual-player capsule queries, 38 physical
body sweeps, 316.7px of normal keyboard boarding from the road sidewalk, 1,089
blocked-water samples, all five markers reached, and production Player pistol
projectiles both travelling through a clear aisle and stopping against cargo.
Evidence: `D:/geteco/harbor-ship-access.log`.
The final real-renderer capture additionally completed the entire 19-leg itinerary
using normal Player input, including the cargo aisle, bow, stern and return to land:
`D:/geteco/harbor-ship-capture-final.log` (`complete_route=true boarded=true`).
An initial capture-driver attempt stopped 4px short because its analog input fell
inside the normal deadzone; the capture driver's input strength was corrected,
without changing Player physics or ship geometry.

Ship-stage regression: seven of the eight existing harbor tests passed, plus the
new ship-access test (**8/9 distinct tests passed**). `test_harbor_life.gd` failed
both in the first run and in one isolated rerun. Courtyard Lane's forward probe
entered but could not leave near `(5402, 1772)`, with `obstacles=[]`; the reverse
probe then lacked a safe upstream spawn. Diagnostics show vehicles holding opposing
junction reservations while waiting behind other cars between `(5550, 1790)` and
`(5550, 2200)`. This is an unresolved traffic circulation case, not an all-green
district result; concurrency is not established as its cause. The ship stage does
not change the traffic controller or weaken that test to hide the failure. The
life test builds its own road fixture without instantiating HarborWaterfront,
so this failure is reproduced without the ship or its new gangway geometry. The
train still completed its cycle in the isolated rerun (13,807.5px).
Evidence: `D:/geteco/harbor_ship_regression_20260904/`.

## Map 2 connection

Northgate leads to two separated 96px carriageways, each with two same-direction
lanes. White lane separators, direction arrows, median and explicit signs identify
the regional route. Its north end currently has a functioning two-lane temporary
return, so traffic never drives into an unimplemented map or wraps at a loose end.

`Gateway.get_map2_connection_contract()` publishes `connected = false`, an empty
`transition_scene`, and two generated Marker2D ports:

- `Map2Outbound`: `(6120, -4200)`, heading north / `Vector2.UP`, width 96, two lanes.
- `Map2Inbound`: `(5880, -4200)`, heading south / `Vector2.DOWN`, width 96, two lanes.

The contract also identifies `RoadLayout/map2_temporary_return`. Future integration
must extend both carriageways consistently into Map 2 and replace that temporary
return deliberately; these markers do not by themselves implement scene switching,
regional traffic streaming or saves. No fake open-end exemption is used.

## Deliberate limits / next integration

This is a playable district prototype, **not five completed connected districts**.
No fictitious gateway endpoints are added just to suppress validation. Regional
connections need to be authored together with the adjacent district later.
Building interiors, purchases, mission anchors, emergency depots and save/menu
integration have not been wired here. Named businesses are currently exterior sites.
The fire station currently has an exterior and vehicle apron, not emergency dispatch.
The remaining requested gameplay program is recorded, not claimed as implemented:
a bus terminal with buses/passenger service
and the mission-1 arrival/respawn; subsequent hospital respawn; and the first
gang's violent territory. The identity of the mission-1 respawning actor still
needs confirmation. A separate requested "zona" must be away from the cemetery;
its intended use also awaits clarification. The new alleys do not silently define
that territory or change any mission/respawn behavior.
The ship is a moored, explorable exterior deck, not a controllable ship or a
cargo-loading simulation. The gangway is a physical pedestrian connection to the
quay. Cargo and accommodation remain solid; they are not walk-through decorations
or accessible cabin interiors. Scene markers reserve locations for a future mission,
without activating a mission, enemies, objectives, rewards or respawn changes.
Normal projectile collisions apply to solid cargo; this does not add a new cover
system for inherited melee or explosion-radius damage.
Its navigable departure direction would be south; navigation beneath Foundry Bridge
is not established. The isolated railway loop is not yet a regional railway service.
Road guard rails remain off for urban frontage; water/rail/solid-site boundaries
have local collision instead. Existing district settings are untouched.

Headless tests establish bounded behavior, not a guarantee of unlimited-session
AI correctness. The renderer was also inspected in overview and close views.
The northern/highway revision ran 41 tests (33 existing + eight harbor contracts).
The first pass was **39/41**: the legacy Borough1 level-crossing runtime test
reported a train/car conflict, and the harbor life test exposed queue arbitration.
After the preview-local queue fix, **all eight harbor tests passed again** using
the final sources. The legacy rail test passed an isolated rerun without a source
change; the initial failure remains recorded and is not claimed fixed by this work.
Evidence is retained in `D:/geteco/harbor_north_suite_20260904/` and
`D:/geteco/harbor_north_final_20260904/`.
Actual highway AI drove both outbound lane choices through the temporary return
and back south (over 3,600 px each); the controllable car drove 1,586 px in each
direction without collision. The final life test drove all four local-street
directions, completed 13,803.3 px of train travel, and reported no deadlock-limit
violations during its bounded observation. Independent fire-apron checks used a
102x40 truck envelope, 114 poses and 14 physical sweeps with zero failures; they
prove exterior clearance, not an integrated firefighter dispatch mission.

The local-street/alley revision passed **40/40 tests** (33 existing + seven harbor
contracts), with evidence in `D:/geteco/harbor-regression/20260904-180046/`.
Both directions of both local streets were driven by actual traffic AI, with no
static obstacle in the real vehicle collision shape; the final train circuit covered
13,769.7 px. Edge auditing found 28 closed contours across the district and curved
fixture, without broken chains or internal seams. Four alley entrances stay open
in the outside sidewalk outline without cutting the asphalt curb.
The earlier bridge/rail expansion passed all **38 tests** (33 existing + five harbor
contracts), before the local-street/alley addition. Its historical logs are retained in
`D:/geteco/harbor-regression/20260904-174706/`.
Actual bridge drives covered 1,386 px in each direction without collision;
the train completed more than 13,600 px including its underground return.
An additional editor-mode probe confirmed `Engine.is_editor_hint() == true` and
an empty spatial/road/safety audit for the new scene. The editor also restores
the user's existing Main/DistrictOne tabs: these emitted unrelated deferred
safety-node and district3-stub diagnostics during restoration. They were not
silenced or repaired as part of this isolated district task.
The tool environment emitted an existing certificate-store warning; renderer
launches also reported inability to prepare the external user-save directory.
The preview does not change SaveManager or user-save handling to hide these messages.

## Performance, environment panel and the fire station (technical-base pass)

**Performance.** The ~10 FPS the reviewer saw traced back to `TrafficVehicle.gd`'s
per-frame `advance_on_lane()` (called by every ambient vehicle, every `_process`
frame, regardless of camera distance) — measured, not assumed: a real-renderer
run with all 28 ambient vehicles' processing disabled went from ~68ms/frame to
~20ms/frame under identical conditions, isolating them as the dominant cost —
not the per-character 3D SubViewports the initial static read of the code
suggested. Fixes, all preserving full traffic function (nothing is disabled
permanently):
- Vehicles far from every active camera are advanced at a coarser, distance-scaled
  time step (`_compute_lod_stride()` in `city_demo/scripts/TrafficVehicle.gd`) —
  same lane-following/reservations/stops, just recalculated less often when
  off-screen, imperceptibly so. Garage-interior FPS alone went ~13→65 with this.
- `_traffic_control_zone_motion()` now skips crossings/rail zones far from the
  vehicle before calling into them (was unconditionally checking every zone in
  the district, every vehicle, every frame).
- Interior NPC 3D rigs (`viewport_3d` SubViewports on `JagerNPC`/
  `HarborConversationalNPC`) only render while an actor is actually inside
  that specific interior (`HarborInteriorBase.set_npc_rendering_active()`,
  toggled by `HarborInteriorManager` on real enter/exit).
- Outdoor pedestrians (`AnimatedPedestrian3D`) throttle their own 3D viewport
  the same way, based on distance to the active camera.
- `AuthoredSidewalkPedestrian`'s two independent per-frame neighbor scans were
  merged into one, and that refresh itself now runs every 3rd physics frame
  instead of every frame.
- `JunctionTrafficController._owned_junction_for_vehicle()`/
  `_release_if_vehicle_cleared()` scanned every junction in the district
  (38 here) for every vehicle, every frame, just to answer "do I already
  hold a reservation?". A reverse index (`_vehicle_owned_junction`, kept in
  sync at the reservation system's only two mutation sites) turns that into
  an O(1) lookup, with a full-scan fallback if the cache and the
  authoritative per-junction state ever disagree.
- `HarborWaterfront.gd` redrew its entire ship/water/crane scene 10x/second
  unconditionally; it now skips that redraw when the active camera is far
  from the quay.
- All ~28 ambient vehicles were spawned with the same LOD-recheck timer
  phase, so their `get_camera_2d()`/distance check for the fix above
  synchronized into a recurring frame-time spike every ~0.4s instead of
  amortizing; the initial phase is now randomized per vehicle.
- The LOD near-radius is capped (`LOD_MAX_NEAR_RADIUS`) so it stays
  effective even when the camera is zoomed far out (the review overview),
  instead of the "near" zone covering the whole district and defeating the
  throttle entirely.

`tests/measure_harbor_performance.gd` (real renderer, not headless) recorded
before/after numbers per scenario, and `tests/measure_harbor_sustained_driving.gd`
records a single continuous drive with no scenario-switching (the multi-scenario
suite showed real run-to-run drift, likely from resource/audio caching effects
across many rapid weather/scenario transitions in one process — a sustained,
single-scenario sample is the more trustworthy number for ordinary play).
Typical real-renderer results on the test machine, day/clear unless noted:
overview ~30-41 FPS (fundamentally harder — the entire district is on-screen
at once, so distance-based throttling has little room to work), walking a busy
block ~40-48 FPS, driving across the district ~55-70 FPS average with a p50
(median frame) around 65-70 FPS, garage interior ~60-100 FPS, night+rain
driving ~45-55 FPS. A real (not yet fully explained) ~250-300ms outlier frame
recurs roughly every 3-4 seconds of continuous driving in the sustained sample,
dragging the average below the median — audio-stream generation was checked
and ruled out (every procedural stream is cached after first use); the
remaining tail is flagged here rather than claimed fixed. The pre-existing
Courtyard Lane traffic-queue failure in `test_harbor_life.gd` (documented
above) is unchanged by this pass — still open, not claimed fixed.

**Alley re-route for the Quadra 1 Westgate layout.** Antigravity's building
pass (`FoundryTerraceWest/East`, `FoundryLofts`, `CornerDiner`, `Laundry`,
`UnionWorkshop`) left both internal building gaps at 24px, narrower than the
28px `ALLEY_WIDTH` `test_harbor_alleys.gd` hard-requires — no path threaded
straight between those buildings can avoid clipping one side. Both alleys in
`HarborAlleys.gd` are re-routed to enter/exit through the open margins at
the edges of the block instead (beside `westgate_drive` for the west alley;
the open corner east of `FoundryLofts` for the east alley), jogging through
the clear band between the two building rows at a height that also clears
the elevated rail's ground-level pillar boundaries (`_create_track_safety_boundaries()`
in `HarborRailLine.gd`) before descending through whichever Market St gap
is actually wide enough. One more obstacle surfaced during this: 
`HarborDistrict._build_street_lamps()` is inherited unchanged by
`HarborEastDistrict`/`HarborNorthDistrict`, so its hardcoded `lamp_points`
plant the same 5 `StreetLamp`s at those small local coordinates in all three
district roots — one of them landed exactly on the widest remaining Market
St gap. Not fixed at the source (that's Antigravity's file/inheritance
chain); the west alley's descent is routed around it instead.
`test_harbor_alleys.gd` passes clean (0 failures) with the new routing.
Flagging the lamp duplication itself for a follow-up: as authored, three
`StreetLamp` instances currently sit stacked at each of the 5 hardcoded
positions (one per district root) instead of one.

The pre-existing Courtyard Lane traffic-queue failure in `test_harbor_life.gd`
(documented above) is unchanged by this pass — still open, not claimed fixed.

**Environment panel.** `HarborPreview.gd` now owns one `DayNightWeatherManager`
(the existing project-wide day/night + rain class — no second weather system),
with Dia/Noite, Chuva and an optional FPS/frame-time readout in the review UI.
`HarborInteriorManager` calls `set_interior_mode(true/false)` on it using the
same enter/exit signals as the NPC-rendering toggle above. **Interface for
lamp posts/window lights**: listen to `DayNightWeatherManager.time_changed(is_dark)`
(group `day_night_manager`) — the class already does this for vehicle
headlights (`_notify_headlights`). `StreetLamp.gd` instances placed in
`HarborDistrict._build_street_lamps()` (added alongside this pass) already
follow this contract correctly.

**Fire station (Northgate Fire / 03).** Each of the 3 bays now holds a real,
player-drivable truck (`world/harbor/interiors/HarborFireStationInterior.gd`,
`_build_trucks()`) — the same `DemoTrafficVehicle` class ambient traffic
already uses (proven `configure_as_parked()`/`enter_vehicle()` contract),
wearing the game's actual firetruck art (`city_demo/art/firetruck.png`, the
same asset `EmergencyVehicle.gd` type=2 uses). This does not touch, move or
remove any existing ambient/dispatched emergency vehicle. Walk in on foot,
board normally (E near the truck), drive to the gate — it opens automatically
as you approach — and crossing it outward while still driving transfers
truck+driver to the exterior aligned with that bay's own access, no extra
keypress. Driving back in through the same access returns the identical node
to its own bay (`HarborEntrance._accepts_actor` now requires a `home_bay`
meta tag for the `fire_station` role, so a stray city vehicle can't be
teleported onto a bay's resident truck). The base interior's south wall was
previously a single solid `StaticBody2D` segment with no opening — fine for
pedestrians, who teleport across it, but a vehicle driving itself out
physically needs a gap; `HarborInteriorBase._get_south_wall_gaps()` is a new
opt-in hook (empty/solid by default, so the other 6 interiors are unaffected)
that `HarborFireStationInterior` uses to open one per bay. A first-aid
station (`_build_heal_station()`) heals the player gradually while standing
in it, animated (pulsing cross light) with a visible progress bar, clamped at
`max_health` — no armor or other reward attached.
`tests/test_harbor_fire_station_trucks.gd` drives all 3 bays end-to-end with
real input (no scripted teleports) and exercises the heal station.
