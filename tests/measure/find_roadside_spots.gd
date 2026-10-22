extends SceneTree
## Ferramenta (22/10): desliza cada lugar da beira de estrada do deserto ao longo da própria estrada
## e imprime o ponto mais próximo do atual que cumpre TODAS as regras de test_core_contracts
## (desert_roadside). Uso: --script res://tests/measure/find_roadside_spots.gd [-- --ids=a,b]
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const DESERT_LAYOUT := preload("res://world/desert/DesertLayout.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const LINES := preload("res://world/desert/DesertUtilityLines.gd")

var _poles: Array[Vector2] = []

func road_distance(point: Vector2) -> Dictionary:
	var best := {"distance": INF, "toward": Vector2.ZERO, "id": "", "tangent": Vector2.ZERO}
	for road in DESERT_LAYOUT.roads():
		var points: PackedVector3Array = road.points
		for i in range(1, points.size()):
			var p0 := Vector2(points[i - 1].x, points[i - 1].z)
			var p1 := Vector2(points[i].x, points[i].z)
			var closest := Geometry2D.get_closest_point_to_segment(point, p0, p1)
			if closest.distance_to(point) < best.distance:
				best = {"distance": closest.distance_to(point), "toward": (closest - point).normalized(), "id": str(road.id), "tangent": (p1 - p0).normalized()}
	return best

func problems(definition: Dictionary, center: Vector2) -> Array[String]:
	var result: Array[String] = []
	var road := road_distance(center)
	var radius := float(definition.get("radius", ROADSIDE.SITE_RADIUS))
	var depth := maxf(0.0, radius - ROADSIDE.SITE_RADIUS)
	if not (road.distance >= 14.0 and road.distance - depth <= 32.0): result.append("estrada %.1f" % road.distance)
	var front := Basis(Vector3.UP, float(definition.yaw)) * Vector3.BACK
	if Vector2(front.x, front.z).dot(road.toward) <= .9: result.append("frente")
	if not DESERT_LAYOUT.BOUNDS.grow(-40).has_point(center): result.append("limites")
	if not DESERT_LAYOUT.drag_reservation_clear(center, 8.0): result.append("arrancada")
	for site in WILDS.SITES:
		if (site.center as Vector2).distance_to(center) <= radius + WILDS.SITE_RADIUS + 20.0: result.append(str(site.id))
	for building in DESERT_LAYOUT.buildings():
		if Vector2(building.position.x, building.position.z).distance_to(center) <= 60.0: result.append(str(building.id))
	for pole in _poles:
		if pole.distance_to(center) <= 16.0:
			result.append("poste")
			break
	# Não pode encostar em outro lugar da beira de estrada.
	for other in ROADSIDE.SITES:
		if other.id == definition.id: continue
		if (other.center as Vector2).distance_to(center) < radius + float(other.get("radius", ROADSIDE.SITE_RADIUS)) + 10.0: result.append(str(other.id))
	return result

func _initialize() -> void:
	ROADSIDE._enabled = 1
	for record in LINES.records():
		if record.kind == "utility_pole": _poles.append(Vector2(record.position.x, record.position.z))
	var wanted: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): wanted = arg.trim_prefix("--ids=").split(",")
	for definition in ROADSIDE.SITES:
		if not wanted.is_empty() and str(definition.id) not in wanted: continue
		var center: Vector2 = definition.center
		var now := problems(definition, center)
		if now.is_empty():
			print("SPOT %s ok em %s" % [definition.id, center])
			continue
		var tangent: Vector2 = road_distance(center).tangent
		var found := false
		for step in range(1, 81):
			for sign in [1.0, -1.0]:
				var candidate: Vector2 = (center + tangent * sign * step * 2.0).round()
				if problems(definition, candidate).is_empty():
					print("SPOT %s %s -> %s (desliza %.0f m; antes: %s)" % [definition.id, center, candidate, candidate.distance_to(center), now])
					found = true
					break
			if found: break
		if not found: print("SPOT %s sem ponto em ±160 m (%s)" % [definition.id, now])
	quit(0)
