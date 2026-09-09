extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 30: await process_frame
	var adapter: Node = current_scene.get_node("GameplayTutorials")
	var hints: Node = adapter.presenter
	var player: Node = current_scene.get_node("Player")
	player.set_physics_process(false)
	adapter.request_context("first_trunk")
	check(not hints.is_showing(),"unfinished trunk feature never advertised")
	adapter.request_context("rare_item")
	check(hints.get_active_hint_id()=="rare_item","real game adapter displays supported hint")
	player.is_in_dialogue = true
	adapter._refresh_context()
	check(not hints._box.visible and hints._timer.paused,"active hint hides and timer pauses during dialogue")
	player.is_in_dialogue = false
	player.fire_cooldown = 0.5
	adapter._refresh_context()
	check(not hints._box.visible,"firing keeps active hint hidden")
	player.fire_cooldown = 0
	adapter.combat_cooldown = 0
	adapter._refresh_context()
	check(hints._box.visible and not hints._timer.paused,"same hint resumes after danger")
	paused = true
	adapter._refresh_context()
	check(not hints._box.visible,"pause menu suppresses hint")
	paused = false
	adapter._refresh_context()
	hints.dismiss_hint()
	adapter.request_context("rare_item")
	check(not hints.is_showing(),"integration keeps session deduplication")
	player.set_meta("police_exterior_position",Vector2(100,100))
	root.get_node("WantedManager").current_stars = 1
	adapter._refresh_context()
	check(hints.get_active_hint_id()=="police_search","wanted player shelter triggers exterior search hint")
	player.remove_meta("police_exterior_position")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/tutorial-gameplay-review.png")
	root.get_node("WantedManager").reset_crime()
	hints.reset_preview()
	var stream: Node = current_scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	player.global_position = stream.mountain.to_global(Vector2(5980,530))
	stream._update_region()
	adapter._refresh_context()
	check(hints.get_active_hint_id()=="thermal_shop","real mountain shop proximity triggers thermal hint")
	hints.dismiss_hint()
	stream.mountain.cold_controller.current_temperature = 55
	stream.mountain.cold_controller.sheltered = false
	adapter._refresh_context()
	check(hints.get_active_hint_id()=="cold_shelter","real temperature triggers cold hint")
	hints.dismiss_hint()
	stream.mountain.get_node("MountainExpedition")._notice("tunnel","legacy text")
	check(hints.get_active_hint_id()=="tunnel","expedition routes its hint into shared presenter")
	print("GAMEPLAY TUTORIALS FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)
