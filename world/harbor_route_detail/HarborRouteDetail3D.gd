extends Node3D
class_name HarborRouteDetail3D

## Visual & physical streetscape component for the core Harbor route:
## Rodoviária (Coach Terminal) → Delegacia (Police Precinct) → Garagem do Maciota.
##
## Modular Zone Architecture:
## - ZONE_RODOVIARIA: Terminal plaza, flush passenger disembarking level crossing, transit benches, planters, bike rack.
## - ZONE_CONNECTING_STREETS: Market St & Union Ave sidewalks, pedestrian crosswalks, municipal lighting, hydrants.
## - ZONE_DELEGACIA: Police precinct forecourt, beveled curb ramp, anti-ram security bollards, civic globe lamps.
## - ZONE_MACIOTA: Workshop frontage, 7.8m wide driveway curb cut, corner hazard bollards, industrial lamp.
##
## ARCHITECTURAL CONSTRAINTS & GUARANTEES:
## - Independent lifecycle per zone: mount_zone(), unmount_zone(), has_zone(), get_zone().
## - Zero duplication of buildings, facades, NPCs, or vehicles.
## - Zero descriptive/decorative text (AGENTS.md).
## - Flush level crossing at Rodoviária disembark corridor (Y ≈ 0.01m), matching Arrival.gd and HarborTerminalModel3D.
## - Gentle beveled ramps (slopes ≤ 8.5°) at Delegacia and Maciota transitions to prevent CharacterBody3D stalls.

const ZONE_RODOVIARIA := "rodoviaria"
const ZONE_CONNECTING_STREETS := "connecting_streets"
const ZONE_DELEGACIA := "delegacia"
const ZONE_MACIOTA := "maciota"
const PLACE_CATALOG := preload("res://world/places/PlaceCatalog.gd")

const ALL_ZONES := [
	ZONE_RODOVIARIA,
	ZONE_CONNECTING_STREETS,
	ZONE_DELEGACIA,
	ZONE_MACIOTA
]

# Dictionary tracking mounted zone instances: zone_id -> Node3D
var _mounted_zones: Dictionary = {}

## If true and no zones have been mounted prior to entering the tree,
## mounts all zones on _ready(). Defaults to false so mounting a single zone
## or using chunk streaming never inadvertently triggers mount_all().
@export var auto_mount_all: bool = false

func _ready() -> void:
	if auto_mount_all and _mounted_zones.is_empty():
		mount_all()

# ==============================================================================
# Zone Lifecycle API (Public)
# ==============================================================================

## Builds and returns an unparented Node3D containing all props and geometry for a specific zone.
## The returned node is not attached to any parent.
static func build_zone(zone_id: String) -> Node3D:
	var zone_node: Node3D = null
	match zone_id:
		ZONE_RODOVIARIA:
			zone_node = _build_rodoviaria_zone()
		ZONE_CONNECTING_STREETS:
			zone_node = _build_connecting_streets()
		ZONE_DELEGACIA:
			zone_node = _build_delegacia_zone()
		ZONE_MACIOTA:
			zone_node = _build_maciota_zone()
		_:
			push_warning("HarborRouteDetail3D: Unknown zone_id '%s'." % zone_id)
			return null
	if zone_node != null:
		zone_node.name = "Zone_" + zone_id
	return zone_node

## Mounts a specific zone by ID as a child of this HarborRouteDetail3D instance.
## Returns the mounted zone Node3D, or the existing one if already mounted.
func mount_zone(zone_id: String) -> Node3D:
	if _mounted_zones.has(zone_id) and is_instance_valid(_mounted_zones[zone_id]):
		return _mounted_zones[zone_id]
	
	var zone_node := build_zone(zone_id)
	if zone_node != null:
		add_child(zone_node)
		_mounted_zones[zone_id] = zone_node
	
	return zone_node

## Unmounts and frees a specific zone by ID from this HarborRouteDetail3D instance.
func unmount_zone(zone_id: String) -> void:
	if not _mounted_zones.has(zone_id):
		return
	var node: Node3D = _mounted_zones[zone_id]
	_mounted_zones.erase(zone_id)
	if is_instance_valid(node):
		node.queue_free()

## Returns true if the designated zone is currently mounted on this instance.
func has_zone(zone_id: String) -> bool:
	return _mounted_zones.has(zone_id) and is_instance_valid(_mounted_zones[zone_id])

## Returns the root Node3D of the mounted zone, or null if not mounted.
func get_zone(zone_id: String) -> Node3D:
	if has_zone(zone_id):
		return _mounted_zones[zone_id]
	return null

## Mounts all zones into this HarborRouteDetail3D instance.
func mount_all() -> void:
	for zone_id in ALL_ZONES:
		mount_zone(zone_id)

## Unmounts and frees all mounted zones from this HarborRouteDetail3D instance.
func unmount_all() -> void:
	for zone_id in ALL_ZONES:
		unmount_zone(zone_id)

## Returns the approximate spatial AABB of a zone in global coordinates.
static func get_zone_bounds(zone_id: String) -> AABB:
	match zone_id:
		ZONE_RODOVIARIA:
			return AABB(Vector3(92.0, 0.0, 68.0), Vector3(31.0, 5.5, 7.5))
		ZONE_CONNECTING_STREETS:
			return AABB(Vector3(81.0, 0.0, 72.0), Vector3(8.0, 5.5, 57.0))
		ZONE_DELEGACIA:
			return AABB(Vector3(58.0, 0.0, 129.0), Vector3(20.0, 5.0, 9.0))
		ZONE_MACIOTA:
			return AABB(Vector3(38.5, 0.0, 101.25), Vector3(18.5, 5.4, 4.15))
	return AABB()

## Returns designated physical transition anchors for gameplay navigation.
static func get_transition_point(point_id: String) -> Vector3:
	match point_id:
		"rodoviaria_bus_crossing":
			return Vector3(107.0, 0.05, 74.55)
		"rodoviaria_arrival_anchor":
			return Vector3(106.25, 0.06, 70.625)
		"market_union_crossing":
			return Vector3(82.5, 0.005, 78.125)
		"delegacia_curb_ramp":
			return Vector3(67.5, 0.05, 134.3)
		"delegacia_approach":
			return Vector3(67.5, 0.10, 132.5)
		"maciota_driveway_ramp":
			return Vector3(45.15, 0.04, 105.0)
		"maciota_bay_entry":
			return Vector3(46.875, 0.08, 101.7375)
	return Vector3.ZERO

# ==============================================================================
# Zone 1: Rodoviária (Coach Terminal Plaza & Passenger Corridor)
# ==============================================================================

static func _build_rodoviaria_zone() -> Node3D:
	var zone := Node3D.new()
	
	# Sidewalk promenade is partitioned into West Wing (X: 92.0 to 103.5) and East Wing (X: 110.5 to 122.0).
	# The central transit corridor (X: 103.5 to 110.5, span 7.0m) is a flush pedestrian level crossing
	# at grade Y = 0.05m, matching Market Street's roadway surface and Arrival.gd disembark trajectory!
	
	# 1. West Wing Slab (11.5m x 4.2m at Y = 0.12m)
	var slab_w := HarborRouteProps.create_sidewalk_slab(Vector2(11.5, 4.2), 0.12)
	slab_w.position = Vector3(97.75, 0.0, 72.4)
	zone.add_child(slab_w)
	
	# West Curb along Market St edge (Z = 74.55)
	var curb_w := HarborRouteProps.create_curb_segment(11.5, 0.30, 0.14)
	curb_w.rotation_degrees = Vector3(0, 90, 0)
	curb_w.position = Vector3(97.75, 0.0, 74.55)
	zone.add_child(curb_w)
	
	# 2. East Wing Slab (11.5m x 4.2m at Y = 0.12m, starting at X = 110.5)
	var slab_e := HarborRouteProps.create_sidewalk_slab(Vector2(11.5, 4.2), 0.12)
	slab_e.position = Vector3(116.25, 0.0, 72.4)
	zone.add_child(slab_e)
	
	# East Curb along Market St edge (Z = 74.55)
	var curb_e := HarborRouteProps.create_curb_segment(11.5, 0.30, 0.14)
	curb_e.rotation_degrees = Vector3(0, 90, 0)
	curb_e.position = Vector3(116.25, 0.0, 74.55)
	zone.add_child(curb_e)
	
	# 3. Central Passenger Disembarking Level Crossing (X: 103.5 to 110.5, Z: 70.3 to 75.0)
	# Level paving (height = 0.05m, top at Y = 0.05m) matching Market St roadway box exactly.
	# Dante walks from bus door (X ≈ 108.56, Z ≈ 76.31) to ARRIVAL (X = 106.25, Z = 70.625)
	# with > 1.29m clearance to side_ramp_e and zero vertical steps or curb stones.
	var level_crossing := HarborRouteProps.create_sidewalk_slab(Vector2(7.0, 4.7), 0.05, HarborRouteMaterials.sidewalk_accent(), false)
	level_crossing.position = Vector3(107.0, 0.0, 72.65)
	zone.add_child(level_crossing)
	
	# Tactile yellow edge line marking the pedestrian boundary at Z = 74.55
	var edge_marker := MeshInstance3D.new()
	edge_marker.name = "BusBayEdgeMarker"
	var em_box := BoxMesh.new()
	em_box.size = Vector3(7.0, 0.015, 0.30)
	edge_marker.mesh = em_box
	edge_marker.material_override = HarborRouteMaterials.curb_yellow_marking()
	edge_marker.position = Vector3(107.0, 0.05, 74.55)
	zone.add_child(edge_marker)
	
	# Side curb ramps transitioning elevated wings down into central corridor
	var side_ramp_w := HarborRouteProps.create_curb_ramp(4.2, 0.70, 0.12)
	side_ramp_w.rotation_degrees = Vector3(0, 90, 0)
	side_ramp_w.position = Vector3(103.5, 0.0, 72.4)
	zone.add_child(side_ramp_w)
	
	var side_ramp_e := HarborRouteProps.create_curb_ramp(4.2, 0.70, 0.12)
	side_ramp_e.rotation_degrees = Vector3(0, -90, 0)
	side_ramp_e.position = Vector3(110.5, 0.0, 72.4)
	zone.add_child(side_ramp_e)
	
	# 4. Amenities placed exclusively in the flanking wings:
	# West Wing Amenities (X ≤ 101.5):
	var bench_w := HarborRouteProps.create_bench(2.2)
	bench_w.position = Vector3(98.5, 0.12, 71.0)
	zone.add_child(bench_w)
	
	var bin_w := HarborRouteProps.create_trash_bin()
	bin_w.position = Vector3(95.0, 0.12, 71.2)
	zone.add_child(bin_w)
	
	var light_w := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(90.0))
	light_w.position = Vector3(93.5, 0.12, 73.8)
	zone.add_child(light_w)
	
	var planter_w := HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85))
	planter_w.position = Vector3(101.5, 0.12, 73.4)
	zone.add_child(planter_w)
	
	# East Wing Amenities (X ≥ 113.0):
	var planter_e := HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85))
	planter_e.position = Vector3(113.0, 0.12, 73.4)
	zone.add_child(planter_e)
	
	var bench_e := HarborRouteProps.create_bench(2.2)
	bench_e.position = Vector3(115.5, 0.12, 71.0)
	zone.add_child(bench_e)
	
	var bin_e := HarborRouteProps.create_trash_bin()
	bin_e.position = Vector3(118.0, 0.12, 71.2)
	zone.add_child(bin_e)
	
	var light_e := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(90.0))
	light_e.position = Vector3(120.5, 0.12, 73.8)
	zone.add_child(light_e)
	
	var bike_rack := HarborRouteProps.create_bike_rack(4, 0.85)
	bike_rack.position = Vector3(121.5, 0.12, 70.5)
	zone.add_child(bike_rack)
	
	# Storm drain grate in street gutter outside west wing
	var drain := HarborRouteProps.create_drain_grate()
	drain.position = Vector3(101.5, 0.0, 74.85)
	zone.add_child(drain)
	
	return zone

# ==============================================================================
# Zone 2: Connecting Streets (Market Street & Union Avenue Corridors)
# ==============================================================================

static func _build_connecting_streets() -> Node3D:
	var zone := Node3D.new()
	
	# 1. Northern sidewalk of Market St towards Union Ave (X: 85.6 to 92.0, Z: 72.5 to 74.5)
	# Começa em 85.6, alinhada à calçada leste da Union Ave: a Union Ave ocupa X 77.2–85.3
	# e a versão anterior (X 83.0) avançava 2.3 m sobre a pista, bloqueando carros no cruzamento.
	var slab_market := HarborRouteProps.create_sidewalk_slab(Vector2(6.4, 2.0), 0.12)
	slab_market.position = Vector3(88.8, 0.0, 73.5)
	zone.add_child(slab_market)
	
	# Curb along Market St edge, trimmed to start past the pedestrian curb ramp at X = 87.8 (X: 87.8 to 92.0, span 4.2m)
	# Eliminates collider overlap between the vertical curb and the beveled ramp wedge (X: 85.6 to 87.8)
	var curb_market := HarborRouteProps.create_curb_segment(4.2, 0.30, 0.14)
	curb_market.rotation_degrees = Vector3(0, 90, 0)
	curb_market.position = Vector3(89.9, 0.0, 74.55)
	zone.add_child(curb_market)
	
	# Pedestrian curb cut ramp at Market/Union intersection corner (X: 85.6 to 87.8, span 2.2m)
	var ramp_market := HarborRouteProps.create_curb_ramp(2.2, 0.70, 0.12)
	ramp_market.position = Vector3(86.7, 0.0, 74.55)
	zone.add_child(ramp_market)
	
	# 2. Pedestrian crosswalk across Market St at Union Ave corner
	var crosswalk_market := HarborRouteProps.create_crosswalk_stripes(3.5, 7.5, 6)
	crosswalk_market.position = Vector3(82.5, 0.0, 78.125)
	zone.add_child(crosswalk_market)
	
	# 3. Eastern sidewalk along Union Avenue (runs North-South from Z: 82.0 to 128.0 at X: 86.8)
	var slab_union_n := HarborRouteProps.create_sidewalk_slab(Vector2(2.4, 22.0), 0.12)
	slab_union_n.position = Vector3(86.8, 0.0, 94.0)
	zone.add_child(slab_union_n)
	
	var slab_union_s := HarborRouteProps.create_sidewalk_slab(Vector2(2.4, 22.0), 0.12)
	slab_union_s.position = Vector3(86.8, 0.0, 116.0)
	zone.add_child(slab_union_s)
	
	# Curbs facing the Union Ave roadway (at X = 85.5)
	var curb_union_n := HarborRouteProps.create_curb_segment(22.0, 0.30, 0.14)
	curb_union_n.position = Vector3(85.5, 0.0, 94.0)
	zone.add_child(curb_union_n)
	
	var curb_union_s := HarborRouteProps.create_curb_segment(22.0, 0.30, 0.14)
	curb_union_s.position = Vector3(85.5, 0.0, 116.0)
	zone.add_child(curb_union_s)
	
	# Streetlights spaced every ~20m along Union Avenue
	var light_u1 := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(-90.0))
	light_u1.position = Vector3(87.5, 0.12, 94.0)
	zone.add_child(light_u1)
	
	var light_u2 := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(-90.0))
	light_u2.position = Vector3(87.5, 0.12, 115.0)
	zone.add_child(light_u2)
	
	# Municipal fire hydrant near the midway junction
	var hydrant_mid := HarborRouteProps.create_fire_hydrant()
	hydrant_mid.position = Vector3(87.4, 0.12, 102.5)
	zone.add_child(hydrant_mid)
	
	# Storm drains along curb
	var drain_u1 := HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85))
	drain_u1.position = Vector3(85.2, 0.0, 92.0)
	zone.add_child(drain_u1)
	
	var drain_u2 := HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85))
	drain_u2.position = Vector3(85.2, 0.0, 118.0)
	zone.add_child(drain_u2)
	
	return zone

# ==============================================================================
# Zone 3: Delegacia (Harbor Patrol Precinct Forecourt)
# ==============================================================================

static func _build_delegacia_zone() -> Node3D:
	var zone := Node3D.new()
	
	# Forecourt esplanade in front of police precinct (X: 59.0 to 76.0, Z: 129.5 to 133.9)
	# The manhole needs an opening in both the visible slab and its collider.
	var forecourt := Rect2(59.0, 129.5, 17.0, 4.4)
	var opening := Rect2(PLACE_CATALOG.HARBOR_SEWER_OPENING.position * PLACE_CATALOG.SCALE, PLACE_CATALOG.HARBOR_SEWER_OPENING.size * PLACE_CATALOG.SCALE)
	for piece in [
		Rect2(forecourt.position, Vector2(forecourt.size.x, opening.position.y - forecourt.position.y)),
		Rect2(Vector2(forecourt.position.x, opening.end.y), Vector2(forecourt.size.x, forecourt.end.y - opening.end.y)),
		Rect2(Vector2(forecourt.position.x, opening.position.y), Vector2(opening.position.x - forecourt.position.x, opening.size.y)),
		Rect2(opening.end.x, opening.position.y, forecourt.end.x - opening.end.x, opening.size.y)
	]:
		if not piece.has_area(): continue
		var slab := HarborRouteProps.create_sidewalk_slab(piece.size, 0.10)
		slab.position = Vector3(piece.get_center().x, 0.0, piece.get_center().y)
		zone.add_child(slab)
	
	# Curbs along Dock Street edge (Z = 134.1) are SPLIT into West and East wings:
	var curb_w := HarborRouteProps.create_curb_segment(5.5, 0.30, 0.12, HarborRouteMaterials.curb_yellow_marking())
	curb_w.rotation_degrees = Vector3(0, 90, 0)
	curb_w.position = Vector3(61.75, 0.0, 134.1)
	zone.add_child(curb_w)
	
	var curb_e := HarborRouteProps.create_curb_segment(5.5, 0.30, 0.12, HarborRouteMaterials.curb_yellow_marking())
	curb_e.rotation_degrees = Vector3(0, 90, 0)
	curb_e.position = Vector3(73.25, 0.0, 134.1)
	zone.add_child(curb_e)
	
	# Pedestrian curb ramp across central approach (span 6.0m, depth 0.80m, max_height 0.10m)
	# Slopes from street Y = 0.0 (Z = 134.7) up to forecourt Y = 0.10 (Z = 133.9).
	# Slope angle = atan2(0.10, 0.80) = 7.1°, smooth stepping for CharacterBody3D!
	var p_ramp := HarborRouteProps.create_curb_ramp(6.0, 0.80, 0.10)
	p_ramp.position = Vector3(67.5, 0.0, 134.3)
	zone.add_child(p_ramp)
	
	# Institutional Police streetlights (Twin globe civic lamps with navy blue base)
	var p_light_w := HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0)
	p_light_w.position = Vector3(60.0, 0.10, 133.0)
	zone.add_child(p_light_w)
	
	var p_light_e := HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0)
	p_light_e.position = Vector3(75.0, 0.10, 133.0)
	zone.add_child(p_light_e)
	
	# Anti-ram security bollards with police navy finish and reflective bands
	# Flanking the entrance approach (X ≤ 63.5 and X ≥ 71.5), leaving an 8.0m open gap centered on entrance (67.5)!
	var bollard_xs := [60.5, 62.0, 63.5, 71.5, 74.5]
	for bx in bollard_xs:
		var bollard := HarborRouteProps.create_bollard("police")
		bollard.position = Vector3(bx, 0.10, 133.4)
		zone.add_child(bollard)
	
	# Public civic bench on the quiet west side of the forecourt
	var bench := HarborRouteProps.create_bench(2.0)
	bench.position = Vector3(61.5, 0.10, 130.2)
	bench.rotation_degrees = Vector3(0, 90, 0)
	zone.add_child(bench)
	
	# Litter bin near east corner
	var bin := HarborRouteProps.create_trash_bin()
	bin.position = Vector3(74.0, 0.10, 130.8)
	zone.add_child(bin)
	
	# Keep the manhole beside the forecourt clear for the lid and ladder access.
	
	# Storm drain grate in street gutter beside the west curb wing (clear of pedestrian ramp)
	var drain := HarborRouteProps.create_drain_grate()
	drain.position = Vector3(63.5, 0.0, 134.4)
	zone.add_child(drain)
	
	# Crosswalk across Dock Street connecting to harbor quays
	var crosswalk_dock := HarborRouteProps.create_crosswalk_stripes(3.6, 7.5, 6)
	crosswalk_dock.position = Vector3(67.5, 0.0, 137.5)
	zone.add_child(crosswalk_dock)
	
	return zone

# ==============================================================================
# Zone 4: Garagem do Maciota (Westgate Motor Co. Frontage & Apron)
# ==============================================================================

static func _build_maciota_zone() -> Node3D:
	var zone := Node3D.new()
	
	# Sidewalk frontage running in front of the workshop (X: 39.5 to 57.0, Z: 101.25 to 104.6).
	# No separate slab mesh here: any raised or differently-colored box reads as a second
	# sidewalk stacked on the district's own flat paving underneath it, no matter how thin
	# or how closely its color is matched. The flat HarborUrbanSurface3D paving (already
	# exposed here, see HarborUrbanSurface3D._RAISED_APRON_HOLES) is the sidewalk; this zone
	# only adds curb/ramp/props on top of it.

	# Driveway curb cut / beveled ramp spanning the entire 11.3m vehicle bay opening + piers + tour car arrival stop (X: 39.5 to 50.8)
	# Center X = 45.15, Z = 105.0.
	# Slopes from road level Y = 0.0 at Z = 105.4 up to apron Y = 0.03 at Z = 104.6.
	var ramp := HarborRouteProps.create_curb_ramp(11.3, 0.80, 0.03)
	ramp.position = Vector3(45.15, 0.0, 105.0)
	zone.add_child(ramp)

	# Granite curb on the east pedestrian sidewalk flank (X: 50.8 to 57.0)
	var curb_e := HarborRouteProps.create_curb_segment(6.2, 0.30, 0.03)
	curb_e.rotation_degrees = Vector3(0, 90, 0)
	curb_e.position = Vector3(53.9, 0.0, 105.0)
	zone.add_child(curb_e)

	# High-visibility yellow safety bollard placed on the east curb corner (X = 51.2, clear of vehicle bay)
	# Note: West bollard at X = 42.5 was removed to clear Arrival.gd's tour car arrival stop at (42.5, 0, 104.55).
	var bollard_e := HarborRouteProps.create_bollard("hazard")
	bollard_e.position = Vector3(51.2, 0.03, 104.6)
	zone.add_child(bollard_e)

	# Industrial gooseneck street light on the far west corner (X = 38.5, Z = 102.5), clear of car hull (X: 40.0-45.0)
	var ind_light := HarborRouteProps.create_streetlight(5.2, 1.1, "industrial", deg_to_rad(45.0))
	ind_light.position = Vector3(38.5, 0.03, 102.5)
	zone.add_child(ind_light)

	# Fire hydrant on the far east sidewalk corner (X = 56.2)
	var hydrant := HarborRouteProps.create_fire_hydrant()
	hydrant.position = Vector3(56.2, 0.03, 103.5)
	zone.add_child(hydrant)

	# Heavy scrap metal / oil drum hopper on the east apron
	var drum := MeshInstance3D.new()
	drum.name = "ScrapOilDrum"
	var d_cyl := CylinderMesh.new()
	d_cyl.top_radius = 0.32
	d_cyl.bottom_radius = 0.32
	d_cyl.height = 0.85
	drum.mesh = d_cyl
	drum.material_override = HarborRouteMaterials.cast_iron_dark()
	drum.position = Vector3(55.0, 0.03 + 0.425, 102.5)
	zone.add_child(drum)
	
	var drum_body := StaticBody3D.new()
	drum_body.name = "DrumCollision"
	drum_body.collision_layer = 1
	drum_body.collision_mask = 0
	var d_col := CollisionShape3D.new()
	var d_shape := CylinderShape3D.new()
	d_shape.radius = 0.35
	d_shape.height = 0.85
	d_col.shape = d_shape
	d_col.position = drum.position
	drum_body.add_child(d_col)
	zone.add_child(drum_body)
	
	# Storm drain grate in street gutter outside the driveway
	var drain := HarborRouteProps.create_drain_grate()
	drain.position = Vector3(51.8, 0.0, 105.35)
	zone.add_child(drain)
	
	return zone
