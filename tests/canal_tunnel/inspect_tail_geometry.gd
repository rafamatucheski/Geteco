extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var model := preload("res://runtime/FleetCatalog.gd").create("sport_coupe")
	root.add_child(model)
	var paint := PackedVector3Array()
	for part in model.find_children("*", "MeshInstance3D", true, false):
		if part.get_active_material(0).resource_name != "paint": continue
		var faces: PackedVector3Array = part.mesh.get_faces()
		for v in faces: paint.append(part.transform * v)
	for part in model.find_children("*", "MeshInstance3D", true, false):
		if str(part.get_meta("coupe_damage_material_key", "")) != "tail": continue
		var box: AABB = part.transform * part.mesh.get_aabb()
		var offsets: Array = []
		for sx in [.05, .25, .5, .75, .95]:
			for sy in [.1, .5, .9]:
				var point := Vector3(lerpf(box.position.x, box.end.x, sx), lerpf(box.position.y, box.end.y, sy), 20)
				var back := -INF
				for i in range(0, paint.size(), 3):
					var hit: Variant = Geometry3D.ray_intersects_triangle(point, Vector3.FORWARD, paint[i], paint[i + 1], paint[i + 2])
					if hit != null: back = maxf(back, hit.z)
				if is_finite(back): offsets.append(back - box.position.z)
		print("TAIL_GEOMETRY ", part.name, " box=", box, " hull_minus_lens=", offsets)
	quit()
