extends SceneTree

## Diagnostic only: times the three sub-steps JunctionTrafficController runs
## every 0.5s (_refresh_lane_path_index, _refresh_signal_visuals,
## _synchronize_crossing_consumers) in isolation, to see which one actually
## dominates the periodic cost spike observed in the driving benchmark.
## Does not change any behavior.

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
	print("JUNCTIONS=%d LANES_INDEXED=%d" % [controller._states.size(), controller._lane_paths_by_id.size()])

	var n := 30
	var t0 := Time.get_ticks_usec()
	for i in n: controller._refresh_lane_path_index()
	var t_lane := (Time.get_ticks_usec() - t0) / float(n)

	t0 = Time.get_ticks_usec()
	for i in n: controller._refresh_signal_visuals()
	var t_visuals := (Time.get_ticks_usec() - t0) / float(n)

	t0 = Time.get_ticks_usec()
	for i in n: controller._synchronize_crossing_consumers()
	var t_crossing := (Time.get_ticks_usec() - t0) / float(n)

	t0 = Time.get_ticks_usec()
	for i in n:
		for index_value in controller._states.keys():
			var junction_index := int(index_value)
			controller._validate_reservation(junction_index)
			controller._advance_junction(junction_index, 1.0 / 60.0)
	var t_advance := (Time.get_ticks_usec() - t0) / float(n)

	print("SUBSTEP_COST refresh_lane_path_index_us=%.1f refresh_signal_visuals_us=%.1f synchronize_crossing_consumers_us=%.1f advance_all_junctions_us=%.1f" % [t_lane, t_visuals, t_crossing, t_advance])
	world.queue_free()
	await process_frame
	quit()
