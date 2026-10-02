extends SceneTree
## Caça finita de travadas na cena real: primeira utilização de armas, combate
## prolongado e recuperação. Setup usa cheats e fire_at; não aprova combate normal.
class EndProbe extends Node:
	var recorder: SceneTree
	func _process(_delta: float) -> void: recorder.process_end = Time.get_ticks_usec()
	func _physics_process(_delta: float) -> void: recorder.physics_end = Time.get_ticks_usec()

class SynchronousWriter extends RefCounted:
	# Controle diagnóstico: reproduz store_line/flush antigo apenas nesta sonda.
	const WORK := preload("res://runtime/StallWorkTrace.gd")
	var file: FileAccess
	var batches := 0
	var maximum := 0.0
	func open_append(path: String) -> Error:
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file == null: return FileAccess.get_open_error()
		file.seek_end()
		return OK
	func enqueue(line: String) -> bool:
		var began := WORK.begin()
		file.store_line(line)
		WORK.finish("logger.sync_store", began)
		began = Time.get_ticks_usec()
		file.flush()
		var ms := float(Time.get_ticks_usec()-began)/1000.0
		WORK.finish("logger.sync_flush", began)
		maximum = maxf(maximum, ms)
		batches += 1
		return true
	func stats() -> Dictionary:
		return {"threaded": false, "diagnostic_fixture": true, "queued_records": 0,
			"dropped_records": 0, "write_batches": batches, "max_write_ms": maximum}
	func stop() -> void:
		if file != null:
			file.close()
			file = null

var world: Node3D
var process_begin := 0
var process_end := 0
var physics_begin := 0
var physics_end := 0
var draw_pre := 0
var draw_post := 0
var started := 0
var phase := "setup"
var frame_samples: Dictionary = {}
var slow: Array[Dictionary] = []
var events: Array[Dictionary] = []
var census: Array[Dictionary] = []
var heartbeat := Thread.new()
var beat_mutex := Mutex.new()
var beat_running := false
var beat_gaps: Array[Dictionary] = []
var target := Vector3.ZERO
var successful_shots := 0

func _initialize() -> void:
	# Controle sem logger conserva o mesmo teto de física da comparação.
	var steps := OS.get_environment("HARBOR_MAX_PHYSICS_STEPS")
	if steps.is_valid_int() and int(steps) >= 1: Engine.max_physics_steps_per_frame = int(steps)
	process_frame.connect(_frame_start)
	physics_frame.connect(func(): physics_begin = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func(): draw_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): draw_post = Time.get_ticks_usec())
	run.call_deferred()

func arg(name: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name + "="): return value.trim_prefix(name + "=")
	return fallback

func _frame_start() -> void:
	var now := Time.get_ticks_usec()
	if started > 0 and process_begin >= started:
		var ms := float(now - process_begin) / 1000.0
		var list: Array = frame_samples.get(phase, [])
		list.append(ms)
		frame_samples[phase] = list
		if ms > 66.7:
			var record := {"clock_usec": now, "t": float(now - started) / 1000000.0,
				"phase": phase, "frame_ms": ms, "process_frame": Engine.get_process_frames(),
				"timestamps": {"process_begin": process_begin, "process_end": process_end,
					"draw_pre": draw_pre, "draw_post": draw_post, "physics_begin": physics_begin, "physics_end": physics_end},
				"position": str(world.player.global_position), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
			# Intervalos só válidos quando a ordem dos sinais permite essa leitura.
			if process_end >= process_begin: record["process_callbacks_ms"] = float(process_end - process_begin) / 1000.0
			if draw_pre >= process_end: record["after_process_to_draw_ms"] = float(draw_pre - process_end) / 1000.0
			if draw_post >= draw_pre: record["draw_signal_interval_ms"] = float(draw_post - draw_pre) / 1000.0
			if physics_end >= physics_begin: record["last_physics_callbacks_ms"] = float(physics_end - physics_begin) / 1000.0
			slow.append(record)
			if "--verbose-progress" in OS.get_cmdline_user_args() and "--quiet" not in OS.get_cmdline_user_args():
				var print_began := Time.get_ticks_usec()
				print("COMBAT_STALL ", JSON.stringify(record))
				record["diagnostic_print_ms"] = float(Time.get_ticks_usec()-print_began)/1000.0
	process_begin = now

func beat_loop() -> void:
	var last := Time.get_ticks_usec()
	while true:
		beat_mutex.lock()
		var running := beat_running
		beat_mutex.unlock()
		if not running: break
		OS.delay_usec(2000)
		var now := Time.get_ticks_usec()
		if now - last >= 50000:
			beat_mutex.lock()
			if beat_gaps.size() < 2000: beat_gaps.append({"clock_usec": now, "gap_ms": float(now-last)/1000.0})
			beat_mutex.unlock()
		last = now

func _finalize() -> void:
	if heartbeat.is_started():
		beat_mutex.lock()
		beat_running = false
		beat_mutex.unlock()
		heartbeat.wait_to_finish()

func record_action(label: String, action: Callable) -> void:
	var began := Time.get_ticks_usec()
	action.call()
	events.append({"label": label, "clock_usec": began, "t": float(began-started)/1000000.0,
		"sync_ms": float(Time.get_ticks_usec()-began)/1000.0})

func choose_target() -> void:
	var origin: Vector3 = world.player.global_position
	target = origin + Vector3(8, 0, -2)
	var best := 24.0
	for car in world.production.vehicles:
		if not is_instance_valid(car) or car == world.driving.car or car.health <= 0: continue
		var distance := origin.distance_to(car.global_position)
		if distance < best:
			best = distance
			target = car.global_position
	if world.dispatch != null:
		for unit in world.dispatch.units:
			if not is_instance_valid(unit.vehicle) or unit.vehicle.health <= 0: continue
			var distance := origin.distance_to(unit.vehicle.global_position)
			if distance < best:
				best = distance
				target = unit.vehicle.global_position
	var direction := (target - origin).normalized()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0
	down.y = 0
	root.get_node("GameInput").touch_aim = Vector2(direction.dot(right.normalized()), direction.dot(down.normalized()))

func take_census(seconds: float) -> void:
	var units := {}
	var police_near := 0
	var wrecks := 0
	if world.dispatch != null:
		for unit in world.dispatch.units:
			var key := "%s:%s" % [unit.service, unit.state]
			units[key] = int(units.get(key, 0)) + 1
			if unit.is_police() and is_instance_valid(unit.vehicle) and unit.vehicle.global_position.distance_to(world.player.global_position) < 40: police_near += 1
	for car in world.production.vehicles:
		if is_instance_valid(car) and car.health <= 0: wrecks += 1
	census.append({"t": seconds, "phase": phase, "stars": world.gameplay.stars,
		"place_id": world.session.state.place_id, "attack_allowed": world.gameplay.attack_allowed(),
		"position": str(world.player.global_position), "units": units, "police_near_40m": police_near,
		"fires": get_nodes_in_group("ground_fire").size(), "wrecks": wrecks, "people": world.people.size(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "shots": successful_shots,
		"modal": world.session.modal, "health": world.gameplay.health, "weapon": world.gameplay.equipped()})
	if "--verbose-progress" in OS.get_cmdline_user_args() and "--quiet" not in OS.get_cmdline_user_args():
		var print_began := Time.get_ticks_usec()
		print("COMBAT_LOAD ", JSON.stringify(census[-1]))
		census[-1]["diagnostic_print_ms"] = float(Time.get_ticks_usec()-print_began)/1000.0

func stats(list: Array) -> Dictionary:
	if list.is_empty(): return {}
	var sorted := list.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in list: total += ms
	return {"frames": list.size(), "seconds": total/1000.0, "p50_ms": sorted[int(list.size()*.5)],
		"p95_ms": sorted[int(list.size()*.95)], "p99_ms": sorted[int(list.size()*.99)], "max_ms": sorted[-1],
		"over_33_ms": list.filter(func(ms): return ms > 33.3).size(),
		"over_66_ms": list.filter(func(ms): return ms > 66.7).size(),
		"over_500_ms": list.filter(func(ms): return ms >= 500).size()}

func run() -> void:
	var output := arg("--out", "")
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not output.begins_with("res://evidence/") or FileAccess.file_exists(output):
		push_error("Exige janela renderizada, --no-save e --out novo dentro de evidence.")
		quit(2)
		return
	seed(20261001)
	create_timer(430.0).timeout.connect(func(): push_error("COMBAT_TIMEOUT"); quit(2))
	if "--sync-logger" in OS.get_cmdline_user_args():
		var logger := root.get_node("StallLog")
		if logger._writer == null:
			push_error("Controle síncrono exige StallLog ativo.")
			quit(2)
			return
		logger._writer.stop()
		var synchronous := SynchronousWriter.new()
		if synchronous.open_append(logger._path) != OK:
			push_error("Não abriu log para controle síncrono.")
			quit(2)
			return
		logger._writer = synchronous
	root.size = Vector2i(1920,1080)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("benchmark_trace", true)
	root.add_child(world)
	current_scene = world
	for i in 6000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Partida não iniciou.")
		quit(1)
		return
	world.session.state.intro.stage = "complete"
	for i in 60: await physics_frame
	if not world.gameplay.attack_allowed():
		push_error("Ponto inicial não permite combate.")
		quit(1)
		return
	world.gameplay.toggle_god_mode()
	world.gameplay.activate_arsenal_cheat()
	var end_probe := EndProbe.new()
	end_probe.recorder = self
	end_probe.process_priority = 1000000
	end_probe.process_physics_priority = 1000000
	root.add_child(end_probe)
	if "--profile" in OS.get_cmdline_user_args():
		if not EngineDebugger.is_active() or not EngineDebugger.has_profiler("servers"):
			push_error("A captura --profile exige debugger local conectado e profiler servers.")
			quit(2)
			return
		EngineDebugger.profiler_enable("servers", true, [128, true])
	beat_running = true
	heartbeat.start(beat_loop)
	started = Time.get_ticks_usec()
	var weapons := ["smg", "shotgun", "ak47", "m4a1", "rpg", "flamethrower", "grenade"]
	var previous_weapon := ""
	var next_target := 0.0
	var next_census := 0.0
	var duration := clampf(float(arg("--seconds", "300")), 120, 360)
	var combat_weapon := arg("--combat-weapon", "")
	var fast := "--fast" in OS.get_cmdline_user_args()
	var idle_until := 5.0 if fast else 20.0
	var weapons_until := 40.0 if fast else 90.0
	var recovery_seconds := 20.0 if fast else 60.0
	if combat_weapon != "" and combat_weapon not in weapons:
		push_error("Arma de combate da sonda inválida.")
		_finalize()
		quit(2)
		return
	print("COMBAT_READY pid=", OS.get_process_id(), " clock_usec=", started, " position=", world.player.global_position)
	var interruption := {}
	while true:
		await process_frame
		var seconds := float(Time.get_ticks_usec()-started)/1000000.0
		if seconds >= duration: break
		phase = "idle" if seconds < idle_until else ("first_weapons" if seconds < weapons_until else ("combat" if seconds < duration-recovery_seconds else "recovery"))
		if not world.session.state.place_id.is_empty() or world.session.rescue_pending or world.session.arrest_pending:
			interruption = {"t": seconds, "place_id": world.session.state.place_id,
				"rescue_pending": world.session.rescue_pending, "arrest_pending": world.session.arrest_pending,
				"position": str(world.player.global_position)}
			take_census(seconds)
			print("COMBAT_LOCATION_INTERRUPTION ", JSON.stringify(interruption))
			break
		if "--walk-loop" in OS.get_cmdline_user_args():
			# Inputs normais num circuito curto: exercita replanejamento e contato
			# com o alvo em movimento, sem teleportar durante a medição.
			var directions := [Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT, Vector2.UP]
			root.get_node("GameInput").touch_move = directions[int((seconds - idle_until) / 8) % 4] if phase in ["first_weapons", "combat"] else Vector2.ZERO
		var weapon := ""
		if phase == "first_weapons": weapon = weapons[mini(6, int((seconds-idle_until)/((weapons_until-idle_until)/7.0)))]
		elif phase == "combat": weapon = ["m4a1", "flamethrower", "rpg"][int((seconds-weapons_until)/15)%3]
		if phase == "combat" and combat_weapon != "": weapon = combat_weapon
		if weapon != "" and weapon != previous_weapon:
			record_action("equip:" + weapon, func(): world.session.state.equip_weapon(weapon))
			previous_weapon = weapon
		if previous_weapon != "" and not world.gameplay.has_meta("probe_crime_applied"):
			world.gameplay.set_meta("probe_crime_applied", true)
			var wanted := clampi(int(arg("--stars", "0")), 0, 6)
			if wanted > 0:
				record_action("fixture:confirmed_crime", func(): world.gameplay.register_crime(world.gameplay.STAR_THRESHOLDS[wanted]+1, world.player.global_position))
		if seconds >= next_target:
			next_target = seconds + .5
			record_action("probe:choose_target", choose_target)
		if weapon != "" and not world.session.modal:
			var before := Time.get_ticks_usec()
			if world.gameplay.fire_at(target):
				successful_shots += 1
				var cost := float(Time.get_ticks_usec()-before)/1000.0
				if cost >= 2: events.append({"label": "fire:"+weapon, "clock_usec": before, "t": seconds, "sync_ms": cost})
		if seconds >= next_census:
			next_census = seconds + 5
			record_action("probe:census", func(): take_census(seconds))
		if world.session.modal:
			print("COMBAT_MODAL_INTERRUPTION")
			break
	if "--profile" in OS.get_cmdline_user_args(): EngineDebugger.profiler_enable("servers", false)
	_finalize()
	root.get_node("GameInput").touch_aim = Vector2.ZERO
	root.get_node("GameInput").touch_move = Vector2.ZERO
	var summary := {}
	for key in frame_samples: summary[key] = stats(frame_samples[key])
	var all: Array = []
	for key in frame_samples: all.append_array(frame_samples[key])
	summary["all"] = stats(all)
	var report := {"summary": summary, "frames_ms_by_phase": frame_samples, "slow": slow,
		"coverage_interruption": interruption,
		"actions": events, "census": census, "heartbeat_gaps": beat_gaps,
		"configuration": {"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
			"gpu": RenderingServer.get_video_adapter_name(), "viewport": str(root.size), "msaa": root.msaa_3d,
			"max_fps": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode(), "max_physics_steps": Engine.max_physics_steps_per_frame,
			"godmode": true, "arsenal_cheat": true, "direct_fire_api": true, "population_requested": world.production.requested_population,
			"requested_stars": int(arg("--stars", "0")), "quiet_probe": "--verbose-progress" not in OS.get_cmdline_user_args() or "--quiet" in OS.get_cmdline_user_args(),
			"script_profiler": "--profile" in OS.get_cmdline_user_args(),
			"debugger_active": EngineDebugger.is_active(), "combat_weapon": combat_weapon,
			"walk_loop_fixture": "--walk-loop" in OS.get_cmdline_user_args(),
			"fast_fixture": fast, "idle_seconds": idle_until, "first_weapons_until": weapons_until, "recovery_seconds": recovery_seconds,
			"sync_logger_fixture": "--sync-logger" in OS.get_cmdline_user_args(),
			"start_usec": started, "pid": OS.get_process_id(), "system_unix": Time.get_unix_time_from_system()}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Falha ao gravar relatório.")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("COMBAT_SUMMARY ", JSON.stringify(summary))
	quit(0 if interruption.is_empty() else 1)
