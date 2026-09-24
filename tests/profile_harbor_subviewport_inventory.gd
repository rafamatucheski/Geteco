extends SceneTree

## Rendered, non-mutating inventory of every quality-managed SubViewport while
## the production HarborGame is playable. Renderer memory is reported only as a
## global observation; per-owner attribution uses counts, pixels and MSAA sample
## pixels because Godot does not expose allocation bytes per SubViewport.

const GAME := preload("res://world/harbor/HarborGame.tscn")
const STARTUP_TIMEOUT_MSEC := 180000
const SETTLE_FRAMES := 120
const TOP_LIMIT := 30

var _output_dir := "res://_codex_diag/harbor-subviewport-inventory"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("SubViewport memory inventory requires a real renderer")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_output_dir = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", ProjectSettings.globalize_path(_output_dir.path_join("saves")) + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [
		&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met",
		&"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete",
	]:
		campaign.set_campaign_flag(flag, true)

	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while (not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready"))) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(world.get("gameplay_ready")) or not bool(world.get("world_build_ready")) or paused:
		_fail("HarborGame did not reach its normal playable state")
		await _finish(world, {})
		return
	for _frame in SETTLE_FRAMES:
		await process_frame

	var records: Array[Dictionary] = []
	for viewport in _all_viewports():
		records.append(_record(viewport, world))
	records.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.pixel_samples) > int(b.pixel_samples))
	var by_category := _aggregate(records, "category")
	var by_owner := _aggregate(records, "owner_key")
	var by_owner_instance := _aggregate(records, "owner_path")
	var by_mode := _aggregate(records, "update_mode")
	var by_population := _aggregate(records, "population_state")
	var by_residency := _aggregate(records, "residency_state")
	var by_lifecycle := _aggregate(records, "lifecycle_state")
	var by_quality_management := _aggregate(records, "quality_state")
	var by_size := _aggregate(records, "size")
	var dormant: Array[Dictionary] = []
	var sleeping: Array[Dictionary] = []
	var quality_managed_count := 0
	for item in records:
		if bool(item.dormant):
			dormant.append(item)
		if item.population_state == "sleeping":
			sleeping.append(item)
		if bool(item.quality_managed):
			quality_managed_count += 1
	var worlds := {}
	for item in records:
		worlds[item.world_id] = true
	var report := {
		"scope": "Every live SubViewport under the HarborGame SceneTree, including autoload-owned caches",
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size),
		"renderer_video_memory_bytes_global": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"process_static_memory_bytes_global": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"memory_attribution_contract": "Global renderer memory is not attributed to owners; owner rankings use viewport pixels and MSAA pixel-samples only.",
		"viewport_count": records.size(),
		"quality_managed_viewport_count": quality_managed_count,
		"quality_unmanaged_viewport_count": records.size() - quality_managed_count,
		"unique_world_count": worlds.size(),
		"total_pixels": _sum(records, "pixels"),
		"total_pixel_samples": _sum(records, "pixel_samples"),
		"dormant_count": dormant.size(),
		"dormant_pixels": _sum(dormant, "pixels"),
		"dormant_pixel_samples": _sum(dormant, "pixel_samples"),
		"sleeping_population_count": sleeping.size(),
		"sleeping_population_pixels": _sum(sleeping, "pixels"),
		"sleeping_population_pixel_samples": _sum(sleeping, "pixel_samples"),
		"by_category": by_category,
		"by_owner": by_owner,
		"by_owner_instance": by_owner_instance,
		"by_update_mode": by_mode,
		"by_population_state": by_population,
		"by_residency_state": by_residency,
		"by_lifecycle_state": by_lifecycle,
		"by_quality_management": by_quality_management,
		"by_size": by_size,
		"largest_dormant": dormant.slice(0, mini(TOP_LIMIT, dormant.size())),
		"largest_sleeping_population": sleeping.slice(0, mini(TOP_LIMIT, sleeping.size())),
		"largest_all": records.slice(0, mini(TOP_LIMIT, records.size())),
		"failures": _failures,
	}
	var report_file := FileAccess.open(_output_dir.path_join("inventory.json"), FileAccess.WRITE)
	if report_file == null:
		_fail("Could not write inventory.json")
	else:
		report_file.store_string(JSON.stringify(report, "\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output_dir.path_join("inventory-scene.png"))
	print("HARBOR_SUBVIEWPORT_INVENTORY count=%d dormant=%d pixels=%d sample_pixels=%d render_memory=%d failures=%s" % [
		records.size(), dormant.size(), int(report.total_pixels), int(report.total_pixel_samples),
		int(report.renderer_video_memory_bytes_global), JSON.stringify(_failures),
	])
	print("HARBOR_SUBVIEWPORT_CATEGORIES ", JSON.stringify(by_category))
	print("HARBOR_SUBVIEWPORT_TOP_DORMANT ", JSON.stringify(report.largest_dormant))
	await _finish(world, report)


func _record(viewport: SubViewport, world: Node) -> Dictionary:
	var owner := _owner_for(viewport, world)
	var population_actor := _population_actor_for(viewport, world)
	var interior_root := _interior_root_for(viewport)
	var population_state := "not_population"
	if population_actor != null:
		population_state = "sleeping" if bool(population_actor.get_meta("proximity_sleeping", false)) else "active"
	var owner_script := _script_path(owner)
	var ancestry := _ancestry_signature(viewport, world)
	var size_key := "%dx%d" % [viewport.size.x, viewport.size.y]
	var samples := _msaa_samples(viewport.msaa_3d if not viewport.disable_3d else viewport.msaa_2d)
	var pixels := maxi(0, viewport.size.x) * maxi(0, viewport.size.y)
	var found_world := viewport.find_world_3d()
	var world_id := 0
	if found_world != null and found_world.get_rid().is_valid():
		world_id = found_world.get_rid().get_id()
	var inactive_interior := interior_root != null and (not interior_root.visible or interior_root.process_mode == Node.PROCESS_MODE_DISABLED)
	var dormant := viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	var lifecycle_state := "resident"
	if population_state == "sleeping":
		lifecycle_state = "sleeping_population"
	elif inactive_interior:
		lifecycle_state = "inactive_interior"
	elif dormant:
		lifecycle_state = "dormant_cache"
	elif owner != null and owner.process_mode == Node.PROCESS_MODE_DISABLED:
		lifecycle_state = "disabled_owner"
	return {
		"path": str(viewport.get_path()),
		"name": viewport.name,
		"owner_path": str(owner.get_path()) if owner != null else "",
		"owner_name": owner.name if owner != null else "",
		"owner_script": owner_script,
		"owner_key": owner_script if not owner_script.is_empty() else ((owner.get_class() + ":" + str(owner.name)) if owner != null else "unknown"),
		"owner_ancestry": ancestry,
		"category": _category_for(viewport, owner, population_actor, ancestry),
		"population_state": population_state,
		"population_actor": str(population_actor.get_path()) if population_actor != null else "",
		"interior_root": str(interior_root.get_path()) if interior_root != null else "",
		"inactive_interior": inactive_interior,
		"lifecycle_state": lifecycle_state,
		"supports_sleep_compaction": population_actor != null and population_actor.has_method("compact_presentation_for_sleep"),
		"dormant": dormant,
		"residency_state": "dormant" if dormant else "resident",
		"quality_managed": viewport.is_in_group("quality_viewports"),
		"quality_state": "managed" if viewport.is_in_group("quality_viewports") else "unmanaged",
		"update_mode": _mode_name(viewport.render_target_update_mode),
		"size": size_key,
		"width": viewport.size.x,
		"height": viewport.size.y,
		"pixels": pixels,
		"msaa": int(viewport.msaa_3d if not viewport.disable_3d else viewport.msaa_2d),
		"msaa_samples": samples,
		"pixel_samples": pixels * samples,
		"disable_3d": viewport.disable_3d,
		"own_world_3d": viewport.own_world_3d,
		"world_id": world_id,
		"mesh_instances": viewport.find_children("*", "MeshInstance3D", true, false).size(),
		"lights": viewport.find_children("*", "Light3D", true, false).size(),
	}


func _all_viewports() -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	var seen := {}
	# Tree traversal is the source of truth. The quality group is diagnostic: an
	# ungrouped viewport is exactly the kind of blind spot this audit must expose.
	for candidate in root.find_children("*", "SubViewport", true, false):
		var viewport := candidate as SubViewport
		if viewport == null or not is_instance_valid(viewport):
			continue
		seen[viewport.get_instance_id()] = true
		result.append(viewport)
	for candidate in get_nodes_in_group("quality_viewports"):
		var viewport := candidate as SubViewport
		if viewport == null or not is_instance_valid(viewport) or seen.has(viewport.get_instance_id()):
			continue
		seen[viewport.get_instance_id()] = true
		result.append(viewport)
	return result


func _owner_for(viewport: SubViewport, world: Node) -> Node:
	var cursor := viewport.get_parent()
	var fallback := cursor
	while cursor != null and cursor != root:
		if not _script_path(cursor).is_empty():
			return cursor
		if cursor == world:
			break
		cursor = cursor.get_parent()
	return fallback


func _population_actor_for(viewport: SubViewport, world: Node) -> Node2D:
	var cursor := viewport.get_parent()
	while cursor != null and cursor != root:
		if cursor is Node2D and (cursor.is_in_group("vehicle") or cursor.is_in_group("pedestrian") or cursor.has_meta("proximity_sleeping")):
			return cursor as Node2D
		if cursor == world:
			break
		cursor = cursor.get_parent()
	return null


func _interior_root_for(viewport: SubViewport) -> Node2D:
	var cursor := viewport.get_parent()
	while cursor != null and cursor != root:
		var parent := cursor.get_parent()
		if cursor is Node2D and parent != null and parent.name == &"InteriorSpaces":
			return cursor as Node2D
		cursor = parent
	return null


func _category_for(viewport: SubViewport, owner: Node, population_actor: Node2D, ancestry: String) -> String:
	if population_actor != null:
		if population_actor.is_in_group("vehicle"):
			return "vehicles"
		return "pedestrians"
	var owner_path := _script_path(owner).to_lower()
	var node_path := str(viewport.get_path()).to_lower()
	var tokens := owner_path + " " + node_path + " " + ancestry
	if tokens.contains("presentationbudget") or tokens.contains("ambientcharacteratlas") or tokens.contains("sharedcharacterworld"):
		return "system_atlas"
	if tokens.contains("/interior") or tokens.contains("/residences/") or tokens.contains("room"):
		return "interiors"
	if _contains_any(tokens, ["vehicle", "traffic", "car3d", "trainpiece", "coach", "ambulance", "firetruck", "policecar"]):
		return "vehicles"
	if _contains_any(tokens, ["pedestrian", "character", "npc", "officer", "paramedic", "mortician", "firefighter", "resident", "driver"]):
		return "pedestrians"
	if viewport.render_target_update_mode in [SubViewport.UPDATE_DISABLED, SubViewport.UPDATE_ONCE]:
		return "static_props"
	return "other_live"


func _ancestry_signature(viewport: SubViewport, world: Node) -> String:
	var parts: Array[String] = []
	var cursor: Node = viewport
	while cursor != null and cursor != root:
		parts.append((str(cursor.name) + " " + _script_path(cursor)).to_lower())
		if cursor == world:
			break
		cursor = cursor.get_parent()
	return " | ".join(parts)


func _contains_any(value: String, needles: Array) -> bool:
	for needle in needles:
		if value.contains(needle):
			return true
	return false


func _script_path(node: Node) -> String:
	if node == null:
		return ""
	var script := node.get_script() as Script
	return script.resource_path if script != null else ""


func _aggregate(records: Array[Dictionary], field: String) -> Array[Dictionary]:
	var buckets := {}
	for record in records:
		var key := str(record.get(field, "unknown"))
		if not buckets.has(key):
			buckets[key] = {
				"key": key, "count": 0, "pixels": 0, "pixel_samples": 0,
				"dormant": 0, "sleeping": 0, "own_world_3d": 0,
				"mesh_instances": 0, "lights": 0,
			}
		var bucket: Dictionary = buckets[key]
		bucket.count += 1
		bucket.pixels += int(record.pixels)
		bucket.pixel_samples += int(record.pixel_samples)
		bucket.dormant += 1 if bool(record.dormant) else 0
		bucket.sleeping += 1 if record.population_state == "sleeping" else 0
		bucket.own_world_3d += 1 if bool(record.own_world_3d) else 0
		bucket.mesh_instances += int(record.mesh_instances)
		bucket.lights += int(record.lights)
	var result: Array[Dictionary] = []
	for bucket in buckets.values():
		result.append(bucket)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.pixel_samples) > int(b.pixel_samples))
	return result


func _sum(records: Array[Dictionary], field: String) -> int:
	var total := 0
	for record in records:
		total += int(record.get(field, 0))
	return total


func _msaa_samples(msaa: Viewport.MSAA) -> int:
	match msaa:
		Viewport.MSAA_2X: return 2
		Viewport.MSAA_4X: return 4
		Viewport.MSAA_8X: return 8
		_: return 1


func _mode_name(mode: SubViewport.UpdateMode) -> String:
	match mode:
		SubViewport.UPDATE_DISABLED: return "disabled"
		SubViewport.UPDATE_ONCE: return "once"
		SubViewport.UPDATE_WHEN_VISIBLE: return "when_visible"
		SubViewport.UPDATE_WHEN_PARENT_VISIBLE: return "when_parent_visible"
		SubViewport.UPDATE_ALWAYS: return "always"
		_: return "unknown_%d" % int(mode)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish(world: Node, report: Dictionary) -> void:
	if is_instance_valid(world):
		world.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() and not report.is_empty() else 1)
