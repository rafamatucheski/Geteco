extends SceneTree
## V1 real HarborGame; isolated temporary save directory.
var officers: Array = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	root.get_node("SaveManager")._save_dir = OS.get_temp_dir().path_join("police_reference_%d" % OS.get_process_id()) + "/"
	root.get_node("CampaignState").reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	root.get_node("SaveManager").clear_pending_save()
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready: await process_frame
	var player = current_scene.get_node("Player")
	player.set_physics_process(false)
	var center: Vector2 = player.global_position
	for i in 8:
		var officer = preload("res://police/PoliceOfficer.gd").new()
		officer.tier = i % 5
		officer.set_meta("response_tier_level", 2 + i % 5)
		officer.set_meta("quiet_patrol", true)
		current_scene.add_child(officer)
		officer.global_position = center + Vector2(sin(i * TAU / 8), cos(i * TAU / 8)) * 80
		officer.target = player
		officer.set_physics_process(false)
		officer.model_root.rotation.y = i * TAU / 8
		var rig = officer.get_node("NPCCombatRig")
		rig.aim_override = true
		officers.append(officer)
	for i in 120: await process_frame
	var output := "D:/geteco/game/geteco_v2/evidence/police-0922/v1-tiers"
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 40:
		if frame % 9 == 0:
			for officer in officers: officer._fire_single_bullet(player.global_position, 0, 880.0 if officer.tier < 2 else 1200.0, 0.13 if officer.tier < 2 else 0.10)
		await create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % frame))
	print("V1_POLICE_CAPTURE ", output)
	quit()
