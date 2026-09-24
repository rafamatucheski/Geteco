extends SceneTree
## Custo dos faróis automáticos do trânsito à noite, com renderização real.
## Mesmo processo, mesma cena, blocos alternados A (desligados) / B (ligados),
## VSync desligado para o custo não sumir atrás do teto de 60 FPS.
## Rodar SEM --headless e com --no-save --benchmark (o relógio do dia fica parado).
## Saída: res://evidence/traffic-headlights-0922/measure.json
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const OUTPUT := "res://evidence/traffic-headlights-0922/measure.json"
const WARMUP := 8.0
const BLOCK := 15.0
var BEAMS := 2
var world
func _initialize() -> void: run.call_deferred()

func stats(samples: Array) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	if sorted.is_empty(): return {}
	var total := 0.0
	for value in sorted: total += value
	var pick := func(p: float) -> float: return sorted[mini(sorted.size() - 1, int(p * sorted.size()))]
	return {"frames": sorted.size(), "mean_ms": total / sorted.size(), "p50_ms": pick.call(.5), "p95_ms": pick.call(.95), "p99_ms": pick.call(.99), "max_ms": sorted[-1]}

func sample(seconds: float) -> Array:
	var result := []
	var elapsed := 0.0
	var last := Time.get_ticks_usec()
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		elapsed += ms / 1000.0
		result.append(ms)
	return result

func lit_state() -> Dictionary:
	var lit := 0
	var beams := 0
	var equipped := 0
	for car in world.production.vehicles:
		if not is_instance_valid(car) or not is_instance_valid(car.equipment): continue
		equipped += 1
		if car.equipment.auto_lit: lit += 1
		if car.equipment.npc_beam.visible: beams += 1
	return {"traffic_equipped": equipped, "auto_lit": lit, "npc_beams": beams}

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args():
		print("Rode com renderização real e --no-save.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beams="): BEAMS = int(arg.trim_prefix("--beams="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	for node in world.find_children("*", "", true, false):
		if node.get("time_of_day") != null and node.get("weather_state") != null: node.time_of_day = .95
	session.state.world_state.time = .95
	# Rua em frente à delegacia: cruzamento com trânsito nos dois sentidos.
	world.player.teleport(Vector3(67.5, .1, 139))
	session.controller.region.set_focus(world.player.global_position)
	await sample(WARMUP)
	var blocks := []
	# off: sem faróis automáticos; pools: lentes + manchas no chão, sem SpotLight de
	# NPC; full: pools + os fachos reais dentro do orçamento.
	var configs := ["off", "pools", "full", "off", "pools", "full"]
	for index in configs.size():
		var config: String = configs[index]
		EQUIPMENT.night_auto_enabled = config != "off"
		EQUIPMENT.npc_beam_budget = BEAMS if config == "full" else 0
		await sample(2.0)
		var frames: Array = await sample(BLOCK)
		var entry := {"block": index, "config": config, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		entry.merge(stats(frames))
		entry.merge(lit_state())
		blocks.append(entry)
		print("BLOCK ", JSON.stringify(entry))
	EQUIPMENT.night_auto_enabled = true
	EQUIPMENT.npc_beam_budget = 2
	var report := {"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "vsync": "disabled", "hour": .95, "full_beams": BEAMS, "blocks": blocks,
		"notes": "A/B alternado no mesmo processo; trânsito é aleatório, então a quantidade de carros acesos varia entre blocos."}
	var file := FileAccess.open(ProjectSettings.globalize_path(OUTPUT), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	world.queue_free()
	await process_frame
	quit(0)
