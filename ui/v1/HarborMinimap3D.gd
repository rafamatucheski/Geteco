extends Control
## V1 cached-vector minimap composition over the current 3D region data.

class MapCanvas extends Control:
	var minimap: Control
	func _draw() -> void:
		if is_instance_valid(minimap): minimap.draw_map(self)

const MAP_SIZE := Vector2(184, 184)
const PANEL_SIZE := MAP_SIZE + Vector2(8, 8)
const SCALE := 1.92 # V1 0.12 px/source-unit, with the V2 1:16 world conversion.

var world: Node
var canvas: MapCanvas
var caption: Label
var center := Vector2.ZERO
var heading := 0.0
var objective_target := Vector2.ZERO
var _tick := 0.0
var _cached_region_id := 0
var _roads: Array[Dictionary] = []
var _buildings: Array[Rect2] = []
var _entries := PackedVector2Array()
var _drawn_center := Vector2(INF, INF)
var _drawn_heading := INF
var _drawn_objective := Vector2(INF, INF)
var _redraw_required := true

func _ready() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	var background := ColorRect.new()
	background.color = Color("08090b")
	background.size = PANEL_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var clip := Control.new()
	clip.position = Vector2(4, 4)
	clip.size = MAP_SIZE
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	canvas = MapCanvas.new()
	canvas.minimap = self
	canvas.size = MAP_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(8, MAP_SIZE.y - 18)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color("ffb565"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = "N ↑"
	add_child(caption)

func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.1: return
	_tick = 0.0
	refresh()

func refresh() -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player) or not is_instance_valid(world.production) or not is_instance_valid(world.session):
		hide()
		return
	var was_visible := visible
	# Boarding temporarily owns movement but remains in the same outdoor world.
	# Keep navigation stable through approach/door/seat, without revealing it in
	# menus, rescue or unrelated scripted movement locks.
	var boarding: bool = is_instance_valid(world.driving) and world.driving.is_body_transition_active()
	var blocked := bool(world.session.get("modal")) or get_tree().paused or bool(world.session.get("rescue_pending")) or bool(world.session.get("arrest_pending")) or (bool(world.player.get("input_locked")) and not boarding) or not str(world.session.state.place_id).is_empty()
	visible = not blocked
	if not visible: return
	var actor: Node3D = world.driving.car if is_instance_valid(world.driving) and bool(world.driving.get("occupied")) else world.player
	if not is_instance_valid(actor): actor = world.player
	center = Vector2(actor.global_position.x, actor.global_position.z)
	_cache_region()
	var velocity: Variant = actor.get("velocity")
	if velocity is Vector3 and Vector2(velocity.x, velocity.z).length() > 0.15:
		heading = Vector2(velocity.x, velocity.z).angle()
	elif actor != world.player:
		var forward := -actor.global_basis.z
		heading = Vector2(forward.x, forward.z).angle()
	objective_target = Vector2.ZERO
	var mission_world: Variant = world.session.get("mission_world")
	if mission_world != null and mission_world.has_method("target_position"):
		var target: Vector3 = mission_world.target_position()
		if target.is_finite() and not target.is_zero_approx(): objective_target = Vector2(target.x, target.z)
	if world.session.freight_active and world.session.freight_target.is_finite():
		var delivery: Vector3 = world.session.freight_target
		objective_target = Vector2(delivery.x, delivery.z)
	if not was_visible or _redraw_required or center.distance_squared_to(_drawn_center) > 0.0004 or absf(angle_difference(heading, _drawn_heading)) > 0.01 or not objective_target.is_equal_approx(_drawn_objective):
		_drawn_center = center
		_drawn_heading = heading
		_drawn_objective = objective_target
		_redraw_required = false
		canvas.queue_redraw()

func _cache_region() -> void:
	var region: Node = world.production.region
	if not is_instance_valid(region) or region.get_instance_id() == _cached_region_id: return
	_cached_region_id = region.get_instance_id()
	_redraw_required = true
	_roads.clear()
	_buildings.clear()
	_entries.clear()
	for source in region.roads:
		var points := PackedVector2Array()
		var bounds := Rect2()
		for point: Vector3 in source.points:
			var mapped := Vector2(point.x, point.z)
			points.append(mapped)
			bounds = Rect2(mapped, Vector2.ZERO) if points.size() == 1 else bounds.expand(mapped)
		_roads.append({"points": points, "width": float(source.get("width", 2.0)), "bounds": bounds})
	for source in region.buildings:
		var point: Vector3 = source.position
		var dimensions: Vector2 = source.size
		_buildings.append(Rect2(Vector2(point.x, point.z) - dimensions * 0.5, dimensions))
	for source in region.entries:
		var point: Vector3 = source.position
		_entries.append(Vector2(point.x, point.z))

func project(point: Vector2) -> Vector2:
	return MAP_SIZE * 0.5 + (point - center) * SCALE

func edge_marker(point: Vector2) -> Vector2:
	var offset := project(point) - MAP_SIZE * 0.5
	var factor := maxf(absf(offset.x) / (MAP_SIZE.x * 0.5 - 12), absf(offset.y) / (MAP_SIZE.y * 0.5 - 12))
	return MAP_SIZE * 0.5 + offset / maxf(1.0, factor)

func draw_map(target: Control) -> void:
	target.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("263940"))
	if not is_instance_valid(world) or not is_instance_valid(world.production) or not is_instance_valid(world.production.region): return
	var map_area := Rect2(center - MAP_SIZE / (2.0 * SCALE), MAP_SIZE / SCALE)
	for rect in _buildings:
		if map_area.intersects(rect): target.draw_rect(Rect2(project(rect.position), rect.size * SCALE), Color("46595c"))
	for road in _roads:
		if not map_area.intersects(road.bounds.grow(maxf(2.0 / SCALE, road.width))): continue
		var points := PackedVector2Array()
		for point: Vector2 in road.points: points.append(project(point))
		if points.size() > 1:
			target.draw_polyline(points, Color("a8b4b0"), maxf(2.0, road.width * SCALE * 0.45), true)
	for entry in _entries:
		var marker := project(entry)
		if Rect2(Vector2(8, 8), MAP_SIZE - Vector2(16, 16)).has_point(marker):
			target.draw_circle(marker, 5, Color("18262d"))
			target.draw_circle(marker, 3, Color("e8b77d"))
	if objective_target != Vector2.ZERO:
		var marker := edge_marker(objective_target)
		target.draw_circle(marker, 10, Color("101820"))
		target.draw_colored_polygon(PackedVector2Array([marker + Vector2(0,-7), marker + Vector2(7,0), marker + Vector2(0,7), marker + Vector2(-7,0)]), Color("ffcf4d"))
	var middle := MAP_SIZE * 0.5
	var pointer := PackedVector2Array()
	for point in [Vector2(8,0), Vector2(-5,-5), Vector2(-2,0), Vector2(-5,5)]: pointer.append(middle + point.rotated(heading))
	target.draw_colored_polygon(pointer, Color.WHITE)
	target.draw_rect(Rect2(Vector2(MAP_SIZE.x * 0.5 - 7, 1), Vector2(14, 16)), Color("101820"))
	target.draw_string(ThemeDB.fallback_font, Vector2(MAP_SIZE.x * 0.5 - 5, 13), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
