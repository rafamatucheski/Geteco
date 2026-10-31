extends SceneTree
## Regressão do vinil de corrida pela pintura real da frota e pelos caminhos animados das portas.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const RACE_IDS := ["desert_faisca_rally", "desert_coyote_drag", "desert_mirage_gt"]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures.append(label)
	push_error(label)


func _spawn(id: String, identity: String, at: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = identity
	car.position = at
	root.add_child(car)
	car.set_physics_process(false)
	return car


func _run() -> void:
	for id in RACE_IDS:
		_check(not CATALOG.spec(id).is_empty(), id + ": authored race car is registered")
		if CATALOG.spec(id).is_empty():
			continue
		var car := _spawn(id, "livery_owner_" + id, Vector3.ZERO)
		var sibling := _spawn(id, "livery_traffic_" + id, Vector3(8, 0, 0))
		var vinyl := car.visual.get_node_or_null("DesertRaceLivery") as MeshInstance3D
		var sibling_vinyl := sibling.visual.get_node_or_null("DesertRaceLivery") as MeshInstance3D
		_check(vinyl != null and sibling_vinyl != null, id + ": player and traffic get race vinyl")
		if vinyl == null or sibling_vinyl == null:
			car.free()
			sibling.free()
			continue
		var shared_mesh: Mesh = vinyl.mesh
		var shared_material := vinyl.get_active_material(0) as StandardMaterial3D
		var original_colors: PackedColorArray = vinyl.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var original_tint: Color = shared_material.albedo_color
		var sibling_paint: Color = sibling.paint_color
		_check(
			(
				shared_mesh == sibling_vinyl.mesh
				and shared_material == sibling_vinyl.get_active_material(0)
			),
			id + ": identities share immutable vinyl resources"
		)
		_check(not car._paint.materials.is_empty(), id + ": body has repaintable material")
		car.paint_color = Color("bc326e")
		for paint: StandardMaterial3D in car._paint.materials:
			_check(
				paint.albedo_color.is_equal_approx(car.paint_color),
				id + ": real body repaint succeeds"
			)
		_check(
			(
				vinyl.get_active_material(0) == shared_material
				and shared_material.albedo_color.is_equal_approx(original_tint)
			),
			id + ": repaint preserves vinyl material and tint"
		)
		_check(
			vinyl.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == original_colors,
			id + ": repaint preserves authored vinyl colours"
		)
		_check(
			sibling.paint_color.is_equal_approx(sibling_paint),
			id + ": repaint does not recolour another identity"
		)
		for paint: StandardMaterial3D in sibling._paint.materials:
			_check(
				paint.albedo_color.is_equal_approx(sibling_paint),
				id + ": another identity keeps its rendered body colour"
			)
		var area_before := _vinyl_area(vinyl)
		car.finish_doors()
		_check(
			car.door_presentation != null and car.door_presentation.ready_for_boarding,
			id + ": real door cutting completes"
		)
		var leaf_area := 0.0
		for side in [-1, 1]:
			var hinge := car.door_presentation.hinges.get(side) as Node3D
			_check(hinge != null, id + ": hinge exists for side " + str(side))
			if hinge == null:
				continue
			var probe: Dictionary = {}
			var side_area := 0.0
			for node: MeshInstance3D in hinge.find_children("*", "MeshInstance3D", true, false):
				side_area += _vinyl_area(node)
				for surface in node.mesh.get_surface_count():
					if ROLES.key(node, surface) != "race_livery":
						continue
					_check(
						node.get_active_material(surface) == shared_material,
						id + ": door retains original vinyl palette"
					)
					var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[
						Mesh.ARRAY_VERTEX
					]
					for vertex in vertices:
						if probe.is_empty() or vertex.z > float(probe.get("distance", -INF)):
							probe = {"part": node, "vertex": vertex, "distance": vertex.z}
			_check(side_area > .025, id + ": visible vinyl moves onto door side " + str(side))
			leaf_area += side_area
			if probe.is_empty():
				continue
			var point: Vector3 = probe.part.to_global(probe.vertex)
			car.animate_driver_door(side, true, 0.0)
			_check(
				point.distance_to(probe.part.to_global(probe.vertex)) > .15,
				id + ": vinyl physically follows opened door side " + str(side)
			)
			car.animate_driver_door(side, false, 0.0)
			_check(
				point.distance_to(probe.part.to_global(probe.vertex)) < .001,
				id + ": vinyl returns exactly when door closes"
			)
		_check(
			absf(area_before - (_vinyl_area(vinyl) + leaf_area)) < .003,
			id + ": cutting neither duplicates nor loses vinyl area"
		)
		_check(
			sibling_vinyl.mesh == shared_mesh and _vinyl_area(sibling_vinyl) > area_before - .001,
			id + ": opening one car leaves the shared traffic skin intact"
		)
		car.paint_color = Color("3349af")
		_check(
			shared_material.albedo_color.is_equal_approx(original_tint),
			id + ": repaint after boarding preserves door vinyl"
		)
		car.free()
		sibling.free()
	await process_frame
	print(
		"DESERT_CAR_LIVERY_",
		"PASS" if failures.is_empty() else "FAIL",
		" checks=",
		checks,
		" failures=",
		failures.size()
	)
	quit(0 if failures.is_empty() else 1)


func _vinyl_area(part: MeshInstance3D) -> float:
	var total := 0.0
	for surface in part.mesh.get_surface_count():
		if ROLES.key(part, surface) != "race_livery":
			continue
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = (
			arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		)
		var count := vertices.size() if indices.is_empty() else indices.size()
		for triangle in range(0, count, 3):
			var a: Vector3 = vertices[triangle if indices.is_empty() else indices[triangle]]
			var b: Vector3 = vertices[triangle + 1 if indices.is_empty() else indices[triangle + 1]]
			var c: Vector3 = vertices[triangle + 2 if indices.is_empty() else indices[triangle + 2]]
			total += (b - a).cross(c - a).length() * .5
	return total
