extends SceneTree
## Main.tscn renderizado, sistemas produtivos ativos. Cenário diagnóstico de combate:
## --no-save --skip-arrival --population=8 --seed=7 out_dir=res://evidence/takeshi/katana
## 30 s steel, 30 s saber/RAGE, depois 30 s sequência temporal contínua (separada das métricas).
var world
var gameplay
var state
var target: Node3D
var direction := Vector3.RIGHT
var output_dir := "res://evidence/takeshi/katana"
var checks := 0
var failures: Array[String] = []
var measurements := {}
var _spawned := 0
var _fire_down := false
var _next_swing := 0.0
var _damage_seen := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func ground(point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point - Vector3.UP * 4.0, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.get("position", point)

func aim() -> void:
	var controls: Node = root.get_node("GameInput")
	var right: Vector3 = world.camera.global_basis.x; right.y = 0.0
	var down: Vector3 = world.camera.global_basis.z; down.y = 0.0
	controls.touch_aim = Vector2(direction.dot(right.normalized()), direction.dot(down.normalized()))

func spawn_target() -> void:
	if is_instance_valid(target) and target.get("dead") != true: return
	if _spawned >= 12: return
	var actor := preload("res://scripts/Actor.gd").new()
	actor.identity = _spawned + 18
	world.add_child(actor)
	actor.global_position = ground(world.player.global_position + direction * 1.7)
	_spawned += 1
	target = actor

func swing_tick(elapsed: float) -> void:
	aim()
	if is_instance_valid(target) and float(target.get("health")) < 100.0: _damage_seen = true
	if _fire_down:
		Input.action_release("fire")
		_fire_down = false
	if elapsed >= _next_swing:
		spawn_target()
		Input.action_press("fire")
		_fire_down = true
		_next_swing = elapsed + 0.70

func summarize(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate(); sorted.sort()
	var total := 0.0; var over33 := 0; var over66 := 0
	for value in samples:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	return {"frames":samples.size(), "seconds":total/1000.0, "fps_mean":samples.size()/(total/1000.0),
		"p50_ms":sorted[int((sorted.size()-1)*.5)], "p95_ms":sorted[int((sorted.size()-1)*.95)], "p99_ms":sorted[int((sorted.size()-1)*.99)],
		"max_ms":sorted[-1], "over_33_3ms":over33, "over_66_7ms":over66, "samples_ms":samples}

func phase(label: String, use_rage := false) -> void:
	var warm_start := Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-warm_start)/1000000.0 < 8.0: await process_frame
	_spawned = 0
	var samples: Array[float] = []
	var start := Time.get_ticks_usec(); var last := start
	_next_swing = 0.0
	var activated_at := -1.0; var ended_at := -1.0
	var requested_at := -1.0
	var movement_start := Vector3.INF
	var moved := 0.0
	var camera_error := 0.0
	while float(Time.get_ticks_usec() - start) / 1000000.0 < 30.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - start) / 1000000.0
		samples.append(float(now-last)/1000.0); last = now
		swing_tick(elapsed)
		if use_rage and requested_at < 0.0 and elapsed >= 2.0:
			gameplay.rage.restore(100.0)
			print("RAGE input precondition ",gameplay.rage.status()," action=",InputMap.has_action("rage"))
			var event := InputEventKey.new(); event.keycode=KEY_V; event.physical_keycode=KEY_V; event.pressed=true
			Input.parse_input_event(event)
			requested_at = elapsed
		if requested_at >= 0.0 and activated_at < 0.0 and gameplay.rage.active:
			activated_at = elapsed
			check(true, "RAGE activation through production keyboard input")
			var release := InputEventKey.new(); release.keycode=KEY_V; release.physical_keycode=KEY_V; release.pressed=false
			Input.parse_input_event(release)
		if activated_at >= 0.0 and ended_at < 0.0 and not gameplay.rage.active:
			ended_at = elapsed
		if use_rage:
			var controls: Node = root.get_node("GameInput")
			# Afasta-se da entrada automática da garagem antes de voltar.
			# Os controles de toque podem limpar os eixos em mudanças de contexto. Aciona
			# as ações de teclado do desktop explicitamente em vez de depender de um analógico inativo.
			if elapsed >= 5.0 and elapsed < 6.0: Input.action_press("move_left")
			else: Input.action_release("move_left")
			if elapsed >= 6.0 and elapsed < 7.0: Input.action_press("move_right")
			else: Input.action_release("move_right")
			if elapsed >= 5.0 and elapsed < 6.0:
				if movement_start == Vector3.INF: movement_start = world.player.global_position
				moved = maxf(moved, world.player.global_position.distance_to(movement_start))
				camera_error = maxf(camera_error, world.camera.unproject_position(world.player.global_position).distance_to(world.get_viewport().get_visible_rect().size*.5))
	if use_rage:
		check(activated_at >= 0.0, "RAGE input activation observed in following frame")
		check(ended_at >= 0.0 and absf(ended_at-activated_at-15.0) < .35, "RAGE lasts fifteen wall-clock seconds (%.3f s)" % (ended_at-activated_at))
		check(is_equal_approx(Engine.time_scale,1.0), "time recovered after full active interval")
		check(moved > 0.5 and camera_error < world.get_viewport().get_visible_rect().size.y*.30, "production movement and camera remain responsive during RAGE (%.2fm, %.1fpx)" % [moved,camera_error])
		root.get_node("GameInput").touch_move = Vector2.ZERO
		Input.action_release("move_left")
		Input.action_release("move_right")
	Input.action_release("fire"); _fire_down=false
	measurements[label] = summarize(samples)
	var compact: Dictionary = measurements[label].duplicate(); compact.erase("samples_ms")
	print("MEASURE ", label, " ", compact)

func capture_sequence() -> void:
	var start := Time.get_ticks_usec(); var index := 0
	var stamps: Array[float] = []
	_next_swing = 0.0
	_spawned = 0
	gameplay.rage.restore(100); gameplay.rage.activate()
	while float(Time.get_ticks_usec()-start)/1000000.0 < 30.0:
		await process_frame
		var elapsed := float(Time.get_ticks_usec()-start)/1000000.0
		swing_tick(elapsed)
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.resize(640,360,Image.INTERPOLATE_BILINEAR)
		shot.save_jpg(output_dir.path_join("temporal_%05d.jpg" % index), .80)
		stamps.append(elapsed)
		index += 1
	Input.action_release("fire")
	var file := FileAccess.open(output_dir.path_join("temporal_timestamps.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(stamps))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output_dir=arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world=load("res://Main.tscn").instantiate(); root.add_child(world); current_scene=world
	for i in 1200:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	gameplay=world.gameplay; state=world.session.state
	await frames(30)
	state.grant_weapon("katana"); state.equip_weapon("katana")
	# Diagnostic protection only: all NPC/traffic/director systems remain enabled.
	gameplay.god_mode=true
	for candidate in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var ray := PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP,world.player.global_position+Vector3.UP+candidate*3.0,1)
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): direction=candidate; break
	aim(); await frames(60)
	check(gameplay.equipped()=="katana" and gameplay.attack_allowed(),"production session equips and allows katana")
	if "--only-rage" not in OS.get_cmdline_user_args():
		await phase("steel")
		check(_damage_seen, "real fire input reaches real actor health")
	var honor: Dictionary = preload("res://runtime/TakeshiHonor.gd").defaults()
	honor.won = true; honor.reward = "katana"; honor.best_seconds = 8.0
	honor.saber_unlocked = true; honor.saber_color = "9b54ffff"
	state.world_state["takeshi"] = honor
	await frames(5)
	check(gameplay.gun.find_child("EnergyBlade",true,false)!=null,"purchase state changes equipped model to custom-color saber")
	await phase("saber_rage", true)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("katana_gameplay.png"))
	if "--skip-temporal" not in OS.get_cmdline_user_args(): await capture_sequence()
	check(gameplay.katana_wounds.part_count()<=12,"wound workload stays within fixed limit")
	gameplay.on_region_changed(); check(gameplay.katana_wounds.part_count()==0 and is_equal_approx(Engine.time_scale,1.0),"transition clears wounds and restores time")
	var summary := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"viewport":str(root.size),"scenario":"Main, population 8, skip arrival, diagnostic god mode, all NPC/traffic/directors active", "comparison":"baseline unavailable; current state only", "measurements":measurements}
	var file := FileAccess.open(output_dir.path_join("measure.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(summary,"\t"))
	print("KATANA_SESSION checks=",checks," failures=",failures)
	world.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
