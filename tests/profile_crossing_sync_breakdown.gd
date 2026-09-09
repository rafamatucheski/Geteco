extends SceneTree

## Diagnostic only: breaks JunctionTrafficController._synchronize_crossing_consumers()
## down into its three real cost centers — group lookups, the per-crossing
## read-only resolution (junction_id/road_index/crossing_id + junction
## lookup), and the actual crossing.call("set_signal_state", ...) side
## effect — by calling the exact same production methods/paths in isolation,
## the same way profile_junction_controller_functions.gd already times the
## whole function. Does not change any behavior.

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 90: await process_frame
	var controller = world.get_node("Life/JunctionTrafficController")

	var n := 30

	# Step 1: just the three get_nodes_in_group lookups + dedupe walk (no per-crossing work).
	var unique_count := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		var seen: Dictionary = {}
		unique_count = 0
		for group_name in [&"road_crossing_area", &"road_crossing", &"traffic_crossing"]:
			for crossing in get_nodes_in_group(group_name):
				if seen.has(crossing.get_instance_id()):
					continue
				seen[crossing.get_instance_id()] = true
				unique_count += 1
	var t_lookup := (Time.get_ticks_usec() - t0) / float(n)
	print("GROUP_LOOKUP_ONLY road_crossing_area=%d road_crossing=%d traffic_crossing=%d unique=%d" % [
		get_nodes_in_group(&"road_crossing_area").size(), get_nodes_in_group(&"road_crossing").size(),
		get_nodes_in_group(&"traffic_crossing").size(), unique_count,
	])

	# Step 2: lookups + read-only per-crossing resolution (properties, get_meta,
	# _resolve_junction_index, is_junction_signalized) but no set_signal_state call.
	t0 = Time.get_ticks_usec()
	for i in n:
		var seen: Dictionary = {}
		for group_name in [&"road_crossing_area", &"road_crossing", &"traffic_crossing"]:
			for crossing in get_nodes_in_group(group_name):
				if seen.has(crossing.get_instance_id()):
					continue
				seen[crossing.get_instance_id()] = true
				if not crossing.has_method("set_signal_state"):
					continue
				var junction_id: StringName
				var road_index: int
				if "junction_id" in crossing and "road_index" in crossing:
					junction_id = StringName(crossing.junction_id)
					road_index = int(crossing.road_index)
				else:
					continue
				var junction_index := int(crossing.get_meta("junction_index", -1))
				if junction_id.is_empty() and junction_index < 0:
					continue
				var junction_ref: Variant = junction_index if junction_index >= 0 else junction_id
				var resolved_index: int = controller._resolve_junction_index(junction_ref)
				if resolved_index < 0 or not controller.is_junction_signalized(resolved_index):
					continue
				if road_index < 0:
					continue
	var t_readonly := (Time.get_ticks_usec() - t0) / float(n)

	# Step 3: the real, unmodified function (lookups + resolution + the actual
	# crossing.call("set_signal_state", ...) side effect).
	t0 = Time.get_ticks_usec()
	for i in n: controller._synchronize_crossing_consumers()
	var t_full := (Time.get_ticks_usec() - t0) / float(n)

	print("CROSSING_SYNC_BREAKDOWN group_lookup_us=%.1f read_only_resolution_us=%.1f full_with_set_signal_state_us=%.1f attributable_to_set_signal_state_us=%.1f" % [
		t_lookup, t_readonly, t_full, t_full - t_readonly,
	])
	world.queue_free()
	await process_frame
	quit()
