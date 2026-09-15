extends SceneTree
## Production HUD + real delivery completion, isolated from user save slots.
var failures: Array[String] = []
const OUT := "D:/geteco/artifacts/sa-hud-0913/v2"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func close_dialog(bridge: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while bridge._dialog.visible and Time.get_ticks_msec() < deadline:
		bridge._next_message()
		await process_frame
	check(not bridge._dialog.visible, "Narrative dialogue closes normally")

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUT.path_join("test-saves"))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", OUT.path_join("test-saves") + "/")
	saves.clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_started", "harbor_delivery_picked_up"]:
		campaign.set_campaign_flag(StringName(flag), true)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	await frames(20)
	var player = world.get_node("Player")
	var hud = world.get_node("HUD")
	var arrival = world.get_node("ArrivalMission")
	var bridge = world.get_node("CobraCampaign")
	var map = world.get_node("Minimap")
	player.global_position = Vector2(1100, 1700)
	player.velocity = Vector2.ZERO
	arrival._refresh_objective()
	map.refresh()
	check(not arrival._obj_card.visible and not bridge._objective_card.visible, "No persistent mission description")
	check(map.objective_target != Vector2.ZERO, "Active mission remains marked on minimap")
	check(map.canvas.size.x == map.canvas.size.y, "Minimap is square")
	check(not is_instance_valid(hud.mission_passed_banner), "Loading an active save never celebrates a completion")
	hud.set_money(350)
	hud.set_weapon_info("pistol", {"clip": 12, "reserve": 60})
	hud.set_armor(70, 100)
	hud.show_achievement("GRANA SUJA", "Acumule $2.000 no bolso.")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		root.content_scale_size = resolution
		await frames(5)
		check(hud.health_bar.get_global_rect().position.x > resolution.x * .7, "Vitals on the right at " + str(resolution))
		check(not hud.weapon_row.get_global_rect().intersects(hud.health_bar.get_global_rect()), "Weapon clears health bar")
		check(root.get_visible_rect().encloses(hud.money_label.get_global_rect()), "Money fits viewport")
		check(hud.ammo_label.text == "12-60", "Ammo shows clip and reserve")
		check(is_equal_approx(hud.achievement_panel.get_global_rect().get_center().x, resolution.x * .5), "Achievement centered horizontally")
		check(hud.achievement_panel.get_global_rect().position.y == 28.0, "Achievement at top of screen")
		check(not hud.achievement_panel.get_global_rect().intersects(hud.get_node("RootMargin/TopRightPanel").get_global_rect()), "Achievement clears status indicators")
		check(not bridge._journal_button.visible, "No diary button on HUD")
		await shot("gameplay-%d" % resolution.x)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	# Exercise the real delivery proximity gate and one-time payment.
	player.global_position = arrival.garage.jager_npc.global_position + Vector2(0, 30)
	player.velocity = Vector2.ZERO
	var money_before: int = player.money
	check(arrival.interact_with_objective(), "Real delivery completes at Maciota")
	check(player.money == money_before + arrival.REWARD, "Reward actually paid once")
	check(hud.mission_passed_title.text == "MISSÃO CUMPRIDA!", "Portuguese victory title")
	check(hud.mission_passed_reward.text == "+$%d" % arrival.REWARD, "Banner matches actual reward")
	var tween = hud._mission_passed_tween
	arrival.interact_with_objective()
	check(player.money == money_before + arrival.REWARD and hud._mission_passed_tween == tween, "Repeat interaction neither pays nor replays banner")
	await create_timer(.3).timeout
	check(hud.mission_passed_banner.modulate.a > .99, "Celebration animates during the completion dialogue pause")
	check(not hud.mission_passed_banner.get_global_rect().intersects(bridge._dialog.get_global_rect()), "Victory clears narrative dialogue")
	await shot("delivery-passed")
	await close_dialog(bridge)
	# Failure must never become a victory. Run a real campaign transition.
	var runtime = bridge.runtime
	check(runtime.start_mission("cobra_contact"), "Next authored campaign mission starts")
	await close_dialog(bridge)
	runtime.fail_mission("test")
	check(hud._mission_passed_tween == tween, "Mission failure does not celebrate")
	await close_dialog(bridge)
	check(runtime.start_mission("cobra_contact"), "Failed mission can restart")
	await close_dialog(bridge)
	var before_campaign: int = player.money
	runtime._finish()
	check(player.money == before_campaign + 120 and hud.mission_passed_reward.text == "+$120", "Campaign completion announces its actual payment")
	runtime._finish()
	check(player.money == before_campaign + 120, "Duplicate completion is idempotent")
	await close_dialog(bridge)
	player.global_position = Vector2(1100, 1700)
	await create_timer(.2).timeout
	check(not bridge._journal_button.visible, "Diary button stays hidden after dialogue and mission transitions")
	var camera := root.get_camera_2d()
	if camera:
		camera.global_position = player.global_position
		camera.reset_smoothing()
	TranslationServer.set_locale("en")
	hud.show_mission_passed(600, 1)
	await create_timer(.3).timeout
	check(hud.mission_passed_title.text == "MISSION PASSED!" and hud.mission_passed_reward.text == "+$600  ·  RESPECT +1", "English title and explicit respect reward")
	await shot("mission-passed-en")
	TranslationServer.set_locale("pt_BR")
	hud.show_mission_passed(120)
	await create_timer(.3).timeout
	await shot("mission-passed-pt")
	await create_timer(5.8).timeout
	check(not hud.mission_passed_banner.visible, "Celebration expires without input")
	print("CLASSIC_MISSION_HUD failures=", failures)
	quit(0 if failures.is_empty() else 1)
