extends SceneTree
## CPU attribution only. Run in separate processes, cold and --prime-char.
## Uses a production-spawned vehicle with the real explosion signal connected.
const DAMAGE := preload("res://gameplay/vehicle_effects/VehicleDamage.gd")
var OUTPUT := "res://evidence/video-review-phase4-20260924/"
var world
var car: CharacterBody3D
var events: Array[Dictionary] = []
var failures: Array[String] = []
var explosions := 0
var signal_end := 0
var spawn_ms := 0.0
var prime_ms := 0.0
var primed := false
var capture_mode := false
var label_override := ""

func _initialize() -> void: run.call_deferred()

func frames(count: int) -> void:
	for frame in count: await physics_frame

func _after_explosion() -> void:
	signal_end = Time.get_ticks_usec()

func run() -> void:
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label_override = arg.trim_prefix("--label=")
		if arg.begins_with("--out="): OUTPUT = arg.trim_prefix("--out=").trim_suffix("/") + "/"
	var diagnostic := "--causal-headless" in OS.get_cmdline_user_args() and DisplayServer.get_name() == "headless"
	var capture_allowed := capture_mode and DisplayServer.get_name() != "headless"
	if not "--no-save" in OS.get_cmdline_user_args() or not (diagnostic or capture_allowed):
		push_error("Requires --no-save and either --headless --causal-headless or rendered --capture"); quit(2); return
	primed = "--prime-char" in OS.get_cmdline_user_args()
	seed(240924)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main ready"); await finish(); return
	world.gameplay.dispatch_owned = true
	world.gameplay.set_meta("trace_explosion", "--trace-stages" in OS.get_cmdline_user_args())
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(35, .05, 109))
	world.production.set_population(0)
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	await frames(120)
	var began := Time.get_ticks_usec()
	car = world.production.spawn_vehicle("sport_coupe", Vector3(26.7, .12, 109), 0)
	spawn_ms = float(Time.get_ticks_usec() - began) / 1000.0
	if not is_instance_valid(car):
		failures.append("Production vehicle admitted"); await finish(); return
	car.destroyed.connect(_after_explosion)
	world.gameplay.explosion_occurred.connect(func(_point: Vector3, _radius: float, _source): explosions += 1)
	await frames(120)
	# Diagnostic-only ablation preserves reproducibility after startup prewarm.
	if "--cold-char" in OS.get_cmdline_user_args():
		DAMAGE._char_albedo = null
		DAMAGE._char_embers = null
	if capture_mode:
		world.camera.set_process(false)
		world.camera.set_physics_process(false)
		world.camera.look_at_from_position(car.global_position + Vector3(10,7,12), car.global_position + Vector3.UP)
		world.camera.size = 18
	if primed:
		began = Time.get_ticks_usec()
		DAMAGE._char(false)
		DAMAGE._char(true)
		prime_ms = float(Time.get_ticks_usec() - began) / 1000.0
	var pose: Transform3D = car.global_transform
	for index in (1 if capture_mode else 3):
		if index > 0:
			world.gameplay.emergency.reset_region()
			car.repair()
			car.global_transform = pose
			car.velocity = Vector3.ZERO
			await frames(12)
		var cache_ready := DAMAGE._char_albedo != null and DAMAGE._char_embers != null
		car.damage_look._rng.seed = 127
		var expected := explosions + 1
		signal_end = 0
		began = Time.get_ticks_usec()
		car.receive_damage(car.max_health * 2.0)
		var ended := Time.get_ticks_usec()
		var record := {"blast":index+1,"char_cache_ready_before":cache_ready,"receive_damage_ms":float(ended-began)/1000.0,"explosion_signal_chain_ms":float(signal_end-began)/1000.0,"wreck_ms":float(ended-signal_end)/1000.0,"explosion_events":explosions,"ground_fires":world.gameplay.emergency.fires.size(),"cpu_process_ms":[],"cpu_physics_ms":[],"char_cache_ready_after":DAMAGE._char_albedo != null}
		if signal_end == 0 or explosions != expected or not car.damage_look.wrecked: failures.append("blast workload " + str(index+1))
		for frame in 240:
			await physics_frame
			record.cpu_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			record.cpu_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
			if capture_mode and frame in [30,239]:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT + label_override + "-f%03d.png" % frame)
		events.append(record)
		print("EXPLOSION_CPU blast=",index+1," total_ms=",record.receive_damage_ms," explosion_chain_ms=",record.explosion_signal_chain_ms," wreck_ms=",record.wreck_ms," actual_explosions=",explosions)
	await finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var label := "explosion-char-primed" if primed else "explosion-cold"
	if not label_override.is_empty(): label = label_override
	var file := FileAccess.open(OUTPUT + label + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write explosion evidence: " + OUTPUT)
		quit(2)
		return
	file.store_string(JSON.stringify({"label":label,"engine":Engine.get_version_info().string,"failures":failures,"spawn_vehicle_ms":spawn_ms,"char_prime_ms":prime_ms,"events":events,"capture_mode":capture_mode,"albedo":texture_identity(DAMAGE._char_albedo),"embers":texture_identity(DAMAGE._char_embers),"notes":"CPU attribution or functional captures; no FPS/GPU approval. Current Main with real production explosion, no-save/no-traffic/population0. User game remains active; timings are diagnostic, not isolated benchmark."}, "\t"))
	file.close()
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	print("EXPLOSION_CPU failures=",failures.size()," prime_ms=",prime_ms)
	quit(0 if failures.is_empty() else 1)

func texture_identity(texture: Texture2D) -> Dictionary:
	if texture == null: return {}
	var picture := texture.get_image()
	if picture == null or picture.is_empty(): return {"unavailable":true}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(picture.get_data())
	return {"width":picture.get_width(),"height":picture.get_height(),"mipmaps":picture.has_mipmaps(),"format":picture.get_format(),"sha256":hashing.finish().hex_encode()}
