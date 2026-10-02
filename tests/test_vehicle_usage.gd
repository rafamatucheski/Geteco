extends SceneTree
const USAGE := preload("res://runtime/VehicleUsage.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var counts := [0, 0, 0]
	var loads := [0, 0, 0, 0]
	for i in 200:
		var choice := USAGE.profile("ranch_pickup", "street_%d" % i)
		counts[choice.x] += 1
		loads[choice.y] += 1
	for count in counts: check(count > 20, "mixed condition in population")
	for count in loads: check(count > 20, "empty and varied bed loads")
	for id in ["police_cruiser", "medic_box", "cobra_boss_ironback", "bike_urban"]:
		check(USAGE.profile(id, "street_1") == Vector2i.ZERO, "special vehicle excluded: " + id)
	for id in USAGE.BEDS:
		for kind in 4:
			var identity := ""
			for i in 200:
				var candidate := "street_%d" % i
				if USAGE.profile(id, candidate) == Vector2i(2, kind): identity = candidate; break
			check(not identity.is_empty(), "fixture identity found")
			var car := VEHICLE.new()
			car.archetype = id
			car.vehicle_id = identity
			car.paint_color = Color("527566")
			world.add_child(car)
			car.set_physics_process(false)
			check(car.health == car.max_health, "cosmetic wear preserves health")
			check(car.visual.get_meta("usage_profile") == Vector2i(2, kind), "ready applies identity")
			var load_node := car.visual.get_node_or_null("BedLoad") as MeshInstance3D
			check((load_node != null) == (kind > 0), "load selection")
			if kind == 0:
				var bed: Array = USAGE.BEDS[id]
				var top := -INF
				var ray := Vector3(0, 3, float(bed[1]))
				for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
					var transform: Transform3D = car.visual.global_transform.affine_inverse() * part.global_transform
					var faces := part.mesh.get_faces()
					for face in range(0, faces.size(), 3):
						var hit: Variant = Geometry3D.ray_intersects_triangle(ray, Vector3.DOWN, transform * faces[face], transform * faces[face + 1], transform * faces[face + 2])
						if hit != null: top = maxf(top, hit.y)
				check(absf(top - float(bed[0])) < .04, id + ": actual bed floor exposed and load seated (surface=%s floor=%s)" % [top, bed[0]])
			if load_node != null:
				var box: AABB = load_node.transform * load_node.get_aabb()
				var bed: Array = USAGE.BEDS[id]
				check(box.position.y >= float(bed[0]) - .01, "load above bed floor")
				check(box.size.x < float(bed[2]) and box.size.z < float(bed[3]), "load fits inside bed")
				check(load_node.mesh.get_surface_count() == 1, "one cargo draw surface")
			var saved: Dictionary = preload("res://runtime/FleetState.gd").capture(car, "harbor")
			var restored := VEHICLE.new()
			stored_setup(restored, id, world)
			# Production restoration replaces the identity after spawning.
			restored.vehicle_id = saved.vehicle_id
			restored.paint_color = Color.html(saved.paint)
			check(restored.visual.get_meta("usage_profile") == car.visual.get_meta("usage_profile"), "save restoration preserves condition and load")
			for material in restored._paint.materials:
				check(material.detail_enabled and material.detail_albedo != null, "wear material installed")
				check(material.albedo_color.is_equal_approx(restored.paint_color), "paint remains repaintable")
			car.free()
			restored.free()
	world.free()
	print("VEHICLE_USAGE ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)

func stored_setup(car: CharacterBody3D, id: String, world: Node3D) -> void:
	car.archetype = id
	world.add_child(car)
	car.set_physics_process(false)
