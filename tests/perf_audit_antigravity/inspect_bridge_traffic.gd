extends SceneTree

const HARBOR_SCENE := "res://world/harbor/HarborGame.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))

	var campaign: Node = root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)

	change_scene_to_file(HARBOR_SCENE)
	var harbor: Node2D = null
	for i in 60:
		await process_frame
		harbor = current_scene as Node2D
		if harbor != null and harbor.name == "HarborGame":
			break

	print("=== INSPECIONANDO VEICULOS MODERN_TRAFFIC NO HARBOR ===")
	var stream = harbor.get_node("ContinuousWorld")
	# Ensure mountain streaming started
	stream.ensure_mountain()
	while not stream.ready_for_crossing:
		await process_frame

	print("Ready for crossing! Inspecionando veiculos na ponte...")
	for v in get_nodes_in_group("modern_traffic"):
		var p := v.get_parent()
		var road_id = v.get_meta("traffic_road_id", "")
		if String(road_id).contains("bridge") or v.global_position.distance_to(Vector2(6400, -4300)) < 600.0:
			print("VEICULO: %s pos=%s parent=%s loop=%s speed=%.1f lane_speed=%.1f prog=%.1f" % [
				v.name, str(v.global_position), p.name if p else "null",
				str(p.get("loop") if p else false),
				float(v.get("speed")), float(v.get("_lane_motion_speed")),
				float(p.get("progress") if p else 0.0)
			])
			if v.has_method("_get_lane_obstruction") and p is PathFollow2D:
				var obs: Dictionary = v.call("_get_lane_obstruction", p)
				print("  OBSTRUCTION: %s" % str(obs))
			if p is PathFollow2D:
				var path = p.get_parent()
				print("  PATH: %s len=%.1f curve_pts=%d" % [
					path.name, path.curve.get_baked_length() if path.curve else 0.0,
					path.curve.point_count if path.curve else 0
				])

	quit(0)
