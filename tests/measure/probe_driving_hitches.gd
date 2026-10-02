extends SceneTree
## Dirige um veículo de verdade (física, tráfego, polícia do mundo) pela rodovia porto -> montanha
## a uma velocidade fixa e registra os quadros acima de 40 ms. Diferente da sonda de teleporte, o
## foco do streaming vem do carro, na velocidade máxima do jogo. Renderizado, sem outra instância:
##   godot --path . --script res://tests/measure/probe_driving_hitches.gd -- --no-save --skip-arrival --speed=45
const SEAM := preload("res://world/regions/WorldConnection3D.gd").SEAM
var world: Node3D
var frames: Array[float] = []
var spikes: Array[Dictionary] = []
var t_process := 0
var t_pre := 0
var t_post := 0
var t_physics := 0
var beat_thread := Thread.new()
var beat_run := true
var beat_gaps: Array = []

func beat_loop() -> void:
	var last := Time.get_ticks_usec()
	while beat_run:
		OS.delay_usec(1000)
		var now := Time.get_ticks_usec()
		if now - last >= 150000: beat_gaps.append("%.0f ms em t=%d" % [float(now - last) / 1000.0, now / 1000])
		last = now

func _initialize() -> void:
	physics_frame.connect(func():
		t_physics = Time.get_ticks_usec()
		if "--per-physics" in OS.get_cmdline_user_args(): run_adopted_physics())
	process_frame.connect(func():
		t_process = Time.get_ticks_usec()
		if "--per-script" in OS.get_cmdline_user_args() and world != null:
			script_frame += 1
			if script_frame % 5 == 1: adopt_processing_nodes()
			var slow := run_timed_processes(1.0 / 60.0)
			if not slow.is_empty(): script_slow.append([t_process, slow]))
	RenderingServer.frame_pre_draw.connect(func(): t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): t_post = Time.get_ticks_usec())
	run.call_deferred()

## --per-script: todo nó com _process passa a ser chamado daqui, cronometrado; o que passa de
## 3 ms entra em `script_slow` com o instante, para o quadro lento listar quem custou.
var timed_nodes: Array[Node] = []
var script_slow: Array = []
var script_frame := 0

func adopt_processing_nodes() -> void:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node.get_script() != null and node.is_processing() and node.has_method("_process") and node not in timed_nodes:
			timed_nodes.append(node)
			node.set_process(false)

func run_timed_processes(delta: float) -> Dictionary:
	var slow := {}
	for node in timed_nodes:
		if not is_instance_valid(node) or not node.is_inside_tree(): continue
		var began := Time.get_ticks_usec()
		node._process(delta)
		var ms := float(Time.get_ticks_usec() - began) / 1000.0
		if ms >= 3.0: slow[(node.get_script() as Script).resource_path.get_file()] = snappedf(ms, 0.1)
	return slow

func arg_float(name: String, fallback: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="): return float(arg.trim_prefix(name + "="))
	return fallback

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--skip-arrival" not in args: quit(2); return
	var speed := arg_float("--speed", 45.0)
	var label := "drive-%d%s%s" % [int(speed), ("-stars%d" % int(arg_float("--stars", 0.0))) if arg_float("--stars", 0.0) > 0.0 else "", "-chuva" if "--rain" in args else ""]
	create_timer(300.0).timeout.connect(func(): push_error("PROBE_TIMEOUT"); quit(2))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("benchmark_trace", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: push_error("mundo não iniciou"); quit(1); return
	world.session.state.intro.stage = "complete"
	for i in 240: await process_frame
	var car: CharacterBody3D = world.driving.car
	# --list-nodes imprime os sistemas do mundo; --disable=A,B desliga o _process/_physics_process
	# deles (bisseção de custo: o pico some quando o culpado está na lista).
	if "--list-nodes" in args:
		for node in world.get_children(): print("NODE ", node.name, " ", (node.get_script() as Script).resource_path if node.get_script() != null else "-")
	for arg in args:
		if arg.begins_with("--disable-script="):
			var parts := arg.trim_prefix("--disable-script=").split(",")
			for node in world.get_children():
				var script_path := (node.get_script() as Script).resource_path if node.get_script() != null else ""
				for part in parts:
					if not part.is_empty() and script_path.contains(part):
						node.process_mode = Node.PROCESS_MODE_DISABLED
						print("DESLIGADO ", script_path)
		if arg.begins_with("--disable="):
			for node_name in arg.trim_prefix("--disable=").split(","):
				var target := world.get_node_or_null(node_name)
				if target != null: target.process_mode = Node.PROCESS_MODE_DISABLED
				else: print("DISABLE não achou ", node_name)
	var start := Vector3(arg_float("--from", SEAM.x - 900.0), 0.0, SEAM.z)
	var ground_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(start.x, 400, start.z), Vector3(start.x, -50, start.z), 1))
	start.y = (float(ground_hit.position.y) if not ground_hit.is_empty() else 0.0) + .5
	world.production.region.set_focus(start)
	for i in 120: await physics_frame
	car.place(start, -PI / 2.0)
	var entered := false
	for side in [-1, 1]:
		var approach := car.to_global(Vector3(side * (car.half_width + .65), .04, .15))
		world.player.teleport(approach)
		await physics_frame
		if world.driving.interact(): entered = true; break
	print("DRIVE entered=", entered, " car=", car.global_position)
	car.set_external_driver(true)
	car.brake_input = false
	Engine.set_meta("slow_stream_records", [])
	beat_thread.start(beat_loop)
	var stars := int(arg_float("--stars", 0.0))
	if stars > 0:
		world.gameplay.register_crime(world.gameplay.STAR_THRESHOLDS[stars] + 1.0, world.player.global_position)
	if "--rain" in args:
		world.session.weather.weather_state = 1
		world.session.weather.weather_timer = 99999.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var previous := Time.get_ticks_usec()
	var elapsed := 0.0
	var stuck := 0.0
	var last_position := car.global_position
	var goal_x := arg_float("--to", SEAM.x + 900.0)
	var distance_done := 0.0
	while car.global_position.x < goal_x and elapsed < 240.0:
		# Volante simples: aponta para a rodovia (z = SEAM.z) 40 m à frente; velocidade fixa.
		var target := Vector3(car.global_position.x + 40.0, 0.0, SEAM.z)
		var to_target := target - car.global_position
		var desired := atan2(-to_target.x, -to_target.z)
		car.rotation.y = lerp_angle(car.rotation.y, desired, .15)
		car.speed = speed
		car.throttle_input = 1.0
		var saved_process := t_process
		# O carro arranca durante a animação de embarque e o jogador ficava para trás (ou
		# desembarcava), então população, polícia do pátio e estações mediam o lugar errado.
		# Dirigindo de verdade o jogador acompanha o carro; aqui ele é mantido junto dele.
		if world.player.global_position.distance_to(car.global_position) > 3.0: world.player.teleport(car.global_position)
		await process_frame
		var prev_pre := t_pre
		var prev_post := t_post
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		elapsed += frame_ms / 1000.0
		frames.append(frame_ms)
		var moved := car.global_position.distance_to(last_position)
		if moved < 5.0: distance_done += moved
		stuck = stuck + frame_ms / 1000.0 if moved < 0.05 else 0.0
		last_position = car.global_position
		if stuck > .6:
			# Preso em tráfego/obstáculo: reposiciona 15 m à frente na rodovia e segue.
			car.place(Vector3(car.global_position.x + 15.0, car.global_position.y + .5, SEAM.z), -PI / 2.0)
			stuck = 0.0
		if frame_ms > 40.0:
			var labels := []
			for cost in world.get_meta("perf_costs", []):
				if int(cost.start_usec) >= now - int(frame_ms * 1000.0) - 2000 and int(cost.start_usec) <= now:
					labels.append("%s %.1f ms" % [cost.label, float(cost.duration_usec) / 1000.0])
			var slow_physics := []
			for entry in physics_slow:
				if int(entry[0]) >= now - int(frame_ms * 1000.0) - 2000: slow_physics.append(entry[1])
			if not slow_physics.is_empty(): labels.append("fisica lenta: " + str(slow_physics))
			var slow_scripts := []
			for entry in script_slow:
				if int(entry[0]) >= now - int(frame_ms * 1000.0) - 2000: slow_scripts.append(entry[1])
			if not slow_scripts.is_empty(): labels.append("scripts lentos: " + str(slow_scripts))
			labels.append("fisica_monitor=%.1f ms objetos=%d pares=%d ilhas=%d" % [Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)), int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))])
			labels.append("fases: scripts=%.0f desenho=%.0f espera_fisica=%.0f batimento=%s" % [float(prev_pre - saved_process) / 1000.0, float(prev_post - prev_pre) / 1000.0, float(t_process - prev_post) / 1000.0, str(beat_gaps.slice(-2))])
			spikes.append({"t": snappedf(elapsed, 0.01), "frame_ms": snappedf(frame_ms, 0.1), "x": snappedf(car.global_position.x, 1.0), "z": snappedf(car.global_position.z, 1.0), "labels": labels})
			print("SPIKE t=%.1fs %.0f ms at (%.0f,%.0f) %s" % [elapsed, frame_ms, car.global_position.x, car.global_position.z, str(labels)])
	frames.sort()
	var summary := {"speed": speed, "frames": frames.size(), "seconds": snappedf(elapsed, 0.1), "meters": snappedf(distance_done, 1.0), "p50": frames[frames.size() / 2], "p95": frames[int(frames.size() * .95)], "p99": frames[int(frames.size() * .99)], "max": frames[-1], "over_40": spikes.size(), "over_16_7": frames.filter(func(v): return v > 16.7).size()}
	print("DRIVE_SUMMARY ", JSON.stringify(summary))
	beat_run = false
	beat_thread.wait_to_finish()
	print("SLOW_RECORDS ", str(Engine.get_meta("slow_stream_records", [])))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/region-hitches"))
	var output_path := "res://evidence/region-hitches/%s.json" % label
	for arg in args:
		if arg.begins_with("--out="): output_path = arg.trim_prefix("--out=")
	# Uma nova investigação precisa preservar as rodadas anteriores.
	if FileAccess.file_exists(output_path):
		push_error("Já existe evidência em " + output_path)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível gravar " + output_path)
		quit(2)
		return
	file.store_string(JSON.stringify({"summary": summary, "spikes": spikes}, "\t"))
	file.close()
	quit(0)

## --per-physics: todo nó com _physics_process passa a ser chamado daqui, cronometrado; o que passa
## de 3 ms entra em `physics_slow` com o instante, para o quadro lento listar quem custou.
var adopted: Array[Node] = []
var physics_slow: Array = []
var adopt_frame := 0

func adopt_physics_nodes() -> void:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node.get_script() != null and node.is_physics_processing() and node.has_method("_physics_process") and node not in adopted:
			adopted.append(node)
			node.set_physics_process(false)

func run_adopted_physics() -> void:
	adopt_frame += 1
	if adopt_frame % 30 == 1: adopt_physics_nodes()
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	for node in adopted:
		if not is_instance_valid(node) or not node.is_inside_tree(): continue
		var began := Time.get_ticks_usec()
		node._physics_process(delta)
		var spent := Time.get_ticks_usec() - began
		if spent >= 3000: physics_slow.append([began, "%s %.1f ms" % [(node.get_script() as Script).resource_path.get_file(), float(spent) / 1000.0]])
