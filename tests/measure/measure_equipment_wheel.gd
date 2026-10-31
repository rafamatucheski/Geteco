extends "res://tests/measure/measure.gd"
## Rendered real session, normal population, identical inventory and slow-motion baseline.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
const SOURCE_PATHS := ["scripts/CameraRig.gd", "scripts/camera/BuildingCameraClearance.gd", "gameplay/Gameplay.gd", "scripts/Vehicle.gd", "gameplay/vehicle_effects/VehicleGlassDamage.gd", "gameplay/vehicle_effects/VehicleDamage.gd", "gameplay/vehicle_effects/VehicleRain.gd", "gameplay/vehicle_effects/VehicleWindshieldRain.gd", "gameplay/vehicle_effects/VehicleWindshieldRain.gdshader", "gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd", "runtime/FamilyVariantPrewarm.gd", "runtime/FormatPrewarm.gd", "runtime/PipelineProbe.gd", "runtime/Weather.gd", "runtime/FullSession.gd", "runtime/EquipmentWheel.gd", "ui/hud/EquipmentWheelView.gd", "tests/measure/measure_equipment_wheel.gd"]
var provenance := {}

func source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCE_PATHS:
		result[path] = FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "missing"
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Requires rendered Godot .NET and --no-save")
		quit(2)
		return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	provenance["before_load"] = source_hashes()
	seed(26102026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	if not await STARTUP.wait_for_startup(world):
		push_error("Gameplay startup did not finish")
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
	var economy = world.session.state.economy
	economy.grid_equip_bag("backpack")
	economy.grant_weapon("pistol")
	economy.grant_weapon("hunting_rifle")
	economy.grant_item("apple",3)
	economy.grant_item("water",2)
	economy.add_ammo("pistol",126)
	var wheel_script: Script = world.session.equipment_wheel.get_script()
	var cursor_mode := Input.mouse_mode
	for phase: String in (["before-ab", "after"] if variant == "paired" else [variant]):
		# Mantém o mesmo grafo de recursos carregado, incluindo edições concorrentes da câmera.
		# Só o componente novo de UI/runtime muda entre A e B.
		Engine.time_scale = 1.0
		world.player.input_locked = false
		Input.mouse_mode = cursor_mode
		if phase.begins_with("before") and is_instance_valid(world.session.equipment_wheel):
			world.session.equipment_wheel.free()
			world.session.equipment_wheel = null
		elif not is_instance_valid(world.session.equipment_wheel):
			world.session.equipment_wheel = wheel_script.new()
			world.add_child(world.session.equipment_wheel)
			world.session.equipment_wheel.configure(world.session)
		provenance[phase+"_start"] = source_hashes()
		if not await measure_phase(phase):
			world.free()
			quit(4)
			return
		provenance[phase+"_end"] = source_hashes()
		if is_instance_valid(world.session.equipment_wheel): world.session.equipment_wheel.close(false)
	Engine.time_scale = 1.0
	provenance["after_measurement"] = source_hashes()
	FileAccess.open("res://artifacts/equipment-wheel-20261026/"+variant+"-provenance.json",FileAccess.WRITE).store_string(JSON.stringify(provenance,"\t"))
	world.free()
	quit()

func measure_phase(variant: String) -> bool:
	var folder := "res://artifacts/equipment-wheel-20261026/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	print("WHEEL_BENCH_LOADED ",variant)
	for scenario in ["closed","weapons","consumables"]:
		var opening_start := Time.get_ticks_usec()
		var wheel: Variant = world.session.get("equipment_wheel")
		if scenario != "closed":
			if variant.begins_with("before"):
				world.player.input_locked = true
				Engine.time_scale = .2
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				if wheel == null or (not wheel.active and not wheel.open()):
					push_error("Equipment wheel did not open")
					return false
				if scenario == "consumables": wheel.toggle_page()
		var opening_call_ms := float(Time.get_ticks_usec()-opening_start)/1000.0
		await process_frame
		var opening_frame_ms := float(Time.get_ticks_usec()-opening_start)/1000.0
		var warm: Array[float] = []
		var frames: Array[float] = []
		var cpu_samples: Array[float] = []
		var physics_samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		var total := 0.0
		while total < 30000:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now-last)/1000.0
			if now-start < 8000000: warm.append(ms)
			else:
				frames.append(ms)
				total += ms
				cpu_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
				physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			last = now
		if not variant.begins_with("before") and scenario != "closed" and not wheel.active:
			push_error("Wheel was interrupted during measurement; sample invalid")
			return false
		var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"time_scale":Engine.time_scale,"population":world.people.size(),"traffic_children":world.traffic.get_child_count(),"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"cpu_ms":cpu_samples,"physics_ms":physics_samples,"baseline_method":"A/B same final code; before removes the equipment wheel component after startup; slow baseline uses matching .2 time scale and player lock.","scope":"Harbor stationary rendered Main; normal directors; fixed clear daytime; 8s warmup + 30s per scenario; no personal save; 60 FPS target, >5% p95/p99 requires finite confirmation."}
		report["opening_call_ms"] = opening_call_ms
		report["opening_first_frame_ms"] = opening_frame_ms
		report["paired_process_note"] = "Six phases share the same loaded scripts and fixed camera/weather. Traffic/NPC simulation continues and positions evolve between baseline and enabled phases; this is a component A/B, not a pre-edit build benchmark."
		FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
		print("WHEEL_BENCH ",variant," ",scenario," ",JSON.stringify(report.summary))
	return true
