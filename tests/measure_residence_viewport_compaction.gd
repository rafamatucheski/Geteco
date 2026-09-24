extends SceneTree

## Rendered HarborGame contract for residential SubViewport compaction. Global
## renderer memory remains an observation only; attributable savings are ranked
## with viewport pixels and MSAA pixel-samples.

const GAME := preload("res://world/harbor/HarborGame.tscn")
const STARTUP_TIMEOUT_MSEC := 180000
const TRANSITION_TIMEOUT_MSEC := 8000

var output_dir := "res://_codex_diag"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Residence compaction measurement requires a real renderer")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			output_dir = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", ProjectSettings.globalize_path(output_dir.path_join("saves")) + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)

	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	var startup_deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while (not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready"))) and Time.get_ticks_msec() < startup_deadline:
		await process_frame
	if not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready")):
		_fail("HarborGame did not reach its playable state")
		await _finish(world, {})
		return
	for _frame in 120:
		await process_frame

	var manager := world.get_node("ResidencePrototype") as ResidenceManager
	var interiors := world.get_node("Interiors")
	var player := world.get_node("Player") as CharacterBody2D
	var rooms: Array[ResidenceInterior] = []
	for value in manager.residence_interiors.values():
		rooms.append(value as ResidenceInterior)
	var initial_renderer_memory := _renderer_memory()
	var initial_pixels := _room_pixels(rooms)
	var initial_sample_pixels := _room_sample_pixels(rooms)
	var authored_pixels := 0
	var authored_sample_pixels := 0
	for room in rooms:
		var size := room.authored_viewport_size()
		var pixels := size.x * size.y
		authored_pixels += pixels
		authored_sample_pixels += pixels * _msaa_samples(room.viewport_3d.msaa_3d)
		_check(room.is_presentation_compacted() and room.viewport_3d.size == Vector2i(2, 2), "%s starts at Godot's effective 2x2 minimum" % room.name)
		_check(not room.room_display.visible and room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "%s has no inactive presentation submission" % room.name)

	manager.state["active_home"] = "westgate_garden"
	manager._commit_state()
	manager._sync_active_visuals()
	var room := manager.residence_interiors["westgate_garden"] as ResidenceInterior
	var collision_before := _collision_signature(room)
	var spawn_before := room.spawn_point.position
	var frame_ms: Array[float] = []
	var transition_started := Time.get_ticks_usec()
	var previous_tick := transition_started
	_check(manager.enter_home("westgate_garden"), "real residence transition accepts the active home")
	var transition_deadline := Time.get_ticks_msec() + TRANSITION_TIMEOUT_MSEC
	while interiors.is_transitioning() and Time.get_ticks_msec() < transition_deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous_tick) / 1000.0)
		previous_tick = now
	var transition_usec := Time.get_ticks_usec() - transition_started
	_check(not interiors.is_transitioning(), "residence entry transition completes")
	_check(player.has_meta("harbor_interior") and room.contains_point(player.global_position), "entry reaches the real residential interior")
	_check(room.is_entry_frame_ready() and room.room_display.visible, "room is rendered before fade-in exposes it")
	_check(room.viewport_3d.size == room.authored_viewport_size(), "active room restores authored target size")
	var actor_presentation := player.get_meta("interior_actor_presentation", null) as Node
	_check(is_instance_valid(actor_presentation), "resident actor shares the room depth presentation")
	var player_viewport := player.get("viewport_3d") as SubViewport
	_check(is_instance_valid(player_viewport) and player_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "shared room depth suspends the actor's private viewport")
	var player_model := player.get("model_root") as Node3D
	_check(is_instance_valid(player_model) and player_model.get_viewport() == room.viewport_3d, "InteriorActorPresentation reparents the real Player rig into the residence viewport")
	_check(_texture_has_visible_room(room.viewport_3d), "restored target contains visible room pixels")
	_check(_collision_signature(room) == collision_before and room.spawn_point.position.is_equal_approx(spawn_before), "entry preserves projected solids and spawn")
	var physics_gate: Dictionary = {}
	var depth_gate: Dictionary = {}
	if is_instance_valid(actor_presentation):
		physics_gate = await _check_real_actor_physics(player, room, actor_presentation)
		depth_gate = await _check_actor_depth_occlusion(player, room, actor_presentation)
	await RenderingServer.frame_post_draw
	var entry_capture_error := root.get_texture().get_image().save_png(output_dir.path_join("residence-viewport-compaction-entry.png"))
	_check(entry_capture_error == OK, "rendered residence entry capture is persisted")
	var active_renderer_memory := _renderer_memory()

	_check(manager.exit_home("westgate_garden"), "real residence transition accepts exit")
	transition_deadline = Time.get_ticks_msec() + TRANSITION_TIMEOUT_MSEC
	while interiors.is_transitioning() and Time.get_ticks_msec() < transition_deadline:
		await process_frame
	for _frame in 3:
		await process_frame
	_check(not interiors.is_transitioning() and not player.has_meta("harbor_interior"), "residence exit completes")
	_check(room.is_presentation_compacted() and room.viewport_3d.size == Vector2i(2, 2), "exited residence returns to compact target")
	_check(not player.has_meta("interior_actor_presentation"), "exit restores the actor's private presentation")
	_check(_collision_signature(room) == collision_before and room.spawn_point.position.is_equal_approx(spawn_before), "exit preserves projected solids and spawn")
	var exit_renderer_memory := _renderer_memory()
	var report := {
		"scenario": "HarborGame real residential entry and exit",
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size),
		"residence_viewport_count": rooms.size(),
		"inactive_target_size": str(Vector2i(2, 2)),
		"inactive_pixels": initial_pixels,
		"inactive_pixel_samples": initial_sample_pixels,
		"authored_pixels": authored_pixels,
		"authored_pixel_samples": authored_sample_pixels,
		"attributable_pixels_avoided_while_inactive": authored_pixels - initial_pixels,
		"attributable_pixel_samples_avoided_while_inactive": authored_sample_pixels - initial_sample_pixels,
		"renderer_memory_bytes_global_initial": initial_renderer_memory,
		"renderer_memory_bytes_global_active_room": active_renderer_memory,
		"renderer_memory_bytes_global_after_exit": exit_renderer_memory,
		"memory_attribution_contract": "Renderer memory is global observation only; residential attribution uses viewport pixels and MSAA pixel-samples.",
		"entry_transition_usec": transition_usec,
		"entry_prewarm_usec": room.last_entry_prepare_usec,
		"entry_frame_count": frame_ms.size(),
		"entry_frame_ms_p50": _percentile(frame_ms, 0.50),
		"entry_frame_ms_p95": _percentile(frame_ms, 0.95),
		"entry_frame_ms_max": frame_ms.max() if not frame_ms.is_empty() else 0.0,
		"real_actor_physics_gate": physics_gate,
		"actor_depth_gate": depth_gate,
		"failures": failures,
	}
	var report_file := FileAccess.open(output_dir.path_join("residence-viewport-compaction-result.json"), FileAccess.WRITE)
	if report_file == null:
		_fail("Could not write result.json")
	else:
		report_file.store_string(JSON.stringify(report, "\t"))
	print("RESIDENCE_VIEWPORT_COMPACTION_RENDERED ", JSON.stringify(report))
	await _finish(world, report)


func _room_pixels(rooms: Array[ResidenceInterior]) -> int:
	var total := 0
	for room in rooms:
		total += room.viewport_3d.size.x * room.viewport_3d.size.y
	return total


func _room_sample_pixels(rooms: Array[ResidenceInterior]) -> int:
	var total := 0
	for room in rooms:
		total += room.viewport_3d.size.x * room.viewport_3d.size.y * _msaa_samples(room.viewport_3d.msaa_3d)
	return total


func _msaa_samples(msaa: Viewport.MSAA) -> int:
	match msaa:
		Viewport.MSAA_2X: return 2
		Viewport.MSAA_4X: return 4
		Viewport.MSAA_8X: return 8
		_: return 1


func _texture_has_visible_room(viewport: SubViewport) -> bool:
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != viewport.size:
		return false
	var visible_samples := 0
	for y in range(0, image.get_height(), 80):
		for x in range(0, image.get_width(), 80):
			if image.get_pixel(x, y).a > 0.05:
				visible_samples += 1
	return visible_samples >= 8


func _check_real_actor_physics(actor: CharacterBody2D, room: ResidenceInterior, presentation: Node) -> Dictionary:
	var physics_was_active := actor.is_physics_processing()
	actor.set_physics_process(false)
	actor.velocity = Vector2.ZERO
	actor.global_position = room.spawn_point.global_position
	actor.reset_physics_interpolation()
	presentation._update_scale()
	await physics_frame

	# This center lane is intentionally clear in the authored residence. Move the
	# complete production Player body through it in both directions so an
	# over-broad projected solid cannot pass as successful furniture blocking.
	var corridor_target := room.to_global(room.project_floor(Vector2(0.0, 0.4)))
	var corridor_hit := actor.move_and_collide(corridor_target - actor.global_position)
	var corridor_forward_clear := corridor_hit == null and actor.global_position.distance_to(corridor_target) < 0.1
	_check(corridor_forward_clear, "real Player body traverses the authored residence center corridor")
	var return_hit := actor.move_and_collide(room.spawn_point.global_position - actor.global_position)
	var corridor_return_clear := return_hit == null and actor.global_position.distance_to(room.spawn_point.global_position) < 0.1
	_check(corridor_return_clear, "real Player body can return through the authored residence center corridor")

	# DoorBoundary is a narrow authored solid. A single large motion must still
	# collide, proving swept movement rather than endpoint-only overlap.
	var boundary_target := room.to_global(room.project_floor(Vector2(0.0, 5.6)))
	var boundary_hit := actor.move_and_collide(boundary_target - actor.global_position)
	var boundary_blocked := boundary_hit != null and boundary_hit.get_collider() == room.walls_body and actor.global_position.distance_to(boundary_target) > 1.0
	_check(boundary_blocked, "real Player swept body cannot tunnel through the residence door boundary")

	actor.global_position = room.spawn_point.global_position
	actor.velocity = Vector2.ZERO
	actor.reset_physics_interpolation()
	presentation._update_scale()
	actor.set_physics_process(physics_was_active)
	return {
		"corridor_forward_clear": corridor_forward_clear,
		"corridor_return_clear": corridor_return_clear,
		"solid_boundary_blocked": boundary_blocked,
		"solid_boundary": "DoorBoundary",
	}


func _check_actor_depth_occlusion(actor: CharacterBody2D, room: ResidenceInterior, presentation: Node) -> Dictionary:
	var physics_was_active := actor.is_physics_processing()
	var presentation_was_active := presentation.is_processing()
	actor.set_physics_process(false)
	actor.velocity = Vector2.ZERO
	actor.global_position = room.to_global(room.project_floor(Vector2(0.0, 0.4)))
	actor.reset_physics_interpolation()
	presentation._update_scale()
	presentation.set_process(false)

	# Compare the same crop with and without the borrowed rig. The opaque probe is
	# rendered in the room viewport between the camera and actor, exercising the
	# exact depth buffer used by InteriorActorPresentation.
	var panel := MeshInstance3D.new()
	panel.name = "ResidenceActorOcclusionProbe"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(4.0, 4.0, 0.2)
	panel.mesh = panel_mesh
	var panel_material := StandardMaterial3D.new()
	panel_material.albedo_color = Color("427766")
	panel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = panel_material
	room.viewport_3d.add_child(panel)
	var actor_focus_world: Vector3 = presentation.anchor.global_position + Vector3.UP * 0.9
	panel.global_position = actor_focus_world + (room.room_camera.global_position - actor_focus_world).normalized() * 1.5
	panel.look_at(room.room_camera.global_position)
	var focus_pixel := room.room_camera.unproject_position(actor_focus_world)
	print("RESIDENCE_DEPTH_DEBUG focus=%s viewport=%s anchor=%s rig_visible=%s" % [focus_pixel, room.viewport_3d.size, presentation.anchor.global_position, presentation.rig.visible])

	panel.show()
	var occluded_changed_pixels := await _actor_pixel_difference(room.viewport_3d, presentation.rig, focus_pixel)
	_check(occluded_changed_pixels == 0, "opaque room depth fully occludes the shared resident actor")
	panel.hide()
	var visible_changed_pixels := await _actor_pixel_difference(room.viewport_3d, presentation.rig, focus_pixel)
	_check(visible_changed_pixels > 100, "unobstructed shared resident actor remains visibly rendered as positive control")

	panel.queue_free()
	presentation.anchor.show()
	presentation.rig.show()
	presentation.set_process(presentation_was_active)
	actor.global_position = room.spawn_point.global_position
	actor.velocity = Vector2.ZERO
	actor.reset_physics_interpolation()
	presentation._update_scale()
	actor.set_physics_process(physics_was_active)
	return {
		"occluded_changed_pixels": occluded_changed_pixels,
		"visible_control_changed_pixels": visible_changed_pixels,
		"positive_control_passed": visible_changed_pixels > 100,
	}


func _actor_pixel_difference(viewport: SubViewport, actor_visual: Node3D, focus_pixel: Vector2) -> int:
	var visible_parts: Array[VisualInstance3D] = []
	if actor_visual is VisualInstance3D and actor_visual.visible:
		visible_parts.append(actor_visual as VisualInstance3D)
	for node in actor_visual.find_children("*", "VisualInstance3D", true, false):
		var part := node as VisualInstance3D
		if part != null and part.visible:
			visible_parts.append(part)
	actor_visual.show()
	for _frame in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var with_actor := viewport.get_texture().get_image().duplicate()
	for part in visible_parts:
		part.hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for _frame in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var without_actor := viewport.get_texture().get_image().duplicate()
	for part in visible_parts:
		part.show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if with_actor == null or without_actor == null or with_actor.is_empty() or without_actor.is_empty():
		return 0
	var left := clampi(int(focus_pixel.x) - 20, 0, with_actor.get_width())
	var right := clampi(int(focus_pixel.x) + 20, 0, with_actor.get_width())
	var top := clampi(int(focus_pixel.y) - 25, 0, with_actor.get_height())
	var bottom := clampi(int(focus_pixel.y) + 25, 0, with_actor.get_height())
	var changed := 0
	for y in range(top, bottom):
		for x in range(left, right):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y):
				changed += 1
	if changed == 0:
		var full_changed := 0
		var bounds := Rect2i()
		for y in range(with_actor.get_height()):
			for x in range(with_actor.get_width()):
				if with_actor.get_pixel(x, y) == without_actor.get_pixel(x, y):
					continue
				if full_changed == 0:
					bounds = Rect2i(x, y, 1, 1)
				else:
					bounds = bounds.expand(Vector2i(x, y))
				full_changed += 1
		print("RESIDENCE_DEPTH_FULL_SCAN focus=%s crop=%s full_changed=%d bounds=%s" % [focus_pixel, Rect2i(left, top, right - left, bottom - top), full_changed, bounds])
		return full_changed
	return changed


func _collision_signature(room: ResidenceInterior) -> String:
	var parts: Array[String] = []
	for child in room.walls_body.get_children():
		if child is CollisionPolygon2D:
			parts.append(str(child.polygon))
		elif child is CollisionShape2D and child.shape != null:
			parts.append("%s:%s:%s" % [child.name, child.position, child.shape.get_rect()])
	return "|".join(parts)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)]


func _renderer_memory() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)


func _check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _finish(world: Node, report: Dictionary) -> void:
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() and not report.is_empty() else 1)
