extends SceneTree

## Counts resident per-actor 3D worlds in the production HarborGame. This is
## diagnostic-only: disabled SubViewports can still retain a World3D, camera,
## light, materials and meshes even when they submit no frames.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	var world := preload("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while not world.gameplay_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.gameplay_ready:
		push_error("Presentation residency checkpoint did not become playable")
		quit(1)
		return
	for frame in 90:
		await process_frame
	var report := {
		"pedestrians": _actor_group("pedestrian"),
		"vehicles": _actor_group("vehicle"),
		"all": _all_viewports(world),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}
	print("PRESENTATION_RESIDENCY ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit()

func _actor_group(group: StringName) -> Dictionary:
	var result := {"actors": 0, "sleeping": 0, "with_viewport": 0,
		"sleeping_with_viewport": 0, "active_with_viewport": 0,
		"own_world_3d": 0, "enabled_updates": 0, "mesh_instances": 0}
	var visited := {}
	for actor_value in get_nodes_in_group(group):
		if not actor_value is Node or not is_instance_valid(actor_value):
			continue
		var actor := actor_value as Node
		var id := actor.get_instance_id()
		if visited.has(id):
			continue
		visited[id] = true
		result.actors += 1
		var sleeping: bool = bool(actor.get_meta("proximity_sleeping", false))
		if sleeping: result.sleeping += 1
		var views := actor.find_children("*", "SubViewport", true, false)
		if views.is_empty():
			continue
		result.with_viewport += 1
		if sleeping: result.sleeping_with_viewport += 1
		else: result.active_with_viewport += 1
		for view_value in views:
			var view := view_value as SubViewport
			if view.own_world_3d: result.own_world_3d += 1
			if view.render_target_update_mode != SubViewport.UPDATE_DISABLED: result.enabled_updates += 1
		result.mesh_instances += actor.find_children("*", "MeshInstance3D", true, false).size()
	return result

func _all_viewports(world: Node) -> Dictionary:
	var result := {"subviewports": 0, "own_world_3d": 0, "enabled_updates": 0}
	for value in world.find_children("*", "SubViewport", true, false):
		var view := value as SubViewport
		result.subviewports += 1
		if view.own_world_3d: result.own_world_3d += 1
		if view.render_target_update_mode != SubViewport.UPDATE_DISABLED: result.enabled_updates += 1
	return result
