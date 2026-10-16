extends SceneTree
## Atribuição dos picos de _process sem span (fase 2, 16/10/2026): no export, os sobrados travam 140–180 ms
## sempre em (340, 0, ~2) e a travessia em (602, -373) com +208 nós e ~+200 CollisionShape3D num quadro só,
## sem nenhuma operação instrumentada. Este script anda o mesmo circuito do ReleaseBenchmark e, em cada
## quadro lento ou que acrescenta muitos nós, imprime quem os acrescentou (script do ancestral mais próximo e
## caminho do pai). Só para atribuição: o editor é mais lento que o export, não use os ms como medida.
##
## Uso: tools/run_godot_locked.sh --path . --script res://tests/measure/trace_unspanned_spikes.gd -- --no-save \
##        --benchmark --no-dispatch --play-at=harbor,295,100 --rota=sobrados [--voltas=2] [--limite-ms=60]
## O ReleaseBenchmark começa no desembarque (233,194) e teleporta para a rota: --play-at=harbor,233,194 repete
## esse primeiro salto (rotas oeste/porto/ponte/travessia).
const ROUTES := {
	"sobrados": [Vector3(295, 0, 100), Vector3(340, 0, 100), Vector3(340, 0, -60), Vector3(295, 0, -60)],
	"travessia": [Vector3(330, 0, -285), Vector3(600, 0, -285), Vector3(700, 4, -300), Vector3(745, 4, -420)],
	"ponte": [Vector3(440, 0, -285), Vector3(600, 0, -285)],
	"porto": [Vector3(150, 0, 82), Vector3(250, 0, 82), Vector3(250, 0, 30), Vector3(180, 0, 30), Vector3(180, 0, 82)],
	"oeste": [Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(143, 0, 60), Vector3(84, 0, 60), Vector3(84, 0, 123), Vector3(65, 0, 113)],
}
const SPEED := 12.0
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var route: Array = ROUTES["sobrados"]
var loops := 2
var limit_ms := 60.0
var world: Variant
var _added: Array = []

func _initialize() -> void: run.call_deferred()

func _arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rota=") and ROUTES.has(argument.trim_prefix("--rota=")): route = ROUTES[argument.trim_prefix("--rota=")]
		if argument.begins_with("--voltas="): loops = int(argument.trim_prefix("--voltas="))
		if argument.begins_with("--limite-ms="): limit_ms = float(argument.trim_prefix("--limite-ms="))

func _route_point(distance: float) -> Dictionary:
	var lengths: Array[float] = []
	var total := 0.0
	for index in route.size():
		lengths.append((route[index] as Vector3).distance_to(route[(index + 1) % route.size()]))
		total += lengths[-1]
	var along := fposmod(distance, total)
	for index in route.size():
		if along <= lengths[index]:
			var a: Vector3 = route[index]
			var b: Vector3 = route[(index + 1) % route.size()]
			return {"point": a.lerp(b, along / lengths[index]), "yaw": atan2(-(b - a).x, -(b - a).z), "total": total}
		along -= lengths[index]
	return {"point": route[0], "yaw": 0.0, "total": total}

func _on_node_added(node: Node) -> void:
	_added.append(node)

func _owner_key(node: Node) -> String:
	var cursor: Node = node.get_parent()
	while cursor != null:
		var script: Script = cursor.get_script()
		if script != null and script.resource_path != "": return script.resource_path.get_file() + ":" + String(cursor.name)
		cursor = cursor.get_parent()
	return "?"

func _summary(nodes: Array) -> Array:
	var groups := {}
	for node in nodes:
		if not is_instance_valid(node): continue
		var key := "%s <- %s" % [node.get_class(), _owner_key(node)]
		groups[key] = int(groups.get(key, 0)) + 1
	var rows: Array = []
	for key in groups: rows.append([groups[key], key])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	return rows.slice(0, 14)

func _slow_spans(labels: Dictionary) -> Array:
	var rows: Array = []
	for label in labels:
		var total_ms := float(labels[label].total_usec) / 1000.0
		if total_ms >= 2.0: rows.append([snappedf(total_ms, .1), label, int(labels[label].calls)])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	return rows.slice(0, 12)

func run() -> void:
	_arguments()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 300000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var weather: Variant = world.session.weather
	weather.time_of_day = 0.5
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var car: CharacterBody3D = world.driving.car
	car.set_physics_process(false)
	car.visible = true
	world.player.set_physics_process(false)
	world.player.visible = false
	world.camera.target = car
	# Deixa o pré-aquecimento e o primeiro streaming assentarem antes de rastrear.
	for i in 180: await process_frame
	node_added.connect(_on_node_added)
	# Com --remote-debug e um receptor passivo (tests/measure/godot_profile_receiver.py), --perfil liga o
	# profiler de funções só agora, depois do carregamento, para os quadros lentos virem com o culpado.
	if "--perfil" in OS.get_cmdline_user_args(): EngineDebugger.profiler_enable("servers", true, [256, true])
	var total: float = _route_point(0.0).total
	var distance := 0.0
	var previous := Time.get_ticks_usec()
	while distance < total * loops:
		var sample := _route_point(distance)
		car.global_position = sample.point + Vector3.UP * .1
		car.rotation = Vector3(0, sample.yaw, 0)
		world.player.global_position = sample.point
		_added.clear()
		var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		# Spans do quadro (StallWorkTrace agregado): diz quanto do quadro lento já tem dono.
		STALL_WORK.start_aggregate()
		await process_frame
		var spans: Dictionary = STALL_WORK.stop_aggregate().labels
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		previous = now
		distance += SPEED * minf(frame_ms, 100.0) / 1000.0
		if frame_ms >= limit_ms or _added.size() >= 60:
			print("TRACE_FRAME ", JSON.stringify({"ms": snappedf(frame_ms, .1), "frame": Engine.get_process_frames(), "pos": [snappedf(sample.point.x, .1), snappedf(sample.point.z, .1)],
				"added": _added.size(), "nodes_delta": Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes_before,
				"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, .1), "groups": _summary(_added),
				"spans": _slow_spans(spans)}))
	if "--perfil" in OS.get_cmdline_user_args(): EngineDebugger.profiler_enable("servers", false)
	# Leituras de malha da placa (cada uma espera a GPU) que o cache poupou ou não.
	var arrays: Variant = preload("res://world/chunk_bake/MeshArrayCache.gd")
	print("TRACE_MESH_READS ", JSON.stringify({"reads": arrays.reads, "hits": arrays.hits}))
	print("TRACE_DONE")
	quit(0)
