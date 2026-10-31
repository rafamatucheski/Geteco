extends SceneTree
## Same fixture for original/candidate canonical SkateModel. Printed geometry
## signatures also permit exact comparison across the two separate runs.
const MODEL := preload("res://activities/skate/SkateModel.gd")
const PALETTE := [Color("d36c3e"), Color("487d9b"), Color("c3a842"), Color("79559b"), Color("44866a")]
const MATERIAL_FIELDS := ["vertex_color_use_as_albedo", "vertex_color_is_srgb", "albedo_color", "metallic",
	"roughness", "cull_mode", "transparency", "shading_mode", "depth_draw_mode", "texture_filter",
	"no_depth_test", "disable_receive_shadows"]
var fixture_world: Node3D
var checks := 0
var failures: Array[String] = []
var last_creation_usec := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func create_model(tint: Color) -> Node3D:
	var began := Time.get_ticks_usec()
	var model := MODEL.new()
	model.color = tint
	fixture_world.add_child(model)
	last_creation_usec = Time.get_ticks_usec()-began
	return model

func material_state(material: Material) -> Dictionary:
	var state := {"class":material.get_class()}
	for field in MATERIAL_FIELDS: state[field] = material.get(field)
	var texture: Texture2D = material.get("albedo_texture")
	if texture != null:
		var image := texture.get_image()
		state["texture_size"] = image.get_size()
		state["texture_data"] = image.get_data()
	else:
		state["texture_size"] = Vector2i.ZERO
		state["texture_data"] = PackedByteArray()
	return state

func describe_part(root_model: Node3D, part: Node3D, result: Array[Dictionary]) -> void:
	var entry := {"path":str(root_model.get_path_to(part)), "class":part.get_class(), "transform":part.transform}
	if part is MeshInstance3D:
		entry["aabb"] = part.mesh.get_aabb()
		entry["material"] = material_state(part.material_override)
		entry["shadow"] = part.cast_shadow
		entry["layers"] = part.layers
		var surfaces: Array[Dictionary] = []
		for index in part.mesh.get_surface_count():
			surfaces.append({"primitive":part.mesh.surface_get_primitive_type(index), "arrays":part.mesh.surface_get_arrays(index)})
		entry["surfaces"] = surfaces
	result.append(entry)
	for child: Node3D in part.get_children(): describe_part(root_model, child, result)

func describe(model: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Node3D in model.get_children(): describe_part(model, child, result)
	return result

func compare(actual: Array[Dictionary], expected: Array[Dictionary], label: String) -> void:
	check(actual.size() == expected.size(), label + " presentation node count")
	for index in mini(actual.size(), expected.size()):
		var a: Dictionary = actual[index]
		var b: Dictionary = expected[index]
		check(a.path == b.path and a["class"] == b["class"], label + " topology " + str(index))
		check(a.transform == b.transform, label + " local transform " + str(index))
		if b.has("surfaces"):
			check(a.get("surfaces", []) == b.surfaces, label + " exact vertices/indices/normals/UV/colors " + str(index))
			check(a.get("material", {}) == b.material, label + " material/texture state " + str(index))
			check(a.get("aabb") == b.aabb and a.get("shadow") == b.shadow and a.get("layers") == b.layers, label + " bounds/shadows/layers " + str(index))

func check_shape(model: Node3D, tint: Color) -> void:
	check(model.get_child_count() == 7 and model.wheels.size() == 4, "four independent wheel pivots and three body surfaces")
	var expected_pivots := [Vector3(-.099, .027, -.205), Vector3(.099, .027, -.205), Vector3(-.099, .027, .205), Vector3(.099, .027, .205)]
	for index in 4:
		var wheel: Node3D = model.wheels[index]
		check(wheel.get_parent() == model and wheel.position.is_equal_approx(expected_pivots[index]), "wheel pivot geometry " + str(index))
		check(wheel.get_child_count() == 1 and wheel.get_child(0).name == "UrethaneAndBearing", "wheel presentation hierarchy " + str(index))
	var art := model.get_node("DeckTrucksAndHubs") as MeshInstance3D
	var arrays := art.mesh.surface_get_arrays(0)
	check(tint in (arrays[Mesh.ARRAY_COLOR] as PackedColorArray), "requested exact color reaches deck vertex colors")
	check(Color("bca17d") in (arrays[Mesh.ARRAY_COLOR] as PackedColorArray), "wood plies preserve their own tint")
	var grip := model.get_node("GripTape") as MeshInstance3D
	check(grip.mesh.get_aabb().size.z > .8 and grip.mesh.get_aabb().size.x > .21, "deck retains authored dimensions")
	check((grip.material_override as StandardMaterial3D).albedo_texture != null, "grip retains grain texture")

func run() -> void:
	fixture_world = Node3D.new()
	root.add_child(fixture_world)
	var timings: Array[Dictionary] = []
	var signatures := {}
	var first_reference: Array[Dictionary] = []
	for tint: Color in PALETTE:
		var first := create_model(tint)
		var cold_usec := last_creation_usec
		check_shape(first, tint)
		var expected := describe(first)
		if first_reference.is_empty(): first_reference = expected
		signatures[tint.to_html()] = var_to_bytes(expected).hex_encode().sha256_text()
		var repetitions: Array[int] = []
		for iteration in 5:
			var other := create_model(tint)
			repetitions.append(last_creation_usec)
			compare(describe(other), expected, "%s repeat%d" % [tint.to_html(), iteration])
			check_shape(other, tint)
			for index in 4: check(first.wheels[index] != other.wheels[index], "wheel nodes belong to separate instances")
			var other_pose: Transform3D = other.wheels[0].transform
			first.wheels[0].rotate_x(.37)
			check(other.wheels[0].transform == other_pose, "rotating one board wheel does not rotate another")
			first.wheels[0].rotation = Vector3.ZERO
			var first_art := first.get_node("DeckTrucksAndHubs") as MeshInstance3D
			var other_art := other.get_node("DeckTrucksAndHubs") as MeshInstance3D
			first_art.transparency = .6
			check(other_art.transparency == 0.0, "fading one board does not fade the other")
			first_art.transparency = 0.0
			other.free()
		timings.append({"color":tint.to_html(), "first_usec":cold_usec, "repeat_usec":repetitions})
		first.free()
		var after_owner_free := create_model(tint)
		compare(describe(after_owner_free), expected, "resource lifetime after first model removal " + tint.to_html())
		after_owner_free.free()
	# Mais cores exatas únicas que a capacidade do cache exercitam despejo/reconstrução.
	# Nenhum teste depende de uma entrada específica ser retida ou reconstruída.
	for index in 10:
		var custom := create_model(Color(float(index + 1) / 17.0, .231, .517, 1.0))
		custom.free()
	var rebuilt := create_model(PALETTE[0])
	compare(describe(rebuilt), first_reference, "geometry survives bounded-cache color churn")
	rebuilt.free()
	print("SKATE_MODEL_SIGNATURES ", JSON.stringify(signatures))
	print("SKATE_MODEL_CPU ", JSON.stringify({"colors":timings, "scope":"Standalone CPU construction times; first color use and five repeated instances. Does not measure gameplay FPS or GPU completion."}))
	fixture_world.queue_free()
	await process_frame
	await process_frame
	print("SKATE_MODEL_CACHE checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
