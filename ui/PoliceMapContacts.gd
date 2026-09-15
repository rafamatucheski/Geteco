extends RefCounted

static func draw_contacts(map: CanvasLayer) -> void:
	var wanted := map.get_node_or_null("/root/WantedManager")
	if wanted == null or wanted.current_stars <= 0: return
	var searching: bool = wanted.has_method("is_searching") and wanted.is_searching()
	var area := Rect2(Vector2(8, 8), map.MAP_SIZE - Vector2(16, 16))
	for unit in map.get_tree().get_nodes_in_group("emergency_vehicle"):
		if not is_instance_valid(unit) or unit.type != 0 or not unit.visible or unit.is_broken or unit.is_returning_to_base: continue
		if unit.global_position.distance_to(map.center) > 2200: continue
		var raw: Vector2 = map.project(unit.global_position)
		var point: Vector2 = raw if area.has_point(raw) else map.edge_marker(unit.global_position)
		var motorcycle: bool = unit.get("police_variant") == "motorcycle"
		var body := PackedVector2Array()
		for vertex in [Vector2(6, 0), Vector2(2, -3 if motorcycle else -4), Vector2(-5, -3 if motorcycle else -4), Vector2(-5, 3 if motorcycle else 4), Vector2(2, 3 if motorcycle else 4)]:
			body.append(point + vertex.rotated(unit.global_rotation))
		map.canvas.draw_circle(point, 7, Color("101c29"))
		map.canvas.draw_colored_polygon(body, Color("e9b95c") if searching else Color("c6e6ff"))
		var side := Vector2(0, 2).rotated(unit.global_rotation)
		map.canvas.draw_circle(point + side, 1.7, Color("ef4355"))
		map.canvas.draw_circle(point - side, 1.7, Color("448fff"))
	for officer in map.get_tree().get_nodes_in_group("police_officer"):
		if not is_instance_valid(officer) or officer.is_dead or not officer.is_visible_in_tree(): continue
		var point: Vector2 = map.project(officer.global_position)
		if area.has_point(point):
			map.canvas.draw_circle(point, 3.5, Color("101c29"))
			map.canvas.draw_circle(point, 2.0, Color("e9b95c") if searching else Color("729eff"))
