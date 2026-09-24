extends SceneTree
## Auditoria: para cada lanterna traseira, a distância até a carroceria logo à frente
## dela (-Z) e se há carroceria sob o centro. Folga > 4 cm = lanterna "voando".
const GEOMETRY := preload("res://tools/fleet_fixups/FleetGeometry.gd")
func _initialize() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty(): ids = preload("res://runtime/FleetCatalog.gd").all().keys()
	for id in ids:
		var model: Node3D = (load("res://assets/fleet/%s.scn" % id) as PackedScene).instantiate()
		var geo = GEOMETRY.new(model)
		var body_only := func(part): return not GEOMETRY.is_lamp(part) and not part.has_meta("wheel_center")
		for part in geo.parts():
			if not GEOMETRY.is_tail_lamp(part): continue
			var box: AABB = geo.bounds(part)
			if box.get_center().z < 0: continue
			var center := box.get_center()
			# Raio vindo de trás acha a face externa da carroceria nesse (x, y).
			var hit: Dictionary = geo.ray(Vector3(center.x, center.y, 30.0), Vector3.FORWARD, [part], body_only)
			var gap: float = box.position.z - hit.point.z if not hit.is_empty() else INF
			if gap > .04: print("FLOAT %s lamp c=%s size=%s gap=%.2f" % [id, center, box.size, gap])
		model.free()
	quit()
