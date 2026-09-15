extends SceneTree
var samples: Array[float] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/map-gps/saves/"
	seed(913)
	create_timer(180).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await create_timer(20).timeout
	var map: Node = current_scene.get_node("Minimap")
	if "gps" in OS.get_cmdline_user_args(): map.set_waypoint(Vector2(2200,1050))
	if "open" in OS.get_cmdline_user_args(): map.full_map.open_map()
	var label := "baseline" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	await measure(label)
	if label == "gps":
		map.full_map.open_map()
		await create_timer(2).timeout
		await measure("open")
	quit()

func measure(label: String) -> void:
	samples.clear()
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
	var total := (previous-start)/1000000.0
	var raw := samples.duplicate()
	samples.sort()
	var slow := 0
	var very_slow := 0
	for ms in samples:
		if ms > 33.3: slow += 1
		if ms > 66.7: very_slow += 1
	var result := {"fps":samples.size()/total,"seconds":total,"frames":samples.size(),"p50":samples[int(samples.size()*0.5)],"p95":samples[int(samples.size()*0.95)],"p99":samples[int(samples.size()*0.99)],"max":samples.back(),"over33":slow,"over66":very_slow,"gpu":RenderingServer.get_video_adapter_name(),"samples":raw}
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/map-gps")
	FileAccess.open("D:/geteco/artifacts/map-gps/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(result))
	result.erase("samples")
	print(result)
