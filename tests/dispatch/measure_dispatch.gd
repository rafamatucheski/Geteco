extends SceneTree
## Medição de frame time do despacho na cena real renderizada (Vulkan). NÃO roda
## em headless: o driver dummy não mede nada. Compara duas execuções com o mesmo
## nível de procura: `--baseline` (despacho embutido de Gameplay, sem o
## controlador) e a padrão (controlador ativo). Percentis em milissegundos.
## Cenário fixo e obrigatório: `--no-save --skip-arrival --population=24 --seed=N`.
## Sem qualquer um deles a medição é recusada: save pessoal, cinemática de chegada
## ou população/aleatoriedade variável não servem de referência para o despacho.
## Uso (o integrador executa; ver gameplay/dispatch/README.md):
##   tests/dispatch/Run.ps1 -Suite measure -Stars 4      (roda baseline e dispatch em sequência)

const THRESHOLDS := [0, 12, 30, 60, 100, 160, 240]
var label := "dispatch"
var stars := 4
var baseline := false
var seconds := 30.0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Medição exige renderização real; headless não mede FPS.")
		quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	var required := ["--no-save", "--skip-arrival", "--population=24"]
	for needed in required:
		if needed not in arguments:
			push_error("Medição recusada: falta %s. Use Run.ps1 -Suite measure." % needed)
			quit(2)
			return
	var seeded := false
	for arg in arguments:
		if arg.begins_with("--seed="):
			seed(arg.split("=")[1].to_int())
			seeded = true
	if not seeded:
		push_error("Medição recusada: falta --seed=N (semente fixa do tráfego e dos moradores).")
		quit(2)
		return
	for arg in arguments:
		if arg.begins_with("--label="): label = arg.split("=")[1]
		if arg.begins_with("--stars="): stars = clampi(arg.split("=")[1].to_int(), 1, 6)
		if arg.begins_with("--seconds="): seconds = arg.split("=")[1].to_float()
		if arg == "--baseline": baseline = true
	var world: Node = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for index in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Mundo nativo não iniciou")
		quit(1)
		return
	# Arrival já foi pulada por --skip-arrival; sem isso a sessão ainda estaria em filme.
	if world.session.arrival != null and world.session.arrival.get("active") == true:
		push_error("Medição recusada: a cinemática de chegada ainda está ativa.")
		quit(2)
		return
	world.player.controlled_automatically = true
	# ProductionWorld já instala o controlador. Criar outro aqui duplicava
	# ownership, unidades e custo; o baseline também continuava com o despacho
	# novo ativo. A/B agora alterna o único controlador produtivo.
	var controller: Node3D = world.dispatch
	if not is_instance_valid(controller):
		push_error("Controlador produtivo de despacho ausente")
		quit(1)
		return
	controller.set_enabled(not baseline)
	world.gameplay.register_crime(THRESHOLDS[stars], world.player.global_position)
	for index in 300: await process_frame
	var samples := PackedFloat64Array()
	var peak_units := 0
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	while elapsed < seconds:
		await process_frame
		world.gameplay.health = 100.0
		var now := Time.get_ticks_usec()
		var step := float(now - previous) / 1000.0
		previous = now
		samples.append(step)
		elapsed += step / 1000.0
		if not baseline: peak_units = maxi(peak_units, controller.units.size())
	samples.sort()
	var count := samples.size()
	var total := 0.0
	var slow := 0
	for value in samples:
		total += value
		if value > 33.3: slow += 1
	var report := {
		"label": label, "stars": stars, "baseline": baseline, "frames": count,
		"mean_ms": total / count, "p50_ms": samples[int(count * 0.50)], "p95_ms": samples[int(count * 0.95)],
		"p99_ms": samples[mini(count - 1, int(count * 0.99))], "max_ms": samples[count - 1], "frames_over_33ms": slow,
		"peak_dispatch_units": peak_units, "renderer": RenderingServer.get_video_adapter_name(),
		"legacy_officers_alive": world.gameplay.police.size(), "seed": true, "population": world.people.size(),
	}
	if not baseline: report["dispatch_status"] = controller.status()
	var folder := ProjectSettings.globalize_path("res://tests/dispatch/results")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "/" + label + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("DISPATCH_MEASURE " + JSON.stringify(report))
	quit(0)
