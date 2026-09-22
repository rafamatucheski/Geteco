extends SceneTree
## Custo de N pedestres civis andando, com renderização real (nunca headless:
## o driver dummy tira o sentido de draw calls e tempo de quadro).
## Uso:
##   "$GODOT" --path . --script res://tests/measure_pedestrian_cost.gd -- --model=res://assets/CivilianModel.gd --count=96
## Relata percentis em milissegundos (não FPS) e as draw calls do quadro.
var model_path := "res://assets/CivilianModel.gd"
var count := 96
var frames := 600
var carriers: Array = []
var _last_usec := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="): model_path = arg.substr(8)
		elif arg.begins_with("--count="): count = arg.substr(8).to_int()
		elif arg.begins_with("--frames="): frames = arg.substr(9).to_int()
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("measure_pedestrian_cost: precisa de renderização real")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 26.0
	stage.add_child(camera)
	camera.current = true
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 4, 0, 0)), Vector3(0, 30, 30))
	var script: Script = load(model_path)
	var spawn_usec: Array[int] = []
	for i in count:
		var began := Time.get_ticks_usec()
		var carrier := Node3D.new()
		# Grade dentro do enquadramento da câmera: todos visíveis, pior caso.
		carrier.position = Vector3(-18.0 + (i % 12) * 3.2, 0, -9.0 + (i / 12) * 2.4)
		stage.add_child(carrier)
		var model: Node3D = script.new()
		model.set("appearance_locked", true)
		model.set("appearance_variant", i * 37 + 11)
		model.rotation.y = PI
		carrier.add_child(model)
		spawn_usec.append(Time.get_ticks_usec() - began)
		# 1 em 8 corre (fuga a 5 m/s); o resto anda na faixa da rua.
		carriers.append({"node": carrier, "model": model, "speed": 5.0 if i % 8 == 0 else lerpf(1.15, 1.75, fposmod(i * 0.618, 1.0)), "angle": float(i), "origin": carrier.position})
	for i in 120: await _step()
	var frame_ms: Array[float] = []
	var script_ms: Array[float] = []
	var draw_calls: Array[float] = []
	for i in frames:
		var began := Time.get_ticks_usec()
		await _step()
		frame_ms.append((Time.get_ticks_usec() - began) / 1000.0)
		# Custo de script dos modelos medido direto: o monitor TIME_PROCESS só
		# atualiza uma vez por segundo e mistura o resto da árvore.
		var script_began := Time.get_ticks_usec()
		for entry in carriers: entry.model._process(0.0)
		script_ms.append((Time.get_ticks_usec() - script_began) / 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# O primeiro pedestre paga a construção das malhas em cache; os seguintes
	# só pagam cortes de roupa ainda não vistos.
	var first_spawn := spawn_usec[0]
	spawn_usec.sort()
	print("PEDESTRIAN_COST model=%s count=%d" % [model_path, count])
	print("  spawn us: first=%d p50=%d p95=%d max=%d" % [first_spawn, spawn_usec[spawn_usec.size() / 2], spawn_usec[int(spawn_usec.size() * 0.95)], spawn_usec[-1]])
	print("  frame ms: %s" % _percentiles(frame_ms))
	print("  modelos _process ms (todos): %s" % _percentiles(script_ms))
	print("  draw calls: %s" % _percentiles(draw_calls))
	quit(0)

func _step() -> void:
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_usec) / 1000000.0, 0.0001, 0.1) if _last_usec > 0 else 1.0 / 60.0
	_last_usec = now
	for entry in carriers:
		# Círculo de 2,5 m: vira o tempo todo, como um Actor seguindo rota.
		entry.angle += entry.speed * delta / 2.5
		var node: Node3D = entry.node
		node.position = entry.origin + Vector3(cos(entry.angle), 0, sin(entry.angle)) * 2.5
		node.rotation.y = -entry.angle
		entry.model.set("walking", true)
	await process_frame

static func _percentiles(values: Array[float]) -> String:
	var sorted := values.duplicate()
	sorted.sort()
	var pick := func(q: float) -> float: return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)]
	return "p50=%.2f p95=%.2f p99=%.2f max=%.2f" % [pick.call(0.5), pick.call(0.95), pick.call(0.99), sorted[-1]]
