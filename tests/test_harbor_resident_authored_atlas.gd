extends SceneTree

const ACTOR_SCRIPT := preload("res://characters/AnimatedPedestrian3D.gd")
const MAX_BUILD_USEC := 16670

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error(message)


func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		printerr("HARBOR_RESIDENT_AUTHORED_ATLAS timeout")
		quit(2)
	)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	preload("res://characters/pedestrians/CitizenGeometry.gd").prewarm_vertex_color_mesh()
	ACTOR_SCRIPT.prewarm_ambient_primitives()
	var stage := Node2D.new()
	stage.name = "HarborResidentAuthoredAtlasFixture"
	root.add_child(stage)
	current_scene = stage
	var camera := Camera2D.new()
	camera.position = Vector2(640.0, 360.0)
	camera.enabled = true
	stage.add_child(camera)
	var budget := root.get_node("PresentationBudget")
	await budget.prewarm_ambient_authored()
	budget.set_process(false)
	var actors: Array[AnimatedPedestrian3D] = []
	var build_usec := PackedInt64Array()
	var unique_viewports := {}
	var colors := {}
	for index in 10:
		var actor := ACTOR_SCRIPT.new() as AnimatedPedestrian3D
		actor.name = "AuthoredHarborResident_%02d" % index
		actor.ambient_low_lod = false
		actor.ambient_presentation_atlas = true
		actor.defer_presentation = true
		actor.appearance_seed = 9200 + index
		actor.body_type_override = index % 5
		actor.archetype_override = [0, 1, 2, 4, 6, 7][index % 6]
		actor.appearance_gender = 1 + index % 2
		actor.position = Vector2(160.0 + index * 96.0, 360.0)
		stage.add_child(actor)
		actor.set_physics_process(false)
		var started := Time.get_ticks_usec()
		actor.ensure_presentation()
		if actor.viewport == null:
			await actor.presentation_ready
		build_usec.append(Time.get_ticks_usec() - started)
		actors.append(actor)
		unique_viewports[actor.viewport.get_instance_id()] = true
		_check(actor._presentation_atlas_active, "%s must use the shared atlas" % actor.name)
		_check(actor.model_root.find_children("*", "MeshInstance3D", true, false).size() >= 12, "%s must retain the authored detailed rig" % actor.name)
		_check(actor.head_node != null and actor.head_node.get_child_count() > 2, "%s must retain authored head details/accessories" % actor.name)
		_check(actor.gait != null, "%s must retain articulated gait" % actor.name)
		for mesh_value in actor.model_root.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_value as MeshInstance3D
			var material := mesh.material_override as StandardMaterial3D
			if material != null and mesh.name != &"GroundShadow":
				colors[material.albedo_color.to_html(false)] = true
	await process_frame
	var maximum_usec := 0
	var total_usec := 0
	for value in build_usec:
		maximum_usec = maxi(maximum_usec, int(value))
		total_usec += int(value)
	_check(unique_viewports.size() == 2, "ten authored residents must use two shared atlas SubViewports")
	_check(colors.size() >= 8, "authored atlas must preserve varied clothing and skin materials")
	var maximum_stage_usec := 0
	var maximum_stage_label := ""
	var stage_samples: Array[Dictionary] = []
	for actor in actors:
		var actor_max := int(actor.get_meta("presentation_stage_max_usec", 0))
		stage_samples.append({"actor": actor.name, "max_ms": actor_max / 1000.0, "stage": String(actor.get_meta("presentation_stage_max_label", ""))})
		if actor_max > maximum_stage_usec:
			maximum_stage_usec = actor_max
			maximum_stage_label = String(actor.get_meta("presentation_stage_max_label", ""))
	_check(maximum_stage_usec <= MAX_BUILD_USEC, "authored resident stage exceeded %.2f ms: %.3f ms" % [MAX_BUILD_USEC / 1000.0, maximum_stage_usec / 1000.0])
	print("HARBOR_RESIDENT_AUTHORED_ATLAS actors=%d viewports=%d average_ms=%.3f max_ms=%.3f max_stage_ms=%.3f max_stage=%s stage_samples=%s colors=%d failures=%s" % [
		actors.size(), unique_viewports.size(), (total_usec / float(build_usec.size())) / 1000.0,
		maximum_usec / 1000.0, maximum_stage_usec / 1000.0, maximum_stage_label, str(stage_samples), colors.size(), str(failures)
	])
	stage.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
