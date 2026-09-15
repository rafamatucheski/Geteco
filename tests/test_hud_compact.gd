extends SceneTree
const OUT = "D:/geteco/artifacts/hud-adjust-0913"
var failed := false
func _initialize(): run.call_deferred()
func check(ok, message):
	print("PASS " if ok else "FAIL ", message)
	failed = failed or not ok
func frames(n):
	for i in n: await process_frame
func run():
	create_timer(180).timeout.connect(func(): quit(2))
	root.get_node("SaveManager").set("_save_dir", OUT + "/saves/")
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	await frames(60)
	var player = world.get_node("Player")
	player.global_position = Vector2(1100,1700)
	player.set_physics_process(false)
	var hud = world.get_node("HUD")
	hud.set_money(3200)
	hud.set_weapon_info("pistol", {"clip":0,"reserve":0})
	var arrival = world.get_node("ArrivalMission")
	paused = false
	player.is_in_dialogue = false
	player.is_control_disabled = false
	arrival.set_process(false)
	world.get_node("CobraCampaign").set_process(false)
	arrival._refresh_objective()
	var stage = "before" if "--before" in OS.get_cmdline_user_args() else "after"
	if stage == "after":
		player.personal_loadout_enabled = false
		var shots := [0]
		player.weapon_fired.connect(func(): shots[0] += 1)
		for id in ["pistol", "smg", "shotgun", "grenade", "flamethrower", "rpg"]:
			player.weapon_inventory[id] = true
			player.weapon_ammo[id] = {"clip":0,"reserve":0}
			player.equip_weapon(id)
			var notice_before: String = player.weapon_wheel.notice
			var deadline_before: float = player.weapon_wheel.notice_until
			for attempt in 30:
				player._shoot_towards(player.global_position + Vector2(100,0))
			check(player.weapon_wheel.notice == notice_before and player.weapon_wheel.notice_until == deadline_before, id+" repeated empty fire emits no notice")
			check(hud.ammo_label.visible and hud.ammo_label.text == "0-0", id+" empty counter survives switching")
		check(shots[0] == 0, "Empty weapons emit no shots")
		player.weapon_ammo.pistol = {"clip":2,"reserve":0}
		player.equip_weapon("pistol")
		player._shoot_towards(player.global_position + Vector2(100,0))
		check(shots[0] == 1 and player.weapon_ammo.pistol.clip == 1 and hud.ammo_label.text == "1-0", "Loaded weapon fires and updates HUD")
		player.equip_weapon("fists")
		check(not hud.ammo_label.visible, "Melee hides ammo")
		player.equip_weapon("pistol")
		arrival.phase = "police_visit"
		arrival.target = player.global_position + Vector2(1660,0)
		arrival._refresh_objective()
		check(arrival._objective_label.text.ends_with("100 m") and not arrival._objective_label.text.contains(" / "), "Distance has units without ambiguous compass letter")
		player.global_position.x += 166
		arrival._refresh_objective()
		check(arrival._objective_label.text.ends_with("90 m"), "Moving updates distance")
		hud.show_notice("Mensagem de teste nas bordas da janela.")
		hud.show_vehicle_name("Monaliza")
		player.weapon_wheel.show_notice("Mensagem funcional preservada")
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768),Vector2i(2560,1080),Vector2i(800,600)]:
		root.size = resolution
		hud.set_stars(6)
		hud.set_armor(70,100)
		hud.show_notice("Mensagem de teste nas bordas da janela.")
		hud.show_vehicle_name("Monaliza")
		await frames(12)
		player.weapon_wheel.show_notice("Mensagem funcional preservada")
		await process_frame
		print("NOTICE paused=",paused," processing=",player.weapon_wheel.is_processing()," can_process=",player.weapon_wheel.can_process()," remaining=",player.weapon_wheel.notice_until-Time.get_ticks_msec()/1000.0)
		print("WINDOW requested=",resolution," actual=",root.size," viewport=",root.get_visible_rect())
		check(not arrival._obj_card.get_global_rect().intersects(hud.get_node("RootMargin/TopRightPanel").get_global_rect()), "Objective clears wanted stars and armor")
		check(player.weapon_wheel._notice_panel.visible, "Other functional notices still appear")
		for control in [hud.get_node("RootMargin/TopRightPanel"),world.get_node("Minimap").panel,arrival._obj_card,hud.notice_label,hud.vehicle_name_label,player.weapon_wheel._notice_panel]:
			if not is_instance_valid(control): continue
			check(root.get_visible_rect().encloses(control.get_global_rect()), str(resolution)+" bounds "+str(control.get_global_rect()))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"/"+stage+"-%d.png"%resolution.x)
	root.size = Vector2i(1280,720)
	for hour in [0.5,0.0]:
		world.weather.is_dynamic_time = false
		world.weather.time_of_day = hour
		await frames(20)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"/contrast-%s.png"%str(hour))
	if not "--measure" in OS.get_cmdline_user_args():
		print("HUD_COMPACT failures=",failed)
		quit(1 if failed else 0)
		return
	await frames(60)
	var samples: Array[float] = []
	var start = Time.get_ticks_usec()
	var previous = start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now = Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
	var total = (previous-start)/1000000.0
	samples.sort()
	print("METRICS ",stage," FPS=",samples.size()/total," p50=",samples[int(samples.size()*.5)]," p95=",samples[int(samples.size()*.95)]," p99=",samples[int(samples.size()*.99)]," max=",samples[-1]," >33=",samples.filter(func(x): return x>33.3).size()," >66=",samples.filter(func(x): return x>66.7).size())
	quit(1 if failed else 0)
