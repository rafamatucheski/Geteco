extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 90: await process_frame
	var costs := {}
	for sample in 10:
		for car in get_nodes_in_group("modern_traffic"):
			var follow = car.get_parent()
			if not follow is PathFollow2D: continue
			var path = follow.get_parent()
			for method in ["_traffic_control_zone_motion", "_lane_spacing_motion", "_update_3d_orientation", "advance_on_lane", "_process"]:
				var start := Time.get_ticks_usec()
				if method == "_traffic_control_zone_motion": car.call(method, path, follow)
				elif method == "_lane_spacing_motion": car.call(method, follow)
				else: car.call(method, 1.0 / 60.0)
				costs[method] = costs.get(method, 0) + Time.get_ticks_usec() - start
	print("TRAFFIC SUBSTEP US (10 fleet passes): ", costs)
	quit()
