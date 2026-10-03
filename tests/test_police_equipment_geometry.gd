extends SceneTree
## Compare the production merge with the original GPU-roundtrip algorithm.
## Run rendered. Optional --capture=res://evidence/police-equipment-before.png.
## Timings cover CPU method calls only; they do not establish gameplay FPS.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const PARTS := ["chest", "belt", "helmet", "glove", "thigh", "knee"]
const NORMAL_EPSILON := 0.0002
const COLOR_EPSILON := 1.0 / 255.0 + 0.0001
var checks := 0
var failures: Array[String] = []
var cold_usec: Array[int] = []
var hit_usec: Array[int] = []
var max_normal_error := 0.0
var max_color_error := 0.0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func source_mesh(part: String, heavy: bool) -> ArrayMesh:
	var profile := KIT.build_profile(false, 2 if heavy else 0)
	match part:
		"chest": return KIT.chest_mesh(profile, 8, false, 0)
		"belt": return KIT.pelvis_mesh(profile, 8, 0, 0)
		"helmet": return KIT.head_mesh(false, 0, 0, 6, false)
		"glove": return KIT.forearm_mesh(profile, 8, -1.0 if heavy else 1.0)
		"thigh": return KIT.thigh_mesh(profile, 0, 8)
		"knee": return KIT.shin_mesh(profile, 0, 8, 1)
	return null

func with_extra_surface(source: ArrayMesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
		result.surface_set_material(surface, source.surface_get_material(surface))
	var builder = KIT._builder()
	builder.ellipsoid(Vector3(0, .43, 0), Vector3(.06, .025, .04), KIT.SLOT_METAL)
	builder.commit(result, true)
	return result

func original_merge(model: Node3D, source: ArrayMesh, part: String) -> ArrayMesh:
	var builder = KIT._builder()
	model._build_equipment(builder, part)
	var extra: ArrayMesh = builder.commit()
	var original: Array = source.surface_get_arrays(0)
	var addition: Array = extra.surface_get_arrays(0)
	var offset: int = original[Mesh.ARRAY_VERTEX].size()
	original[Mesh.ARRAY_TANGENT] = null
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		var stream: Variant = original[channel]
		stream.append_array(addition[channel])
		original[channel] = stream
	var indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	for index in addition[Mesh.ARRAY_INDEX]: indices.append(int(index) + offset)
	original[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original)
	merged.surface_set_material(0, KIT.material())
	for surface in range(1, source.get_surface_count()):
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
		merged.surface_set_material(surface, source.surface_get_material(surface))
	return merged

func compare_arrays(actual: Array, expected: Array, label: String) -> void:
	var positions: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	var reference_positions: PackedVector3Array = expected[Mesh.ARRAY_VERTEX]
	check(positions == reference_positions, label + " identical vertex positions/order")
	check(actual[Mesh.ARRAY_INDEX] == expected[Mesh.ARRAY_INDEX], label + " identical triangle indices")
	var normals: PackedVector3Array = actual[Mesh.ARRAY_NORMAL]
	var reference_normals: PackedVector3Array = expected[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = actual[Mesh.ARRAY_COLOR]
	var reference_colors: PackedColorArray = expected[Mesh.ARRAY_COLOR]
	check(normals.size() == reference_normals.size() and colors.size() == reference_colors.size(), label + " complete normal/color streams")
	if normals.size() != reference_normals.size() or colors.size() != reference_colors.size(): return
	var normal_error := 0.0
	var color_error := 0.0
	var same_slots := true
	for index in normals.size(): normal_error = maxf(normal_error, normals[index].distance_to(reference_normals[index]))
	for index in colors.size():
		var a := colors[index]
		var b := reference_colors[index]
		color_error = maxf(color_error, maxf(maxf(absf(a.r-b.r), absf(a.g-b.g)), maxf(absf(a.b-b.b), absf(a.a-b.a))))
		same_slots = same_slots and int(a.r*16.0) == int(b.r*16.0)
	max_normal_error = maxf(max_normal_error, normal_error)
	max_color_error = maxf(max_color_error, color_error)
	check(normal_error <= NORMAL_EPSILON, label + " normals preserve orientation within octahedral quantization")
	check(color_error <= COLOR_EPSILON, label + " RGBA stays within one stored color level")
	check(same_slots, label + " material slot classification is unchanged")
	for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		check(actual[channel] == expected[channel], label + " untouched channel %d" % channel)

func mesh_instance(mesh: ArrayMesh, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.set_instance_shader_parameter("top_color", Color("343d52"))
	instance.set_instance_shader_parameter("accent_color", Color("596a59"))
	return instance

func setup_camera(stage: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("303640")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(0, .6, 12)
	stage.add_child(camera)
	camera.look_at(Vector3(0, .1, 0))
	camera.current = true

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	setup_camera(stage)
	var model = MODEL.new() # Deliberately outside the tree: no unrelated legacy body construction.
	var source_refs: Array[ArrayMesh] = []
	var drawable_refs: Array[WeakRef] = []
	var merged_refs: Array[WeakRef] = []
	var cases := 0
	for tier in [MODEL.UnitTier.SWAT, MODEL.UnitTier.FBI, MODEL.UnitTier.ARMY]:
		model.tier = tier
		for heavy in [false, true]:
			for part: String in PARTS:
				var source := source_mesh(part, heavy)
				if part == "chest" and heavy: source = with_extra_surface(source)
				source_refs.append(source) # Keep the original RID alive throughout cache assertions.
				var source_before: Array = source.surface_get_arrays(0)
				var source_material: Material = source.surface_get_material(0)
				var label := "%d/%s/%s" % [tier, "heavy" if heavy else "slim", part]
				var column: int = cases % 6
				@warning_ignore("integer_division")
				var row: int = cases / 6
				var position := Vector3(float(column)*1.12-2.8, 2.6-float(row)*.95, 0)
				var joint := mesh_instance(source, position + Vector3(.26, 0, 0))
				stage.add_child(joint)
				var initial_transform := joint.transform
				var cache_before: int = MODEL._equipment_meshes.size()
				var began := Time.get_ticks_usec()
				model._merge_equipment(joint, part)
				var elapsed := Time.get_ticks_usec() - began
				if MODEL._equipment_meshes.size() > cache_before: cold_usec.append(elapsed)
				check(joint.transform == initial_transform, label + " joint transform preserved")
				var expected := original_merge(model, source, part)
				check(joint.mesh.get_surface_count() == source.get_surface_count(), label + " surface count preserved")
				for surface in expected.get_surface_count():
					compare_arrays(joint.mesh.surface_get_arrays(surface), expected.surface_get_arrays(surface), label + "/surface%d" % surface)
					check(joint.mesh.surface_get_material(surface) == expected.surface_get_material(surface), label + " surface material preserved")
				check(source.surface_get_arrays(0) == source_before and source.surface_get_material(0) == source_material, label + " shared source remains unchanged")
				var duplicate := mesh_instance(source, Vector3.ZERO)
				var cache_warm: int = MODEL._equipment_meshes.size()
				began = Time.get_ticks_usec()
				model._merge_equipment(duplicate, part)
				hit_usec.append(Time.get_ticks_usec() - began)
				check(duplicate.mesh == joint.mesh and MODEL._equipment_meshes.size() == cache_warm, label + " repeat identity reuses merged resource")
				duplicate.free()
				stage.add_child(mesh_instance(expected, position + Vector3(-.26, 0, 0)))
				drawable_refs.append(weakref(joint))
				merged_refs.append(weakref(joint.mesh))
				cases += 1
	var report := {"cases": cases, "cold_calls": cold_usec.size(), "cold_usec": cold_usec,
		"hit_usec": hit_usec, "max_normal_error": max_normal_error, "max_color_error": max_color_error,
		"scope": "CPU merge-call timing and mesh equivalence; not gameplay FPS. Image pairs: original left, production right."}
	print("POLICE_EQUIPMENT_GEOMETRY_METRICS ", JSON.stringify(report))
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture="): continue
		var output := argument.trim_prefix("--capture=")
		if DisplayServer.get_name() == "headless":
			check(false, "capture requires a rendered viewport")
			continue
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
		check(root.get_texture().get_image().save_png(output) == OK, "comparison image saved")
		print("POLICE_EQUIPMENT_GEOMETRY_CAPTURE ", output)
	model.free()
	stage.queue_free()
	await process_frame
	await process_frame
	for reference: WeakRef in drawable_refs: check(reference.get_ref() == null, "joint released with fixture")
	for reference: WeakRef in merged_refs: check(reference.get_ref() != null, "immutable merged mesh remains reusable in existing cache")
	print("POLICE_EQUIPMENT_GEOMETRY checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
