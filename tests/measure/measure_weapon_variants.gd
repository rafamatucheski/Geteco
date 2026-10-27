extends "res://tests/measure/measure.gd"
## Fixed rendered Main scenario. Never use personal saves or headless for this measurement.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
var variant := "before"
const SOURCES := ["gameplay/Gameplay.gd","gameplay/WeaponCatalog.gd","gameplay/CombatAudio.gd","gameplay/CombatEffects.gd","gameplay/WeaponVariantModels.gd","runtime/EquipmentWheel.gd","ui/hud/EquipmentWheelView.gd","runtime/ProductionWorld.gd","runtime/TrafficFleetRoster.gd","scripts/Vehicle.gd","gameplay/desert_cars/StreetPowertrainCatalog.gd"]
var provenance := {}

func source_hashes() -> Dictionary:
	var values := {}
	for path: String in SOURCES: values[path]=FileAccess.get_sha256("res://"+path)
	return values

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(27102026)
	provenance["before_load"]=source_hashes()
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	if not await STARTUP.wait_for_startup(world):
		push_error("Weapon benchmark startup failed")
		quit(3)
		return
	world.player.teleport(Vector3(132,.15,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(world.player.global_position)
	world.camera.target_size = 38
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.state.economy.activate_arsenal_cheat()
	world.gameplay.toggle_god_mode()
	provenance["loaded"]=source_hashes()
	print("VARIANT_BENCH_LOADED ",variant)
	var folder := "res://artifacts/weapon-variants-20261027/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if "--capture-only" in OS.get_cmdline_user_args():
		await showcase(folder)
		world.free()
		quit()
		return
	var scenarios := ["idle","smg","shotgun"]
	if variant.begins_with("after"): scenarios.append_array(["pistol_suppressed","smg_compact","smg_tactical","shotgun_auto","wheel"])
	for scenario: String in scenarios:
		if scenario != "idle" and scenario != "wheel":
			if not world.gameplay.equip_slot(scenario):
				push_error("Benchmark cannot equip "+scenario)
				quit(4)
				return
		if scenario == "wheel" and not world.session.equipment_wheel.open():
			push_error("Benchmark cannot open equipment wheel")
			quit(4)
			return
		var warm: Array[float] = []
		var frames: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		var measured := 0.0
		var shots := 0
		var successful := 0
		while measured < 30000:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now-last)/1000.0
			last = now
			if now-start < 8000000: warm.append(ms)
			else:
				frames.append(ms)
				measured += ms
			if scenario != "idle" and scenario != "wheel" and world.gameplay.cooldown <= 0.0:
				if world.gameplay.fire_at(world.player.global_position+Vector3.RIGHT*16): successful += 1
				shots += 1
			if scenario == "wheel" and frames.size()%40 == 0: world.session.equipment_wheel.cycle_variant(1)
		var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"shots_attempted":shots,"population":world.people.size(),"traffic":world.traffic.get_child_count(),"scope":"Main rendered; normal directors; fixed daytime/camera; 8s warmup + 30s sample. Direct fire_at diagnostic with arsenal cheat. 60 FPS target; >5% p95/p99 requires finite confirmation."}
		report["shots_successful"] = successful
		report["health"] = world.gameplay.health
		report["player_position"] = str(world.player.global_position)
		report["invulnerability_fixture"] = true
		report["equipped"] = world.session.state.equipped_weapon
		report["valid_fire_sample"] = shots==0 or successful>0
		FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
		print("VARIANT_BENCH ",variant," ",scenario," ",JSON.stringify(report.summary))
		print("VARIANT_SHOTS ",scenario," attempts=",shots," success=",successful," health=",world.gameplay.health)
		if shots>0 and successful==0:
			push_error("No successful shots in "+scenario)
			quit(5)
			return
		if scenario == "wheel": world.session.equipment_wheel.close(false)
	if "--capture" in OS.get_cmdline_user_args(): await showcase(folder)
	provenance["finished"]=source_hashes()
	FileAccess.open(folder+"/provenance.json",FileAccess.WRITE).store_string(JSON.stringify(provenance,"\t"))
	world.free()
	quit()

func showcase(folder: String) -> void:
	# Presentation-only recording follows timing samples, so GPU readback does not affect them.
	TranslationServer.set_locale("pt_BR")
	world.gameplay.clear_wanted()
	world.player.teleport(world.production.nearest_road(world.driving.car.global_position+Vector3(0,0,14))+Vector3.UP*.1)
	world.session.weather.time_of_day=.93
	world.session.weather._update()
	world.camera.target_size = 14
	world.camera.size = 14
	var controls = root.get_node("GameInput")
	controls.using_gamepad = true
	var facing := Vector3.RIGHT
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y=0; down.y=0
	controls.touch_aim=Vector2(facing.dot(right.normalized()),facing.dot(down.normalized()))
	Input.action_press("aim")
	var sequence := folder+"/sequence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sequence))
	var stamps: Array = []
	var ids := ["pistol_suppressed","smg_compact","smg_tactical","shotgun_auto"]
	var active_index := -1
	var start := Time.get_ticks_usec()
	var frame_index := 0
	while "--stills-only" not in OS.get_cmdline_user_args() and Time.get_ticks_usec()-start < 30000000:
		var seconds := float(Time.get_ticks_usec()-start)/1000000.0
		var index := mini(3,int(seconds/7.5))
		if index != active_index:
			active_index=index
			world.gameplay.equip_slot(ids[index])
		if fmod(seconds,7.5)<5.0 and world.gameplay.cooldown<=0.0:
			world.gameplay.fire_at(world.player.global_position+facing*16)
		elif fmod(seconds,7.5)>=5.0 and world.gameplay.reload_timer<=0.0:
			world.gameplay.reload_weapon()
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.resize(960,540,Image.INTERPOLATE_BILINEAR)
		picture.save_jpg(sequence+"/frame_%05d.jpg"%frame_index,.85)
		stamps.append({"frame":frame_index,"usec":Time.get_ticks_usec()-start,"weapon":ids[index],"flash":world.gameplay._muzzle_timer,"light":is_instance_valid(world.gameplay._muzzle_light) and world.gameplay._muzzle_light.visible})
		if frame_index%60==0: root.get_texture().get_image().save_png(folder+"/held-"+ids[index]+".png")
		frame_index+=1
		await process_frame
	Input.action_release("aim")
	controls.touch_aim=Vector2.ZERO
	if not stamps.is_empty():
		FileAccess.open(sequence+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(stamps))
		print("VARIANT_TEMPORAL_CAPTURE frames=",frame_index," seconds=",float(Time.get_ticks_usec()-start)/1000000.0)
	# This isolated catalog fixture does not enter the shop, so hide the outdoor
	# HUD explicitly; the real storefront handles its modal state on entry.
	world.hud.visible = false
	var shop := preload("res://runtime/HarborAmmunationCatalog.gd").new()
	shop.configure(world.session)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(shop)
	shop.open_catalog()
	for id: String in ids:
		shop.selection = shop.stock.find(id)
		shop.change_selection(0)
		for tick in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/shop-"+id+".png")
	shop.dismiss()
	layer.free()
	world.hud.visible = true
	world.gameplay.clear_wanted()
	if world.session.equipment_wheel.open():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/wheel-pt.png")
		TranslationServer.set_locale("en")
		world.session.equipment_wheel._rebuild()
		assert(world.session.equipment_wheel.entries[0].slot_label=="FISTS")
		world.session.equipment_wheel.close(false)
