@tool
class_name CityIntersection
extends Node2D

enum JunctionType {
	CROSS_4_WAY,
	T_JUNCTION_NORTH,
	T_JUNCTION_SOUTH,
	T_JUNCTION_EAST,
	T_JUNCTION_WEST,
	ROUNDABOUT
}

@export var junction_type: int = JunctionType.CROSS_4_WAY:
	set(jt):
		junction_type = jt
		_apply_type_defaults()
		_update_intersection()

@export var road_width: float = 96.0:
	set(rw):
		road_width = maxf(rw, 32.0)
		_update_intersection()

@export var sidewalk_width: float = 28.0:
	set(sw):
		sidewalk_width = maxf(sw, 8.0)
		_update_intersection()

# --- CROSSWALKS & STOP LINES ---
@export_group("Crosswalks")
@export var crosswalk_north: bool = true:
	set(val):
		crosswalk_north = val
		queue_redraw()

@export var crosswalk_south: bool = true:
	set(val):
		crosswalk_south = val
		queue_redraw()

@export var crosswalk_east: bool = true:
	set(val):
		crosswalk_east = val
		queue_redraw()

@export var crosswalk_west: bool = true:
	set(val):
		crosswalk_west = val
		queue_redraw()

@export var has_stop_lines: bool = true:
	set(val):
		has_stop_lines = val
		queue_redraw()

@export var has_yellow_box: bool = false:
	set(val):
		has_yellow_box = val
		queue_redraw()

# --- TRAFFIC CONTROLS & CURBS ---
@export_group("Traffic Controls")
@export var has_traffic_lights: bool = true:
	set(val):
		has_traffic_lights = val
		_update_controls()

@export var has_curb_islands: bool = true:
	set(val):
		has_curb_islands = val
		queue_redraw()

# --- COLORS ---
@export_group("Colors")
@export var asphalt_color: Color = Color("2d3139"):
	set(c):
		asphalt_color = c
		queue_redraw()

@export var sidewalk_color: Color = Color("94a3b8"):
	set(c):
		sidewalk_color = c
		queue_redraw()

@export var curb_color: Color = Color("cbd5e1"):
	set(c):
		curb_color = c
		queue_redraw()

@export var marking_yellow: Color = Color("dbc85c"):
	set(c):
		marking_yellow = c
		queue_redraw()

@export var marking_white: Color = Color("f1f5f9"):
	set(c):
		marking_white = c
		queue_redraw()

var controls_container: Node2D
var _traffic_registration_id: StringName

func _ready() -> void:
	_update_intersection()
	add_to_group("city_intersection")

func _exit_tree() -> void:
	_unregister_traffic_controls()

func _apply_type_defaults() -> void:
	match junction_type:
		JunctionType.CROSS_4_WAY:
			crosswalk_north = true
			crosswalk_south = true
			crosswalk_east = true
			crosswalk_west = true
		JunctionType.T_JUNCTION_NORTH:
			crosswalk_north = false
			crosswalk_south = true
			crosswalk_east = true
			crosswalk_west = true
		JunctionType.T_JUNCTION_SOUTH:
			crosswalk_north = true
			crosswalk_south = false
			crosswalk_east = true
			crosswalk_west = true
		JunctionType.T_JUNCTION_EAST:
			crosswalk_north = true
			crosswalk_south = true
			crosswalk_east = false
			crosswalk_west = true
		JunctionType.T_JUNCTION_WEST:
			crosswalk_north = true
			crosswalk_south = true
			crosswalk_east = true
			crosswalk_west = false
		JunctionType.ROUNDABOUT:
			crosswalk_north = true
			crosswalk_south = true
			crosswalk_east = true
			crosswalk_west = true
			has_yellow_box = false

func _update_intersection() -> void:
	_update_controls()
	queue_redraw()

func _update_controls() -> void:
	# Compatibilidade de cena: o container antigo continua existindo, mas nunca
	# instancia managers. O autoload unico e responsavel pelos quatro postes.
	if controls_container == null and is_inside_tree():
		controls_container = get_node_or_null("ControlsContainer") as Node2D
		if controls_container == null:
			controls_container = Node2D.new()
			controls_container.name = "ControlsContainer"
			add_child(controls_container)
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	var manager := get_node_or_null("/root/TrafficLightManager")
	if manager == null:
		return
	if _traffic_registration_id == StringName():
		_traffic_registration_id = StringName("city_intersection:%s" % String(get_path()))
	if has_traffic_lights:
		manager.register_intersection(_traffic_registration_id, global_position, road_width)
	else:
		manager.unregister_intersection(_traffic_registration_id)

func _unregister_traffic_controls() -> void:
	if _traffic_registration_id == StringName() or not is_inside_tree():
		return
	var manager := get_node_or_null("/root/TrafficLightManager")
	if manager != null and manager.has_method("unregister_intersection"):
		manager.unregister_intersection(_traffic_registration_id)

func _draw() -> void:
	var half_w := road_width * 0.5
	var total_box := road_width + sidewalk_width * 2.0
	var half_tot := total_box * 0.5

	# 1. Corner Sidewalk Islands
	if has_curb_islands:
		var corners := [
			Rect2(-half_tot, -half_tot, sidewalk_width, sidewalk_width),
			Rect2(half_w, -half_tot, sidewalk_width, sidewalk_width),
			Rect2(-half_tot, half_w, sidewalk_width, sidewalk_width),
			Rect2(half_w, half_w, sidewalk_width, sidewalk_width)
		]
		for c in corners:
			draw_rect(c, sidewalk_color)
			draw_rect(c, curb_color, false, 1.5)

	# 2. Main Junction Asphalt
	var junction_rect := Rect2(-half_w, -half_w, road_width, road_width)
	draw_rect(junction_rect, asphalt_color)

	# 3. Roundabout Center Island or Yellow Box Marking
	if junction_type == JunctionType.ROUNDABOUT:
		var island_r := road_width * 0.28
		draw_circle(Vector2.ZERO, island_r + 2.0, curb_color)
		draw_circle(Vector2.ZERO, island_r, Color("4d7c0f"))
		draw_circle(Vector2.ZERO, island_r * 0.6, Color("65a30d"))
		draw_circle(Vector2.ZERO, 5.0, Color("cbd5e1"))
	elif has_yellow_box:
		draw_rect(junction_rect.grow(-4.0), Color(0.86, 0.78, 0.36, 0.15))
		_draw_box_junction_grid(junction_rect.grow(-4.0))

	# 4. Zebra Crosswalks
	var arm_offset := half_w + 12.0
	if crosswalk_north:
		_draw_zebra(Vector2(-half_w * 0.8, -arm_offset), Vector2(half_w * 0.8, -arm_offset), true)
		if has_stop_lines:
			draw_line(Vector2(0, -arm_offset - 16), Vector2(half_w * 0.85, -arm_offset - 16), marking_white, 3.5)

	if crosswalk_south:
		_draw_zebra(Vector2(-half_w * 0.8, arm_offset), Vector2(half_w * 0.8, arm_offset), true)
		if has_stop_lines:
			draw_line(Vector2(-half_w * 0.85, arm_offset + 16), Vector2(0, arm_offset + 16), marking_white, 3.5)

	if crosswalk_west:
		_draw_zebra(Vector2(-arm_offset, -half_w * 0.8), Vector2(-arm_offset, half_w * 0.8), false)
		if has_stop_lines:
			draw_line(Vector2(-arm_offset - 16, -half_w * 0.85), Vector2(-arm_offset - 16, 0), marking_white, 3.5)

	if crosswalk_east:
		_draw_zebra(Vector2(arm_offset, -half_w * 0.8), Vector2(arm_offset, half_w * 0.8), false)
		if has_stop_lines:
			draw_line(Vector2(arm_offset + 16, 0), Vector2(arm_offset + 16, half_w * 0.85), marking_white, 3.5)

func _draw_zebra(start_pos: Vector2, end_pos: Vector2, is_horizontal: bool) -> void:
	var count := 8
	for i in range(count):
		var t := float(i) / float(count - 1)
		var center := start_pos.lerp(end_pos, t)
		if is_horizontal:
			draw_rect(Rect2(center.x - 4, center.y - 10, 8, 20), marking_white)
		else:
			draw_rect(Rect2(center.x - 10, center.y - 4, 20, 8), marking_white)

func _draw_box_junction_grid(rect: Rect2) -> void:
	draw_rect(rect, marking_yellow, false, 2.0)
	var step := 18.0
	var cursor := rect.position.x
	while cursor < rect.end.x + rect.size.y:
		var p1 := Vector2(cursor, rect.position.y)
		var p2 := Vector2(cursor - rect.size.y, rect.end.y)
		# Clip inside rect
		_draw_clipped_line(p1, p2, rect, marking_yellow)
		cursor += step

func _draw_clipped_line(from: Vector2, to: Vector2, bounds: Rect2, col: Color) -> void:
	draw_line(
		Vector2(clampf(from.x, bounds.position.x, bounds.end.x), clampf(from.y, bounds.position.y, bounds.end.y)),
		Vector2(clampf(to.x, bounds.position.x, bounds.end.x), clampf(to.y, bounds.position.y, bounds.end.y)),
		col, 1.5
	)
