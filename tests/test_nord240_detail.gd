extends SceneTree
## Nord 240 pilot: less geometry, working doors/lights/paint/damage, isolated from
## the Touring variant. Rendered appearance and frame time are checked separately.
## Run: godot --headless --path . --script res://tests/test_nord240_detail.gd
const FLEET := preload("res://runtime/FleetCatalog.gd")
const FINISH := preload("res://runtime/VehicleFinish.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DOORS := preload("res://gameplay/VehicleDoorBuilder.gd")
const SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
var failures: Array[String] = []
var checks := 0
var stage: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _original(id: String) -> Node3D:
	# The unchanged baked source plus the pre-existing common finishing pass is
	# the reference. Neither of these two IDs has HeavyDetail or TwoTone passes.
	var model := (load(FLEET.spec(id).scene) as PackedScene).instantiate() as Node3D
	FINISH.decorate(id, model)
	stage.add_child(model)
	return model

func _metrics(model: Node3D) -> Dictionary:
	var result := {"triangles": 0, "visible_triangles": 0, "meshes": 0, "bounds": AABB()}
	var first := true
	var inverse := model.global_transform.affine_inverse()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		result.meshes += 1
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var count := int((indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3)
			result.triangles += count
			if part.is_visible_in_tree(): result.visible_triangles += count
		if not part.is_visible_in_tree(): continue
		var box: AABB = inverse * part.global_transform * part.get_aabb()
		result.bounds = box if first else (result.bounds as AABB).merge(box)
		first = false
	return result

func _wheel_signature(model: Node3D) -> Dictionary:
	var centers := {}
	# The driving factory discovers only direct children before making pivots.
	for part in model.get_children():
		if not part is MeshInstance3D or not part.has_meta("wheel_center"): continue
		if not bool(part.get_meta("wheel_spins", true)): continue
		var center: Vector3 = part.get_meta("wheel_center")
		var key := "%.5f,%.5f,%.5f" % [center.x, center.y, center.z]
		centers[key] = maxf(float(centers.get(key, 0.0)), float(part.get_meta("wheel_radius", 0.0)))
	return centers

func _material_signature(material: Material) -> Array:
	if not material is StandardMaterial3D: return [material.get_class() if material else "null"]
	var result: Array = [material.resource_name, material.albedo_color, material.metallic,
		material.roughness, material.clearcoat_enabled, material.clearcoat,
		material.normal_enabled, material.normal_scale, material.emission_enabled,
		material.emission, material.emission_energy_multiplier, material.cull_mode,
		material.uv1_triplanar, material.uv1_scale]
	for key in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
		var texture := material.get(key) as Texture2D
		result.append([texture.resource_path, texture.get_width(), texture.get_height()] if texture else [])
	return result

func _fingerprint(model: Node3D) -> int:
	var parts: Array = []
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var surfaces: Array = []
		for surface in part.mesh.get_surface_count():
			surfaces.append([hash(var_to_bytes(part.mesh.surface_get_arrays(surface))),
				ROLES.key(part, surface), _material_signature(part.get_active_material(surface))])
		parts.append([part.transform, part.visible, part.cast_shadow, surfaces])
	return hash(var_to_bytes(parts))

func _spawn(color: Color) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = "nordic_estate"
	car.paint_color = color
	stage.add_child(car)
	car.set_physics_process(false)
	return car

func _material_snapshots(model: Node3D) -> Array:
	var found := {}
	var result: Array = []
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or found.has(material): continue
			found[material] = true
			result.append({"material": material, "role": ROLES.key(part, surface),
				"color": material.albedo_color, "normal": material.normal_texture,
				"normal_enabled": material.normal_enabled, "roughness_map": material.roughness_texture,
				"roughness": material.roughness, "uv1_triplanar": material.uv1_triplanar,
				"uv1_scale": material.uv1_scale})
	return result

func _check_authored_maps(snapshots: Array, label: String, repaired: bool) -> void:
	for item in snapshots:
		var material: StandardMaterial3D = item.material
		if item.normal != null:
			check(material.normal_texture == item.normal and material.normal_enabled == item.normal_enabled,
				label + ": authored normal survives on " + str(item.role))
		if item.roughness_map != null:
			check(material.roughness_texture == item.roughness_map,
				label + ": roughness map survives on " + str(item.role))
		if repaired:
			check(is_equal_approx(material.roughness, float(item.roughness)),
				label + ": roughness restored on " + str(item.role))
			check(material.uv1_triplanar == item.uv1_triplanar and material.uv1_scale.is_equal_approx(item.uv1_scale),
				label + ": authored UV mapping restored on " + str(item.role))

func _body_at_door(model: Node3D, spec: Dictionary, side: int) -> bool:
	var origin := Vector3(side * (float(spec.x) + .04), (float(spec.sill) + float(spec.belt)) * .5,
		(float(spec.zf) + float(spec.zr)) * .5)
	var direction := Vector3(-side, 0, 0)
	var inverse := model.global_transform.affine_inverse()
	# Door leaves are nested below their hinge and excluded: this checks that
	# the original static body actually loses the opening instead of duplicating it.
	for part in model.get_children():
		if not part is MeshInstance3D or part.mesh == null or not part.visible: continue
		var xf: Transform3D = inverse * part.global_transform
		for surface in part.mesh.get_surface_count():
			if ROLES.key(part, surface) != "paint": continue
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var indexed: bool = indices != null and indices.size() > 0
			var count: int = indices.size() if indexed else vertices.size()
			for index in range(0, count, 3):
				var a: Vector3 = xf * vertices[indices[index] if indexed else index]
				var b: Vector3 = xf * vertices[indices[index + 1] if indexed else index + 1]
				var c: Vector3 = xf * vertices[indices[index + 2] if indexed else index + 2]
				var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
				if hit != null and origin.distance_to(hit) < .08: return true
	return false

func _check_doors(car: CharacterBody3D) -> void:
	var spec: Dictionary = SPECS.row("nordic_estate")
	var measured := DOORS.measure(car.visual, spec)
	check(absf(measured - float(spec.x)) <= .03, "door table still matches actual side skin within 3 cm")
	for side in [-1, 1]: check(_body_at_door(car.visual, spec, side), "body present before cutting side " + str(side))
	car.finish_doors()
	check(is_instance_valid(car.door_presentation) and car.door_presentation.ready_for_boarding,
		"real driving door presentation finishes")
	if not is_instance_valid(car.door_presentation): return
	for side in [-1, 1]:
		var hinge: Node3D = car.door_presentation.hinges.get(side)
		check(hinge != null, "door hinge exists on side " + str(side))
		if hinge == null: continue
		var skin := hinge.get_node_or_null("Skin") as MeshInstance3D
		check(skin != null and skin.mesh.get_surface_count() > 0, "real body/glass forms the door leaf")
		if skin == null: continue
		var paint_found := false
		var meaningful_uv := false
		for surface in skin.mesh.get_surface_count():
			if ROLES.key(skin, surface) != "paint": continue
			paint_found = true
			check(skin.get_active_material(surface) in car._paint.materials,
				"door paint shares the repaintable body material")
			var arrays := skin.mesh.surface_get_arrays(surface)
			var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
			if uv != null and uv.size() > 1:
				for coordinate: Vector2 in uv:
					if not coordinate.is_equal_approx(uv[0]): meaningful_uv = true; break
		check(paint_found and meaningful_uv, "door leaf retains paint and nonconstant UV1")
		check(not _body_at_door(car.visual, spec, side), "static body no longer covers door opening")
		car.door_presentation.set_open(side, true, 0.0)
		check(absf(hinge.rotation.y) > .5, "door physically rotates open")
		car.door_presentation.set_open(side, false, 0.0)
		check(is_zero_approx(hinge.rotation.y), "door returns to closed position")

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var original := _original("nordic_estate")
	var reference := _metrics(original)
	var original_fingerprint := _fingerprint(original)
	var original_wheels := _wheel_signature(original)
	var touring_reference := _original("station_wagon")
	var touring_fingerprint := _fingerprint(touring_reference)
	# Shared fleet passes may evolve independently of this Nord pilot. Compare the
	# production Touring factory before/after Nord use, and keep the raw source
	# fingerprint separately to detect shared-resource mutation.
	var touring_factory_reference := FLEET.create("station_wagon")
	stage.add_child(touring_factory_reference)
	var touring_factory_fingerprint := _fingerprint(touring_factory_reference)
	var revised := FLEET.create("nordic_estate")
	stage.add_child(revised)
	var actual := _metrics(revised)
	var revised_fingerprint := _fingerprint(revised)
	var cached := FLEET.create("nordic_estate")
	stage.add_child(cached)
	check(_fingerprint(cached) == revised_fingerprint,
		"cached spawn matches the first prepared Nord geometry and materials")
	check(_wheel_signature(cached) == original_wheels,
		"cached spawn preserves wheel anchors and rolling radii")
	check(actual.triangles < reference.triangles, "Nord has fewer total triangles, including hidden pieces")
	check(actual.visible_triangles < reference.visible_triangles, "Nord has fewer visible triangles")
	check(actual.meshes <= reference.meshes, "added detail does not increase mesh node count")
	check((actual.bounds as AABB).position.distance_to((reference.bounds as AABB).position) <= .08
		and (actual.bounds as AABB).end.distance_to((reference.bounds as AABB).end) <= .08,
		"visual bounds still fit the unchanged driving hull")
	check(original_wheels.size() == 4 and _wheel_signature(revised) == original_wheels,
		"four wheel anchors and rolling radii survive geometry consolidation")
	var first := _spawn(Color("a83f36"))
	var second := _spawn(Color("365b83"))
	var second_fingerprint := _fingerprint(second.visual)
	check(first.wheels.size() == 4 and second.wheels.size() == 4, "Vehicle builds four live wheel pivots")
	check(not first._paint.materials.is_empty() and not second._paint.materials.is_empty(), "paint is still customizable")
	var snapshots := _material_snapshots(first.visual)
	var has_roughness_map := false
	for item in snapshots:
		if item.role == "paint" and item.roughness_map != null: has_roughness_map = true
	check(has_roughness_map, "Nord body has authored roughness detail")
	first.paint_color = Color("d2b273")
	for material: StandardMaterial3D in first._paint.materials:
		check(material.albedo_color.is_equal_approx(first.paint_color), "repainting reaches every body material")
	for material: StandardMaterial3D in second._paint.materials:
		check(material.albedo_color.is_equal_approx(Color("365b83")), "repainting one Nord does not repaint another")
	for item in snapshots:
		if item.role != "paint": check(item.material.albedo_color.is_equal_approx(item.color), "repainting preserves " + str(item.role))
	first.ensure_equipment(stage)
	var equipment: Node = first.equipment
	check(equipment.lamps.size() == 2 and not equipment.tail_materials.is_empty(), "front pair and brake lenses bind")
	var sides := {}
	for item in equipment.lamps: sides[int(item.side)] = true
	check(sides.has(-1) and sides.has(1), "front lights retain separate left and right mounts")
	first.controlled = true
	first.brake_input = true
	equipment._refresh()
	for material in equipment.tail_materials: check(material.emission_enabled, "braking lights the rear lenses")
	first.brake_input = false
	equipment._refresh()
	for material in equipment.tail_materials: check(not material.emission_enabled, "releasing brake extinguishes daytime brake lamps")
	# Snapshot after equipment has made its own per-car lens copies.
	snapshots = _material_snapshots(first.visual)
	first.receive_damage(first.max_health * .55)
	check(not first.damage_look.burning and first.health > 0, "partial damage test remains below fire threshold")
	_check_authored_maps(snapshots, "damage", false)
	first.repair()
	_check_authored_maps(snapshots, "repair", true)
	for material: StandardMaterial3D in first._paint.materials:
		check(material.albedo_color.is_equal_approx(first.paint_color) and not material.detail_enabled,
			"repair keeps chosen paint and removes damage scratches")
	_check_doors(first)
	first.paint_color = Color("477658")
	for material: StandardMaterial3D in first._paint.materials:
		check(material.albedo_color.is_equal_approx(first.paint_color), "repainting still works after door cut")
	check(_fingerprint(second.visual) == second_fingerprint,
		"paint, lights, damage, repair and door cuts do not mutate the second Nord")
	var late_cached := FLEET.create("nordic_estate")
	stage.add_child(late_cached)
	check(_fingerprint(late_cached) == revised_fingerprint,
		"later cached spawn stays pristine after per-car paint, damage and doors")
	check(_fingerprint(revised) == revised_fingerprint,
		"per-car changes do not mutate the first shared Nord resource template")
	var touring := FLEET.create("station_wagon")
	stage.add_child(touring)
	check(_fingerprint(touring) == touring_factory_fingerprint,
		"Nord usage leaves station_wagon production geometry/materials unchanged")
	check(_fingerprint(original) == original_fingerprint, "cached Nord generation does not mutate the baked source")
	check(_fingerprint(touring_reference) == touring_fingerprint, "shared Touring source stays unchanged")
	print("NORD240_GEOMETRY before_triangles=", reference.triangles, " after_triangles=", actual.triangles,
		" before_meshes=", reference.meshes, " after_meshes=", actual.meshes)
	stage.free()
	print("NORD240_DETAIL checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
