extends Node3D
class_name HarborRouteDetail3D

## Visual & physical streetscape component for the core Harbor route:
## Rodoviária (Coach Terminal) → Delegacia (Police Precinct) → Garagem do Maciota.
##
## Modular Zone Architecture:
## - ZONE_RODOVIARIA: Transit benches, planters and bike rack on the district pavement.
## - ZONE_CONNECTING_STREETS: Pedestrian markings, municipal lighting and hydrants.
## - ZONE_DELEGACIA: Anti-ram security bollards and civic globe lamps on a flush forecourt.
## - ZONE_MACIOTA: Workshop frontage furniture on the shared native ground.
## Legacy slab/curb/ramp coordinates below are retained as empty editor anchors;
## former dimensions explain their original slots, not current raised geometry.
##
## ARCHITECTURAL CONSTRAINTS & GUARANTEES:
## - Independent lifecycle per zone: mount_zone(), unmount_zone(), has_zone(), get_zone().
## - Zero duplication of buildings, facades, NPCs, or vehicles.
## - Zero descriptive/decorative text (AGENTS.md).
## - Flush level crossing at Rodoviária disembark corridor (Y ≈ 0.01m), matching Arrival.gd and HarborTerminalModel3D.
## - Exterior support belongs to NativeRegion; route furniture adds no second paving layer.

const ZONE_RODOVIARIA := "rodoviaria"
const ZONE_CONNECTING_STREETS := "connecting_streets"
const ZONE_DELEGACIA := "delegacia"
const ZONE_MACIOTA := "maciota"
const PLACE_CATALOG := preload("res://world/places/PlaceCatalog.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

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

## O streaming monta a mesma zona em partes, fora da árvore. A ordem dos
## filhos é a ordem original dos IDs piece/route, inclusive âncoras sem malha.
## Não há estado global: cancelar o job libera somente a zona deste pedido.
static func begin_zone(zone_id: String) -> Dictionary:
	var count := {ZONE_RODOVIARIA: 18, ZONE_CONNECTING_STREETS: 12, ZONE_DELEGACIA: 18, ZONE_MACIOTA: 7}
	if not count.has(zone_id): return {}
	var root := Node3D.new()
	root.name = "Zone_" + zone_id
	return {"zone_id": zone_id, "root": root, "index": 0, "count": count[zone_id], "complete": false}

static func step_zone(job: Dictionary, budget_usec: float = 1500.0) -> bool:
	if job.is_empty() or bool(job.get("complete", false)): return true
	var root := job.get("root") as Node3D
	if not is_instance_valid(root):
		job.complete = true
		return true
	var began := Time.get_ticks_usec()
	while int(job.index) < int(job.count):
		var piece_began := STALL_WORK.begin()
		var fragment: Node3D
		match str(job.zone_id):
			ZONE_RODOVIARIA: fragment = _build_rodoviaria_zone(int(job.index))
			ZONE_CONNECTING_STREETS: fragment = _build_connecting_streets(int(job.index))
			ZONE_DELEGACIA: fragment = _build_delegacia_zone(int(job.index))
			ZONE_MACIOTA: fragment = _build_maciota_zone(int(job.index))
		if fragment == null:
			cancel_zone(job)
			return true
		root.transform = fragment.transform
		for child in fragment.get_children():
			fragment.remove_child(child)
			root.add_child(child)
		fragment.free()
		STALL_WORK.finish_slow("harbor_route_zone.%s.piece.%d" % [str(job.zone_id), int(job.index)], piece_began, 2000)
		job.index = int(job.index) + 1
		# Um móvel ainda é indivisível; a próxima peça só começa se houver orçamento.
		if Time.get_ticks_usec() - began >= budget_usec: break
	job.complete = int(job.index) >= int(job.count)
	return bool(job.complete)

static func cancel_zone(job: Dictionary) -> void:
	var root := job.get("root") as Node3D
	if is_instance_valid(root) and root.get_parent() == null: root.free()
	job.clear()


## Retired paving keeps its child slot so saved piece/route/<zone>/<index>
## edits still address the same furniture. No mesh or collider is allocated:
## district paving and the road generator own the continuous, flush floor.
static func _ground_anchor(label: String) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = label
	anchor.set_meta("district_ground_owned",true)
	return anchor

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
			return AABB(Vector3(152.6, 0.0, 97.1), Vector3(25.6, 5.4, 15.1))
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
			return Vector3(164.275, 0.04, 109.625)
		"maciota_bay_entry":
			return Vector3(166.0, 0.08, 109.8)
	return Vector3.ZERO

# ==============================================================================
# Zone 1: Rodoviária (Coach Terminal Plaza & Passenger Corridor)
# ==============================================================================

static func _build_rodoviaria_zone(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	
	# Sidewalk promenade is partitioned into West Wing (X: 92.0 to 103.5) and East Wing (X: 110.5 to 122.0).
	# The central transit corridor (X: 103.5 to 110.5, span 7.0m) is a flush pedestrian level crossing
	# at grade Y = 0.05m, matching Market Street's roadway surface and Arrival.gd disembark trajectory!
	
	# 1. West Wing Slab (11.5m x 4.2m at Y = 0.12m)
	if selected_piece < 0 or selected_piece == 0:
		var slab_w := _ground_anchor("SidewalkSlab")
		slab_w.position = Vector3(97.75, 0.0, 72.4)
		zone.add_child(slab_w)
	
	# West Curb along Market St edge (Z = 74.55)
	if selected_piece < 0 or selected_piece == 1:
		var curb_w := _ground_anchor("CurbSegment")
		curb_w.rotation_degrees = Vector3(0, 90, 0)
		curb_w.position = Vector3(97.75, 0.0, 74.55)
		zone.add_child(curb_w)
	
	# Preserve the intercity exit lane centred at X=121.875. The former wing,
	# bike rack and lamp occupied its swept coach hull and blocked the V1 route.
	if selected_piece < 0 or selected_piece == 2:
		var slab_e := _ground_anchor("SidewalkSlab")
		slab_e.position = Vector3(114.75, 0.0, 72.4)
		zone.add_child(slab_e)
	
	# East Curb along Market St edge (Z = 74.55)
	if selected_piece < 0 or selected_piece == 3:
		var curb_e := _ground_anchor("CurbSegment")
		curb_e.rotation_degrees = Vector3(0, 90, 0)
		curb_e.position = Vector3(114.75, 0.0, 74.55)
		zone.add_child(curb_e)
	
	# 3. Central Passenger Disembarking Level Crossing (X: 103.5 to 110.5, Z: 70.3 to 75.0)
	# Level paving (height = 0.05m, top at Y = 0.05m) matching Market St roadway box exactly.
	# Dante walks from bus door (X ≈ 108.56, Z ≈ 76.31) to ARRIVAL (X = 106.25, Z = 70.625)
	# with > 1.29m clearance to side_ramp_e and zero vertical steps or curb stones.
	if selected_piece < 0 or selected_piece == 4:
		var level_crossing := _ground_anchor("SidewalkSlab")
		level_crossing.position = Vector3(107.0, 0.0, 72.65)
		zone.add_child(level_crossing)
	
	# Tactile yellow edge line marking the pedestrian boundary at Z = 74.55
	if selected_piece < 0 or selected_piece == 5:
		var edge_marker := MeshInstance3D.new()
		edge_marker.name = "BusBayEdgeMarker"
		var em_box := PlaneMesh.new()
		em_box.size = Vector2(7.0, 0.30)
		edge_marker.mesh = em_box
		edge_marker.material_override = HarborRouteMaterials.curb_yellow_marking()
		edge_marker.position = Vector3(107.0, 0.010, 74.55)
		edge_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(edge_marker)
	
	# Side curb ramps transitioning elevated wings down into central corridor
	if selected_piece < 0 or selected_piece == 6:
		var side_ramp_w := _ground_anchor("CurbRamp")
		side_ramp_w.rotation_degrees = Vector3(0, 90, 0)
		side_ramp_w.position = Vector3(103.5, 0.0, 72.4)
		zone.add_child(side_ramp_w)

	if selected_piece < 0 or selected_piece == 7:
		var side_ramp_e := _ground_anchor("CurbRamp")
		side_ramp_e.rotation_degrees = Vector3(0, -90, 0)
		side_ramp_e.position = Vector3(110.5, 0.0, 72.4)
		zone.add_child(side_ramp_e)
	
	# 4. Amenities placed exclusively in the flanking wings:
	# West Wing Amenities (X ≤ 101.5):
	if selected_piece < 0 or selected_piece == 8:
		var bench_w := HarborRouteProps.create_bench(2.2)
		bench_w.position = Vector3(98.5, 0.008, 71.0)
		zone.add_child(bench_w)

	if selected_piece < 0 or selected_piece == 9:
		var bin_w := HarborRouteProps.create_trash_bin()
		bin_w.position = Vector3(95.0, 0.008, 71.2)
		zone.add_child(bin_w)

	if selected_piece < 0 or selected_piece == 10:
		var light_w := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(90.0))
		light_w.position = Vector3(93.5, 0.008, 73.8)
		zone.add_child(light_w)

	if selected_piece < 0 or selected_piece == 11:
		var planter_w := HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85))
		planter_w.position = Vector3(101.5, 0.008, 73.4)
		zone.add_child(planter_w)
	
	# East Wing Amenities (X ≥ 113.0):
	if selected_piece < 0 or selected_piece == 12:
		var planter_e := HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85))
		planter_e.position = Vector3(112.8, 0.008, 73.4)
		zone.add_child(planter_e)

	if selected_piece < 0 or selected_piece == 13:
		var bench_e := HarborRouteProps.create_bench(2.2)
		bench_e.position = Vector3(115.5, 0.008, 71.0)
		zone.add_child(bench_e)

	if selected_piece < 0 or selected_piece == 14:
		var bin_e := HarborRouteProps.create_trash_bin()
		bin_e.position = Vector3(118.0, 0.008, 71.2)
		zone.add_child(bin_e)

	if selected_piece < 0 or selected_piece == 15:
		var light_e := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(90.0))
		light_e.position = Vector3(118.5, 0.008, 73.8)
		zone.add_child(light_e)

	if selected_piece < 0 or selected_piece == 16:
		var bike_rack := HarborRouteProps.create_bike_rack(4, 0.85)
		bike_rack.position = Vector3(115.5, 0.008, 73.8)
		zone.add_child(bike_rack)
	
	# Storm drain grate in street gutter outside west wing
	if selected_piece < 0 or selected_piece == 17:
		var drain := HarborRouteProps.create_drain_grate()
		drain.position = Vector3(101.5, 0.0, 74.85)
		zone.add_child(drain)
	
	return zone

# ==============================================================================
# Zone 2: Connecting Streets (Market Street & Union Avenue Corridors)
# ==============================================================================

static func _build_connecting_streets(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	
	# 1. Northern sidewalk of Market St towards Union Ave (X: 85.6 to 92.0, Z: 72.5 to 74.5)
	# Começa em 85.6, alinhada à calçada leste da Union Ave: a Union Ave ocupa X 77.2–85.3
	# e a versão anterior (X 83.0) avançava 2.3 m sobre a pista, bloqueando carros no cruzamento.
	if selected_piece < 0 or selected_piece == 0:
		var slab_market := _ground_anchor("SidewalkSlab")
		slab_market.position = Vector3(88.8, 0.0, 73.5)
		zone.add_child(slab_market)
	
	# Curb along Market St edge, trimmed to start past the pedestrian curb ramp at X = 87.8 (X: 87.8 to 92.0, span 4.2m)
	# Eliminates collider overlap between the vertical curb and the beveled ramp wedge (X: 85.6 to 87.8)
	if selected_piece < 0 or selected_piece == 1:
		var curb_market := _ground_anchor("CurbSegment")
		curb_market.rotation_degrees = Vector3(0, 90, 0)
		curb_market.position = Vector3(89.9, 0.0, 74.55)
		zone.add_child(curb_market)
	
	# Pedestrian curb cut ramp at Market/Union intersection corner (X: 85.6 to 87.8, span 2.2m)
	if selected_piece < 0 or selected_piece == 2:
		var ramp_market := _ground_anchor("CurbRamp")
		ramp_market.position = Vector3(86.7, 0.0, 74.55)
		zone.add_child(ramp_market)
	
	# 2. Pedestrian crosswalk across Market St at Union Ave corner
	if selected_piece < 0 or selected_piece == 3:
		var crosswalk_market := HarborRouteProps.create_crosswalk_stripes(3.5, 7.5, 6)
		crosswalk_market.position = Vector3(82.5, 0.0, 78.125)
		zone.add_child(crosswalk_market)
	
	# 3. Eastern sidewalk along Union Avenue (runs North-South from Z: 82.0 to 128.0 at X: 86.8)
	if selected_piece < 0 or selected_piece == 4:
		var slab_union_n := _ground_anchor("SidewalkSlab")
		slab_union_n.position = Vector3(86.8, 0.0, 94.0)
		zone.add_child(slab_union_n)
	
	# Medical Garden Lane crosses here (Z 119.875–125.125). The former
	# continuous slab and curb cut across both lanes beside Harbor Patrol.
	if selected_piece < 0 or selected_piece == 5:
		for span in [Vector2(105.0,119.4), Vector2(125.6,127.0)]:
			var slab := _ground_anchor("SidewalkSlab")
			slab.position = Vector3(86.8, 0.0, (span.x+span.y)*.5)
			zone.add_child(slab)
			var curb := _ground_anchor("CurbSegment")
			curb.position = Vector3(85.5, 0.0, (span.x+span.y)*.5)
			zone.add_child(curb)

		# Curbs facing the Union Ave roadway (at X = 85.5)
	if selected_piece < 0 or selected_piece == 6:
		var curb_union_n := _ground_anchor("CurbSegment")
		curb_union_n.position = Vector3(85.5, 0.0, 94.0)
		zone.add_child(curb_union_n)
	
	# Streetlights spaced every ~20m along Union Avenue
	if selected_piece < 0 or selected_piece == 7:
		var light_u1 := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(-90.0))
		light_u1.position = Vector3(87.5, 0.008, 94.0)
		zone.add_child(light_u1)
	
	if selected_piece < 0 or selected_piece == 8:
		var light_u2 := HarborRouteProps.create_streetlight(5.4, 1.35, "standard", deg_to_rad(-90.0))
		light_u2.position = Vector3(87.5, 0.008, 115.0)
		zone.add_child(light_u2)
	
	# Municipal fire hydrant near the midway junction
	if selected_piece < 0 or selected_piece == 9:
		var hydrant_mid := HarborRouteProps.create_fire_hydrant()
		hydrant_mid.position = Vector3(87.4, 0.008, 102.5)
		zone.add_child(hydrant_mid)
	
	# Storm drains along curb
	if selected_piece < 0 or selected_piece == 10:
		var drain_u1 := HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85))
		drain_u1.position = Vector3(85.2, 0.0, 92.0)
		zone.add_child(drain_u1)
	
	if selected_piece < 0 or selected_piece == 11:
		var drain_u2 := HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85))
		drain_u2.position = Vector3(85.2, 0.0, 118.0)
		zone.add_child(drain_u2)
	
	return zone

# ==============================================================================
# Zone 3: Delegacia (Harbor Patrol Precinct Forecourt)
# ==============================================================================

static func _build_delegacia_zone(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	
	# Dock Street is now 14 m wide: its north asphalt edge is Z = 130.5.
	# Keep every raised part behind that edge; the sewer opening remains in the road.
	# Four paving panels preserve the editor's existing child IDs (crosswalk = 17).
	var paving := [
		Rect2(56.0, 125.0, 10.0, 2.35),
		Rect2(56.0, 127.35, 10.0, 2.35),
		Rect2(66.0, 125.0, 10.0, 2.35),
		Rect2(66.0, 127.35, 10.0, 2.35)
	]
	for index in range(paving.size()):
		if selected_piece >= 0 and selected_piece != index: continue
		var piece: Rect2 = paving[index]
		if not piece.has_area(): continue
		var slab := _ground_anchor("SidewalkSlab")
		slab.position = Vector3(piece.get_center().x, 0.0, piece.get_center().y)
		zone.add_child(slab)

	# Curbs flank the central accessible approach, entirely on the sidewalk.
	if selected_piece < 0 or selected_piece == 4:
		var curb_w := _ground_anchor("CurbSegment")
		curb_w.rotation_degrees = Vector3(0, 90, 0)
		curb_w.position = Vector3(59.5, 0.0, 129.85)
		zone.add_child(curb_w)

	if selected_piece < 0 or selected_piece == 5:
		var curb_e := _ground_anchor("CurbSegment")
		curb_e.rotation_degrees = Vector3(0, 90, 0)
		curb_e.position = Vector3(72.5, 0.0, 129.85)
		zone.add_child(curb_e)
	
	# Former six-metre ramp slot: approach and forecourt are now flush.
	if selected_piece < 0 or selected_piece == 6:
		var p_ramp := _ground_anchor("CurbRamp")
		p_ramp.position = Vector3(66.0, 0.0, 130.1)
		zone.add_child(p_ramp)
	
	# Institutional Police streetlights (Twin globe civic lamps with navy blue base)
	if selected_piece < 0 or selected_piece == 7:
		var p_light_w := HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0)
		p_light_w.position = Vector3(57.0, 0.008, 128.8)
		zone.add_child(p_light_w)
	
	if selected_piece < 0 or selected_piece == 8:
		var p_light_e := HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0)
		p_light_e.position = Vector3(75.0, 0.008, 128.8)
		zone.add_child(p_light_e)
	
	# Anti-ram security bollards with police navy finish and reflective bands
	# Flank the entrance, keeping the central six-metre ramp unobstructed.
	var bollard_xs := [57.5, 59.0, 60.5, 71.5, 74.5]
	for index in range(bollard_xs.size()):
		if selected_piece >= 0 and selected_piece != 9 + index: continue
		var bollard := HarborRouteProps.create_bollard("police")
		bollard.position = Vector3(bollard_xs[index], 0.008, 129.1)
		zone.add_child(bollard)

	# Public civic bench on the quiet west side of the forecourt
	if selected_piece < 0 or selected_piece == 14:
		var bench := HarborRouteProps.create_bench(2.0)
		bench.position = Vector3(58.0, 0.008, 126.8)
		bench.rotation_degrees = Vector3(0, 90, 0)
		zone.add_child(bench)
	
	# Litter bin near east corner
	if selected_piece < 0 or selected_piece == 15:
		var bin := HarborRouteProps.create_trash_bin()
		bin.position = Vector3(74.0, 0.008, 127.5)
		zone.add_child(bin)
	
	# Keep the manhole beside the forecourt clear for the lid and ladder access.
	
	# Storm drain grate in street gutter beside the west curb wing (clear of pedestrian ramp)
	if selected_piece < 0 or selected_piece == 16:
		var drain := HarborRouteProps.create_drain_grate()
		drain.position = Vector3(62.0, 0.0, 130.35)
		zone.add_child(drain)
	
	# Crosswalk across Dock Street connecting to harbor quays
	if selected_piece < 0 or selected_piece == 17:
		var crosswalk_dock := HarborRouteProps.create_crosswalk_stripes(3.6, 7.5, 6)
		crosswalk_dock.position = Vector3(67.5, 0.0, 137.5)
		zone.add_child(crosswalk_dock)
	
	return zone

# ==============================================================================
# Zone 4: Garagem do Maciota (Westgate Motor Co. Frontage & Apron)
# ==============================================================================

static func _build_maciota_zone(selected_piece := -1) -> Node3D:
	var zone := Node3D.new()
	# Existing apron props follow the workshop's new industrial anchor.
	zone.position = Vector3(2696.0/16-790.0/16,0,1624.0/16-1495.0/16)
	
	# Sidewalk frontage running in front of the workshop (X: 39.5 to 57.0, Z: 101.25 to 104.6).
	# No separate slab mesh here: any raised or differently-colored box reads as a second
	# sidewalk stacked on the district's own flat paving underneath it, no matter how thin
	# or how closely its color is matched. The flat HarborUrbanSurface3D paving (already
	# exposed here, see HarborUrbanSurface3D._RAISED_APRON_HOLES) is the sidewalk; this zone
	# only adds curb/ramp/props on top of it.

	# The freight-yard frontage has continuous native paving at road level.
	# The old 3 cm wedge joined a raised apron at the previous garage; here it
	# connected no height change and its vertical side obstructed westbound
	# vehicles. The native floor remains the supported, full-width access.

	# Granite curb on the east pedestrian sidewalk flank (X: 50.8 to 57.0)
	if selected_piece < 0 or selected_piece == 0:
		var curb_e := _ground_anchor("CurbSegment")
		curb_e.rotation_degrees = Vector3(0, 90, 0)
		curb_e.position = Vector3(55.375, 0.0, 91.9375)
		zone.add_child(curb_e)

	# High-visibility yellow safety bollard placed on the east curb corner (X = 51.2, clear of vehicle bay)
	# Note: West bollard at X = 42.5 was removed to clear Arrival.gd's tour car arrival stop at (42.5, 0, 104.55).
	if selected_piece < 0 or selected_piece == 1:
		var bollard_e := HarborRouteProps.create_bollard("hazard")
		bollard_e.position = Vector3(54.575, 0.03, 91.7375)
		zone.add_child(bollard_e)

	# The utility corner lights the court from the east. Its pole stays outside
	# the full turning hull and the car's forward obstacle sensor.
	if selected_piece < 0 or selected_piece == 2:
		var ind_light := HarborRouteProps.create_streetlight(5.2, 1.1, "industrial", deg_to_rad(45.0))
		ind_light.position = Vector3(55.675, 0.03, 90.9375)
		zone.add_child(ind_light)

	# Fire hydrant on the far east sidewalk corner (X = 56.2)
	if selected_piece < 0 or selected_piece == 3:
		var hydrant := HarborRouteProps.create_fire_hydrant()
		hydrant.position = Vector3(55.675, 0.03, 93.0375)
		zone.add_child(hydrant)

	# Heavy scrap metal / oil drum hopper on the east apron
	if selected_piece < 0 or selected_piece == 4:
		var drum := MeshInstance3D.new()
		drum.name = "ScrapOilDrum"
		var d_cyl := CylinderMesh.new()
		d_cyl.top_radius = 0.32
		d_cyl.bottom_radius = 0.32
		d_cyl.height = 0.85
		drum.mesh = d_cyl
		drum.material_override = HarborRouteMaterials.cast_iron_dark()
		drum.position = Vector3(54.875, 0.03 + 0.425, 92.7375)
		zone.add_child(drum)

	if selected_piece < 0 or selected_piece == 5:
		var drum_body := StaticBody3D.new()
		drum_body.name = "DrumCollision"
		drum_body.collision_layer = 1
		drum_body.collision_mask = 0
		var d_col := CollisionShape3D.new()
		var d_shape := CylinderShape3D.new()
		d_shape.radius = 0.35
		d_shape.height = 0.85
		d_col.shape = d_shape
		d_col.position = Vector3(54.875, 0.03 + 0.425, 92.7375)
		drum_body.add_child(d_col)
		zone.add_child(drum_body)
	
	# Storm drain grate in street gutter outside the driveway
	if selected_piece < 0 or selected_piece == 6:
		var drain := HarborRouteProps.create_drain_grate()
		drain.position = Vector3(55.375, 0.0, 102.6875)
		zone.add_child(drain)
	
	return zone
