extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.get_node("SaveManager").set("_save_dir","D:/geteco/artifacts/south-port-test-saves/")
	root.get_node("SaveManager").set("_save_directory_ready",false)
	root.get_node("SettingsManager").set("_settings_path","D:/geteco/artifacts/south-port-test-settings.cfg")
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 90: await process_frame
	var world := current_scene
	var ok: bool = world != null and world.get("gameplay_ready") == true and world.has_node("SouthPort") and world.has_node("Minimap")
	if ok:
		world.get_node("Player").position = Vector2(3570,3300)
		world.get_node("Minimap").refresh()
		var roads: Array = world.get_node("Minimap")._roads
		ok = roads.any(func(road: Dictionary): return (road.points as PackedVector2Array).has(Vector2(5750,5650)))
		world.get_node("SouthPort")._process(.3)
		ok = ok and world.get_node("SouthPort").active
	print("SOUTH_PORT_PRODUCTION gameplay, minimap, activation: ","PASS" if ok else "FAIL")
	world.queue_free()
	await process_frame
	quit(0 if ok else 1)
