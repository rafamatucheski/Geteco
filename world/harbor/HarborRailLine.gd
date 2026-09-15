@tool
extends "res://world/shared/rail/DistrictRailLine.gd"

## Circuito único porto–serra. A cidade mantém seu viaduto e sua descida;
## túneis unem os trechos visíveis sem reiniciar nem duplicar a composição.
const TRAIN_SCRIPT := preload("res://world/harbor/HarborTrain.gd")
const REGIONAL_ROUTE := preload("res://world/shared/rail/HarborMountainRailRoute.gd")
const STRUCTURE_3D := preload("res://world/shared/rail/RailStructure3D.gd")
const DECK_WIDTH := 48.0
const DECK_ELEVATION := 64.0
const WEST_PORTAL := Vector2(0, 892)
const EAST_PORTAL := Vector2(3114, 3320)
var _visible_start := 0.0
var _visible_end := 0.0
var _ramp_start := 0.0
var _pillar_bounds: Array[Rect2] = []
var _ground_barriers: Array[Rect2] = []
var _underpass_material: ShaderMaterial
var _reveal_amount := 0.0
var _reveal_position := Vector2.ZERO
var _reveal_radius := 76.0
var regional_route: RefCounted
var _regional_scenery: Node2D


class PortalCover extends Node2D:
	var east := false
	var snowy := false
	func _ready() -> void:
		var model = load("res://world/shared/rail/RailStructure3D.gd").new()
		add_child(model)
		# Geometry rotates in 3D; the orthographic camera stays aligned to the world.
		var heading := rotation
		rotation = 0.0
		for side in [-1.0,1.0]:
			model.box(Vector2(18,side*35).rotated(heading),Vector3(80,48,14),16,heading,"92998e")
			model.box(Vector2(-25,side*35).rotated(heading),Vector3(12,52,18),16,heading,"bdbeac")
		model.box(Vector2(18,0).rotated(heading),Vector3(86,12,84),44,heading,"737e75")
		model.box(Vector2(-26,0).rotated(heading),Vector3(14,15,88),45,heading,"b3b6a7")
		if snowy: model.box(Vector2(18,0).rotated(heading),Vector3(88,3,86),51,heading,"e5eef3")
		model.finish()



class ViaductShadow extends Node2D:
	var points := PackedVector2Array()
	var pillars: Array[Rect2] = []
	func _draw() -> void:
		if points.size() > 1:
			draw_polyline(points, Color(0.035, 0.045, 0.045, 0.25), 54.0, true)
		for rect in pillars:
			draw_rect(Rect2(rect.position + Vector2(8, 11), rect.size + Vector2(14, 14)), Color(0.04, 0.05, 0.05, 0.28))



class RampDeck extends Node2D:
	var rail: Node2D


func _ready() -> void:
	get_underpass_material()
	material = _underpass_material
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
	STRUCTURE_3D.track(self, self, _visible_start, _ramp_start)
	STRUCTURE_3D.track(ramp, self, _ramp_start, _visible_end)
	STRUCTURE_3D.barriers(ramp, _ground_barriers)
	_create_portals()
	_regional_scenery = preload("res://world/shared/rail/RegionalRailScenery.gd").new()
	_regional_scenery.name = "HarborMountainRailScenery"
	add_child(_regional_scenery)
	_regional_scenery.build(self)
	if not Engine.is_editor_hint():
		add_to_group("regional_railway")
		var map_overlay := preload("res://world/shared/rail/RailMinimapOverlay.gd").new()
		map_overlay.rail = self
		add_child(map_overlay)
	set_process(not Engine.is_editor_hint())


func get_underpass_material() -> ShaderMaterial:
	if _underpass_material == null:
		_underpass_material = ShaderMaterial.new()
		_underpass_material.shader = preload("res://world/shared/rail/RailUnderpassReveal.gdshader")
	return _underpass_material


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var target := player
	var travel := get_node_or_null("/root/RegionTravel")
	if travel != null:
		var car: Node2D = travel.controlled_car()
		if is_instance_valid(car): target = car
	var active := false
	if is_instance_valid(target) and is_instance_valid(player):
		var outside := not bool(player.get_meta("harbor_interior", false)) and not bool(player.get_meta("mountain_interior", false))
		var point := to_local(target.global_position)
		var offset := _route.get_closest_offset(point)
		var state := get_track_state_at_offset(offset)
		active = outside and bool(state.above_ground) and float(state.elevation) >= 48.0 and point.distance_to(_route.sample_baked(offset, true)) < 70.0
		_reveal_position = target.global_position
		_reveal_radius = 96.0 if target != player else 76.0
	_reveal_amount = move_toward(_reveal_amount, 1.0 if active else 0.0, delta * 5.0)
	_underpass_material.set_shader_parameter("reveal_position", _reveal_position)
	_underpass_material.set_shader_parameter("reveal_amount", _reveal_amount)
	_underpass_material.set_shader_parameter("reveal_radius", _reveal_radius)


func build_route() -> void:
	regional_route = REGIONAL_ROUTE.new()
	_route = regional_route.curve
	_baked_points = _route.get_baked_points()
	_visible_start = _route.get_closest_offset(WEST_PORTAL)
	_visible_end = _route.get_closest_offset(EAST_PORTAL)
	_ramp_start = _route.get_closest_offset(Vector2(3114, 2320))


func get_track_state_at_offset(offset: float) -> Dictionary:
	var progress := fposmod(offset, maxf(1.0, get_route_length()))
	var section: Dictionary = regional_route.section_at(progress)
	if not section.is_empty() and String(section.id) != "harbor":
		var alpha := minf(clampf((progress - float(section.start)) / 28.0, 0.0, 1.0), clampf((float(section.end) - progress) / 28.0, 0.0, 1.0))
		return {"above_ground": true, "elevation": DECK_ELEVATION, "opacity": alpha, "z_index": 15, "section": section.id, "region": "mountain" if String(section.id) == "mountain" else "connection"}
	var above_ground := progress >= _visible_start and progress <= _visible_end
	var elevation := DECK_ELEVATION
	if progress > _ramp_start:
		elevation = lerpf(DECK_ELEVATION, -12.0, clampf((progress - _ramp_start) / maxf(1.0, _visible_end - _ramp_start), 0.0, 1.0))
	if not above_ground:
		elevation = -12.0
	var opacity := 0.0
	if above_ground:
		opacity = minf(clampf((progress - _visible_start) / 18.0, 0, 1), clampf((_visible_end - progress) / 18.0, 0, 1))
	return {"above_ground": above_ground, "elevation": elevation, "opacity": opacity, "z_index": 15 if elevation >= 16.0 else 4, "section": "harbor" if above_ground else "tunnel", "region": "harbor" if above_ground else "transit"}


func get_regional_route_data() -> Dictionary:
	var data: Dictionary = regional_route.get_route_data()
	for section in data.sections:
		var transformed := PackedVector2Array()
		for point in section.points: transformed.append(to_global(point))
		section.points = transformed
	for landmark in data.landmarks: landmark.position = to_global(landmark.position)
	return data


func get_cruise_speed_at_offset(offset: float) -> float:
	var section: Dictionary = regional_route.section_at(offset)
	if not section.is_empty(): return 105.0 if String(section.id) == "harbor" else 118.0
	# Acelera apenas depois que o último vagão entrou e freia antes do portal.
	var length := get_route_length()
	for visible_section in regional_route.sections:
		if fposmod(offset - float(visible_section.end), length) < 560.0 or fposmod(float(visible_section.start) - offset, length) < 1000.0:
			return 105.0
	return 280.0


func get_rail_graph_data() -> Dictionary:
	var result := super.get_rail_graph_data()
	result["id"] = "harbor_mountain_freight_corridor"
	result["control_points_local"] = PackedVector2Array(regional_route.points)
	result["handoffs"] = get_rail_handoffs()
	result["ballast_width"] = DECK_WIDTH
	result["visible_start"] = _visible_start
	result["visible_end"] = _visible_end
	result["elevated_end"] = _ramp_start
	result["closed_underground_return"] = false
	result["regional_route"] = get_regional_route_data()
	return result


func get_elevated_crossing_data(world_position: Vector2) -> Dictionary:
	var offset := _route.get_closest_offset(to_local(world_position))
	var state := get_track_state_at_offset(offset)
	state["rail_offset"] = offset
	state["position"] = to_global(_route.sample_baked(offset, true))
	state["classification"] = "rail_elevated" if float(state.elevation) >= 48.0 else ("rail_underground" if not state.above_ground else "at_grade")
	return state


func get_pillar_bounds() -> Array[Rect2]:
	var result := _pillar_bounds.duplicate()
	if is_instance_valid(_regional_scenery): result.append_array(_regional_scenery.supports)
	return result


func get_ground_barrier_bounds() -> Array[Rect2]:
	return _ground_barriers.duplicate()


func get_rail_handoffs() -> Array[Dictionary]:
	return [{"id": "HarborMountainRailConnection", "position": to_global(Vector2(7300,-4920)), "from_region": "harbor", "to_region": "mountain", "connection_type": "rail", "continuous": true}]


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
	if get_parent().has_node("ArrivalStop"):
		# The terminal's east bus lane passes beneath the viaduct. Its support
		# belongs in the central island, outside the complete swept coach hull.
		proposed[6] = Vector2(2005, 873)
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
	STRUCTURE_3D.supports(shadow, _pillar_bounds)


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
	var entries := [["WestPortal", WEST_PORTAL, false, PI], ["EastPortal", EAST_PORTAL, true, PI * 0.5]]
	for section in regional_route.sections:
		if String(section.id) == "harbor": continue
		for edge in ["start", "end"]:
			var offset: float = section[edge]
			entries.append(["%s_%s_portal" % [section.id,edge], _route.sample_baked(offset,true), edge == "end", _route_tangent(offset).angle() + (PI if edge == "start" else 0.0)])
	for entry in entries:
		if get_node_or_null(entry[0]) != null:
			continue
		var portal := PortalCover.new()
		portal.name = entry[0]
		portal.position = entry[1]
		portal.east = entry[2]
		portal.snowy = portal.position.y < -6460.0
		portal.rotation = entry[3]
		portal.z_as_relative = false
		portal.z_index = 16
		add_child(portal)


func _draw() -> void:
	pass
