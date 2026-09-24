extends RefCounted

const BLINK_INTERVAL_MS := 320
const MARKER_OUTLINE := Color("101c29")
const POLICE_RED := Color("ef4355")
const POLICE_BLUE := Color("448fff")

static func marker_color(elapsed_msec: int) -> Color:
	var phase := floori(float(elapsed_msec) / float(BLINK_INTERVAL_MS))
	return POLICE_RED if phase % 2 == 0 else POLICE_BLUE

static func draw_contacts(map: CanvasLayer) -> void:
	var wanted := map.get_node_or_null("/root/WantedManager")
	if wanted == null or wanted.current_stars <= 0: return
	var area := Rect2(Vector2(8, 8), map.MAP_SIZE - Vector2(16, 16))
	var light_color := marker_color(Time.get_ticks_msec())
	for unit in map.get_tree().get_nodes_in_group("emergency_vehicle"):
		if not is_instance_valid(unit) or unit.type != 0 or not unit.visible or unit.is_broken or unit.is_returning_to_base: continue
		if unit.global_position.distance_to(map.center) > 2200: continue
		var raw: Vector2 = map.project(unit.global_position)
		var point: Vector2 = raw if area.has_point(raw) else map.edge_marker(unit.global_position)
		map.canvas.draw_circle(point, 6.0, MARKER_OUTLINE)
		map.canvas.draw_circle(point, 4.0, light_color)
