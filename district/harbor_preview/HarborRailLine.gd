@tool
extends "res://district/rail/DistrictRailLine.gd"

## Single-track viaduct; closed return is underground. Streets beneath retain
## their ground-level collision/navigation. Supports have audited footprints.
const TRAIN_SCRIPT := preload("res://district/harbor_preview/HarborTrain.gd")
const DECK_WIDTH := 48.0
const DECK_ELEVATION := 64.0
const WEST_PORTAL := Vector2(0, 892)
const EAST_PORTAL := Vector2(3114, 3320)
const HARBOR_ROUTE := [
	Vector2(-700, 892), WEST_PORTAL, Vector2(2814, 892),
	Vector2(3114, 1192), Vector2(3114, 2240), EAST_PORTAL,
	Vector2(3114, 3850), Vector2(-700, 3850), Vector2(-900, 3000),
	Vector2(-900, 1100), Vector2(-700, 892),
]
var _visible_start := 0.0
var _visible_end := 0.0
var _ramp_start := 0.0
var _pillar_bounds: Array[Rect2] = []
var _ground_barriers: Array[Rect2] = []


class PortalCover extends Node2D:
	var east := false
	func _draw() -> void:
		draw_rect(Rect2(-25, -41, 123, 82), Color("#59655c"))
		# A recessed mouth and covered roof read as a tunnel, not a track bumper.
		draw_rect(Rect2(-22, -28, 54, 56), Color("#111c24"))
		draw_rect(Rect2(13, -28, 19, 56), Color("#080f14"))
		draw_rect(Rect2(32, -37, 62, 74), Color("#717767"))
		draw_line(Vector2(35, -32), Vector2(89, -32), Color("#939582"), 3)
		draw_rect(Rect2(-30, -38, 17, 76), Color("#b5b4a4"))
		for side in [-1.0, 1.0]:
			draw_rect(Rect2(-28, side * 30.0 - 4.0, 24, 8), Color("#ddd0a1"))
		# Architectural keystone and masonry relief replacing painted text
		draw_rect(Rect2(-14, -46, 28, 8), Color("#828678"))
		draw_rect(Rect2(-9, -48, 18, 3), Color("#a2a696"))



class ViaductShadow extends Node2D:
	var points := PackedVector2Array()
	var pillars: Array[Rect2] = []
	func _draw() -> void:
		if points.size() > 1:
			draw_polyline(points, Color(0.035, 0.045, 0.045, 0.25), 54.0, true)
		for rect in pillars:
			draw_rect(Rect2(rect.position + Vector2(8, 11), rect.size + Vector2(14, 14)), Color(0.04, 0.05, 0.05, 0.28))
			draw_rect(rect.grow(3), Color("#545f60"))
			draw_rect(rect, Color("#b1b2a3"))


class RampDeck extends Node2D:
	var rail: Node2D
	func _draw() -> void:
		if is_instance_valid(rail):
			rail.draw_track(self, rail._ramp_start, rail._visible_end)


func _ready() -> void:
	if not Engine.is_editor_hint() and get_node_or_null("AmbientTrain") == null:
		var train := TRAIN_SCRIPT.new()
		train.name = "AmbientTrain"
		train.start_progress = 1380.0
		add_child(train)
	train_speed = 105.0
	freight_car_count = 6
	super._ready()
	z_index = 14
	if Engine.is_editor_hint():
		_create_track_safety_boundaries()
	var ramp := RampDeck.new()
	ramp.name = "RampDeck"
	ramp.rail = self
	ramp.z_as_relative = false
	ramp.z_index = 3
	add_child(ramp)
	_create_portals()


func build_route() -> void:
	_route = Curve2D.new()
	_route.bake_interval = 6.0
	var handles := [Vector2(140, 0), Vector2(180, 0), Vector2(165, 0), Vector2(0, 165), Vector2(0, 100), Vector2(0, 100), Vector2(-180, 180), Vector2(-180, -40), Vector2(0, -170), Vector2(0, -120), Vector2(140, 0)]
	for index in HARBOR_ROUTE.size():
		_route.add_point(HARBOR_ROUTE[index], -handles[index], handles[index])
	_baked_points = _route.get_baked_points()
	_visible_start = _route.get_closest_offset(WEST_PORTAL)
	_visible_end = _route.get_closest_offset(EAST_PORTAL)
	_ramp_start = _route.get_closest_offset(Vector2(3114, 2320))


func get_track_state_at_offset(offset: float) -> Dictionary:
	var progress := fposmod(offset, maxf(1.0, get_route_length()))
	var above_ground := progress >= _visible_start and progress <= _visible_end
	var elevation := DECK_ELEVATION
	if progress > _ramp_start:
		elevation = lerpf(DECK_ELEVATION, -12.0, clampf((progress - _ramp_start) / maxf(1.0, _visible_end - _ramp_start), 0.0, 1.0))
	if not above_ground:
		elevation = -12.0
	var opacity := 0.0
	if above_ground:
		opacity = minf(clampf((progress - _visible_start) / 18.0, 0, 1), clampf((_visible_end - progress) / 18.0, 0, 1))
	return {"above_ground": above_ground, "elevation": elevation, "opacity": opacity, "z_index": 15 if elevation >= 16.0 else 4}


func get_rail_graph_data() -> Dictionary:
	var result := super.get_rail_graph_data()
	result["id"] = "harbor_elevated_freight_corridor"
	result["control_points_local"] = PackedVector2Array(HARBOR_ROUTE)
	result["handoffs"] = []
	result["ballast_width"] = DECK_WIDTH
	result["visible_start"] = _visible_start
	result["visible_end"] = _visible_end
	result["elevated_end"] = _ramp_start
	result["closed_underground_return"] = true
	return result


func get_elevated_crossing_data(world_position: Vector2) -> Dictionary:
	var offset := _route.get_closest_offset(to_local(world_position))
	var state := get_track_state_at_offset(offset)
	state["rail_offset"] = offset
	state["position"] = to_global(_route.sample_baked(offset, true))
	state["classification"] = "rail_elevated" if float(state.elevation) >= 48.0 else ("rail_underground" if not state.above_ground else "at_grade")
	return state


func get_pillar_bounds() -> Array[Rect2]:
	return _pillar_bounds.duplicate()


func get_ground_barrier_bounds() -> Array[Rect2]:
	return _ground_barriers.duplicate()


func get_rail_handoffs() -> Array[Dictionary]:
	return []


func _ensure_connection_marker() -> void:
	pass


func _create_track_safety_boundaries() -> void:
	# No inherited continuous fence may appear under the elevated track.
	if get_node_or_null("RailSafetyBoundaries") != null:
		return
	_pillar_bounds.clear()
	_ground_barriers.clear()
	var body := StaticBody2D.new()
	body.name = "RailSafetyBoundaries"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("rail_safety_boundary")
	var proposed := [Vector2(150, 892), Vector2(600, 873), Vector2(800, 873), Vector2(1000, 873), Vector2(1180, 892), Vector2(1690, 873), Vector2(2050, 873), Vector2(2330, 892), Vector2(2400, 873), Vector2(2820, 873), Vector2(2880, 925), Vector2(3114, 1360), Vector2(3114, 1800), Vector2(3114, 2150)]
	for point in proposed:
		var rect := Rect2(point - Vector2(6, 9), Vector2(12, 18))
		if not _pillar_is_clear(rect):
			continue
		_pillar_bounds.append(rect)
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		collision.position = rect.get_center()
		body.add_child(collision)
	# The long descent starts beyond Dock Street's entire sidewalk envelope.
	# Only its sides are fenced at ground level, never streets under the viaduct.
	for side in [-1.0, 1.0]:
		var rect := Rect2(3114 + side * 32.0 - 3.0, 2320, 6, 1000)
		_ground_barriers.append(rect)
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		collision.position = rect.get_center()
		body.add_child(collision)
	add_child(body)
	var shadow := get_node_or_null("ViaductShadow") as ViaductShadow
	if shadow == null:
		shadow = ViaductShadow.new()
		shadow.name = "ViaductShadow"
		shadow.z_as_relative = false
		shadow.z_index = 3
		add_child(shadow)
	shadow.points = PackedVector2Array()
	var distance := _visible_start
	while distance <= _ramp_start:
		shadow.points.append(_route.sample_baked(distance, true) + Vector2(11, 24))
		distance += 10.0
	shadow.pillars = _pillar_bounds.duplicate()
	shadow.queue_redraw()


func _pillar_is_clear(rect: Rect2) -> bool:
	var network := get_node_or_null("../RoadNetwork")
	if network == null:
		network = get_node_or_null("../../RoadNetwork")
	if network != null:
		for road in network.get_graph_data().get("roads", []):
			var points: PackedVector2Array = road.points
			for index in range(points.size() - 1):
				var reserved := Rect2(network.to_global(points[index]), Vector2.ZERO).expand(network.to_global(points[index + 1])).grow(float(road.width) * 0.5 + 42.0)
				if reserved.intersects(Rect2(to_global(rect.position), rect.size)):
					return false
	var district := get_node_or_null("../District")
	if district != null:
		for site in district.sites:
			if (site.bounds as Rect2).grow(8).intersects(rect):
				return false
		for access in district.accesses:
			if (access.bounds as Rect2).grow(8).intersects(rect):
				return false
	return true


func _create_portals() -> void:
	for entry in [["WestPortal", WEST_PORTAL, false, PI], ["EastPortal", EAST_PORTAL, true, PI * 0.5]]:
		if get_node_or_null(entry[0]) != null:
			continue
		var portal := PortalCover.new()
		portal.name = entry[0]
		portal.position = entry[1]
		portal.east = entry[2]
		portal.rotation = entry[3]
		portal.z_as_relative = false
		portal.z_index = 16
		add_child(portal)


func _draw() -> void:
	draw_track(self, _visible_start, _ramp_start)


func draw_track(target: Node2D, from_distance: float, to_distance: float) -> void:
	if _baked_points.size() < 2:
		return
	var visible_points := PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var distance := from_distance
	while distance <= to_distance:
		var point := _route.sample_baked(distance, true)
		var normal := _route_tangent(distance).orthogonal()
		visible_points.append(point)
		left.append(point + normal * TRACK_GAUGE * 0.5)
		right.append(point - normal * TRACK_GAUGE * 0.5)
		distance += 6.0
	target.draw_polyline(visible_points, Color("#353f44"), DECK_WIDTH, true)
	target.draw_polyline(visible_points, Color("#b7b4a5"), DECK_WIDTH - 5.0, true)
	target.draw_polyline(visible_points, Color("#696861"), DECK_WIDTH - 12.0, true)
	distance = from_distance
	while distance <= to_distance:
		var point := _route.sample_baked(distance, true)
		var normal := _route_tangent(distance).orthogonal()
		target.draw_line(point - normal * 15.0, point + normal * 15.0, Color("#3e3a34"), 4.0, true)
		distance += SLEEPER_SPACING
	target.draw_polyline(left, Color("#d8dfdc"), 3.0, true)
	target.draw_polyline(right, Color("#d8dfdc"), 3.0, true)
	if from_distance >= _ramp_start:
		for rect in _ground_barriers:
			target.draw_rect(rect, Color("#505e62"))
			target.draw_line(rect.position + Vector2(3, 0), rect.end - Vector2(3, 0), Color("#c5c3ac"), 2.0)
			for y in range(int(rect.position.y), int(rect.end.y), 50):
				target.draw_rect(Rect2(rect.position.x - 3, y, 12, 5), Color("#a5aaa0"))
