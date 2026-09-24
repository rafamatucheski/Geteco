extends SceneTree

const ACTOR_SCRIPT := preload("res://characters/AnimatedPedestrian3D.gd")
const TILE_PIXELS := 104 * 104
const CELL_PIXELS := 130 * 104
const ATLAS_CAPACITY := 8
const DORMANT_VIEWPORT_PIXELS := 2 * 2

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("PEDESTRIAN_SUBVIEWPORT_BUDGET failure=", message)

func _run() -> void:
	var timeout := create_timer(30.0)
	timeout.timeout.connect(func() -> void:
		printerr("PEDESTRIAN_SUBVIEWPORT_BUDGET timeout")
		quit(2)
	)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var stage := Node2D.new()
	stage.name = "PedestrianViewportBudgetFixture"
	root.add_child(stage)
	current_scene = stage
	var camera := Camera2D.new()
	camera.position = Vector2(640.0, 360.0)
	camera.enabled = true
	stage.add_child(camera)
	var budget := root.get_node_or_null("PresentationBudget")
	_check(budget != null, "PresentationBudget autoload must exist")
	if budget == null:
		quit(1)
		return
	budget.set_process(false)
	var actors: Array[AnimatedPedestrian3D] = []
	for index in 10:
		var actor := ACTOR_SCRIPT.new() as AnimatedPedestrian3D
		actor.name = "BudgetResident_%02d" % index
		actor.ambient_low_lod = true
		actor.defer_presentation = true
		actor.appearance_seed = 700 + index
		actor.body_type_override = index % 5
		actor.archetype_override = [0, 1, 2, 4, 6, 7][index % 6]
		actor.appearance_gender = 1 + index % 2
		actor.position = Vector2(10000.0 + index * 50.0, 10000.0)
		if index == 0: actor.position = Vector2(640.0, 360.0)
		if index == 1: actor.position = Vector2(520.0, 300.0)
		if index == 2: actor.position = Vector2(760.0, 420.0)
		if index == 8: actor.position = Vector2(1240.0, 680.0)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.ensure_presentation()
		actor._viewport_cull_timer = 0.0
		actor._update_viewport_render_state(0.0)
		actors.append(actor)
	await process_frame
	await process_frame

	var stats: Dictionary = budget.get_ambient_atlas_stats()
	var initial_stats := stats.duplicate(true)
	var old_capacity_pixels := int(stats.atlas_viewports) * ATLAS_CAPACITY * CELL_PIXELS
	var old_capacity_pixels_per_second := old_capacity_pixels * 30.0
	var expected_scheduled_pixels_per_second := float(CELL_PIXELS * (3 * 30 + 20))
	_check(actors.size() == 10 and actors.all(func(actor: AnimatedPedestrian3D) -> bool: return actor.is_inside_tree()), "Atlas must not reduce the resident population")
	_check(int(stats.atlas_viewports) == 2, "Ten ambient residents must use two atlas SubViewports instead of ten personal SubViewports")
	_check(int(stats.active_viewports) == 2 and int(stats.visible_actors) == 4, "Only the two batches containing four camera-relevant residents may stay active")
	_check(int(stats.allocated_pixels) == 4 * CELL_PIXELS, "Atlas target must reserve one isolated cell per visible resident")
	_check(int(stats.allocated_pixels) < old_capacity_pixels, "Visible compaction must reduce allocated atlas pixels")
	_check(is_equal_approx(float(stats.scheduled_pixels_per_second), expected_scheduled_pixels_per_second), "Atlas cadence must account for three near residents at 30 Hz and one edge resident at 20 Hz")
	_check(float(stats.scheduled_pixels_per_second) < old_capacity_pixels_per_second * 0.25, "Visibility and distance cadence must remove at least 75% of the old full-capacity pixel schedule in this fixture")
	_check(is_equal_approx(float(actors[0].get_meta("presentation_render_hz", 0.0)), 30.0), "Resident near camera center must retain 30 Hz presentation")
	_check(is_equal_approx(float(actors[8].get_meta("presentation_render_hz", 0.0)), 20.0), "Resident near the camera edge must use the 20 Hz distance tier")

	var unique_viewports := {}
	var non_black_colors := {}
	for actor in actors:
		_check(actor.viewport != null and actor.model_root != null and actor.sprite_3d_display != null, "%s must keep a complete 3D viewport presentation" % actor.name)
		_check(actor.sprite_3d_display.texture == actor.viewport.get_texture(), "%s must display its live 3D atlas texture" % actor.name)
		_check(actor.sprite_3d_display.region_enabled, "%s must use an atlas region, never a 2D fallback" % actor.name)
		_check(int(actor.sprite_3d_display.region_rect.position.x) % 130 == 13, "%s atlas portrait must retain a 13 px transparent gutter" % actor.name)
		_check(not is_instance_valid(actor._presentation_fallback), "%s fallback silhouette must be released after 3D presentation" % actor.name)
		unique_viewports[actor.viewport.get_instance_id()] = true
		for mesh in actor.model_root.find_children("*", "MeshInstance3D", true, false):
			var material := (mesh as MeshInstance3D).material_override as StandardMaterial3D
			if material != null and mesh.name != &"GroundShadow":
				var color := material.albedo_color
				if maxf(color.r, maxf(color.g, color.b)) > 0.08:
					non_black_colors[color.to_html(false)] = true
	_check(unique_viewports.size() == 2, "All ten residents must share two atlas viewports")
	_check(non_black_colors.size() >= 5, "Shared atlas materials must preserve varied non-black character colors")

	for index in 3:
		actors[index].position = Vector2(10000.0 + index * 50.0, 10000.0)
		actors[index]._viewport_cull_timer = 0.0
		actors[index]._update_viewport_render_state(0.0)
	stats = budget.get_ambient_atlas_stats()
	_check(int(stats.active_viewports) == 1 and int(stats.visible_actors) == 1, "Off-screen batch must disable while the second batch remains visible")
	_check(int(stats.allocated_pixels) == CELL_PIXELS + DORMANT_VIEWPORT_PIXELS, "Disabled atlas must compact to the engine's 2x2 minimum instead of retaining eight cells")

	actors[0].position = Vector2(640.0, 360.0)
	actors[0].restore_presentation_after_sleep()
	actors[0]._viewport_cull_timer = 0.0
	actors[0]._update_viewport_render_state(0.0)
	stats = budget.get_ambient_atlas_stats()
	_check(int(stats.visible_actors) == 2 and int(stats.allocated_pixels) == 2 * CELL_PIXELS, "Returning resident must restore one isolated 3D cell without rebuilding population")
	actors[0].compact_presentation_for_sleep()
	stats = budget.get_ambient_atlas_stats()
	_check(int(stats.visible_actors) == 1 and int(stats.allocated_pixels) == CELL_PIXELS + DORMANT_VIEWPORT_PIXELS, "Sleeping resident must release its cell while preserving its rig")
	_check(actors[0].model_root != null and actors[0].is_inside_tree(), "Sleep compaction must not despawn or replace the 3D resident")

	print("PEDESTRIAN_SUBVIEWPORT_BUDGET before_viewports=10 after_viewports=%d before_capacity_pixels=%d initial_visible_pixels=%d final_visible_pixels=%d before_capacity_pixels_per_second=%.0f after_scheduled_pixels_per_second=%.0f initial_active_viewports=%d final_active_viewports=%d failures=%s" % [
		int(initial_stats.atlas_viewports), old_capacity_pixels, int(initial_stats.allocated_pixels), int(stats.allocated_pixels), old_capacity_pixels_per_second, float(initial_stats.scheduled_pixels_per_second), int(initial_stats.active_viewports), int(stats.active_viewports), str(failures)
	])
	stage.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
