extends "res://tests/measure/measure.gd"
## Integrated comparison, separate from capture overhead; no personal saves.
var out := "res://artifacts/flashlight-fix-20261017"
var review_label := "before"

func _process(_delta: float) -> bool: return false

func shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(review_label + "-" + tag + ".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): review_label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 1000000
	world.gameplay.state.economy.cheat_infinite_money = true
	world.gameplay.state.grant_weapon("pistol")
	world.gameplay.buy_attachment("pistol","flashlight")
	world.gameplay.belt_flashlight.purchase()
	var reports := []
	for site in ["harbor_sewer","sewer_market"]:
		var definition := preload("res://world/places/PlaceCatalog.gd").get_definition(site)
		world.session.controller.region.set_focus(definition.entry_position)
		world.player.teleport(definition.entry_position+Vector3(-1.2,.08,1.0))
		for i in 60: await physics_frame
		var hatch: Node3D = world.session._find_sewer_hatch(site)
		if is_instance_valid(hatch): world.player.teleport(hatch.to_global(Vector3(0,.08,1.1)))
		for i in 3: await physics_frame
		if not await world.session.enter_place(site,false): push_error("entry failed " + site); quit(4); return
		world.gameplay.state.equip_weapon("fists")
		world.gameplay.flashlight_enabled = false
		world.gameplay.belt_flashlight.enabled = true
		for i in 12: await physics_frame
		await shot(site + "-belt")
		if review_label == "before":
			var casters := {}
			for mesh in world.player.visual.find_children("*","GeometryInstance3D",true,false):
				casters[mesh] = mesh.cast_shadow
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for i in 3: await process_frame
			await shot(site + "-diagnostic-no-body-shadow")
			for mesh in casters: mesh.cast_shadow = casters[mesh]
		world.gameplay.state.equip_weapon("pistol")
		world.gameplay.flashlight_enabled = true
		for i in 12: await physics_frame
		await shot(site + "-both")
		var warm_until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < warm_until: await process_frame
		var intervals: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec() - start < 30000000:
			root.get_node("GameInput").touch_aim = Vector2.from_angle(float(Time.get_ticks_usec()-start)*0.00000025)
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append((now-last)/1000.0)
			last = now
		reports.append({"site":site,"summary":stats(intervals),"intervals_ms":intervals})
		print("PERSONAL_LIGHTS ",site," ",JSON.stringify(stats(intervals)))
		if not await world.session.leave_place(): quit(5); return
		for i in 12: await physics_frame
	var report := {"label":review_label,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"reports":reports}
	FileAccess.open(out.path_join(review_label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	world.queue_free()
	await process_frame
	quit()
