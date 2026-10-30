extends SceneTree
## Ruas de Harbor no jogo de verdade (Main.tscn), na câmera de jogo, antes e depois dos objetos
## soltos do StreetJunk (lixo, porto, orla). Mesmo build, interruptor de ambiente para o "antes":
##   GETECO_STREET_JUNK=0 tools/run_godot_locked.sh --path . --script res://tests/capture/capture_harbor_props.gd -- --no-save --label=antes
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_harbor_props.gd -- --no-save --label=depois
## Com tela, nunca --headless. PNG e JSON em evidence/harbor-props-20261029/ (PNG fica fora do Git).
## Por local: draw calls, objetos e primitivas do quadro (mediana e faixa de 60 quadros parados),
## quantas peças e lotes do StreetJunk estão nos chunks carregados e quanto a montagem custou.
## Não é medição de desempenho: o editor é debug e o trânsito muda entre rodadas. FPS/ms só no
## export release (docs/HOW-TO-DEVELOP.md).
const JUNK_KIT := preload("res://world/city_look/StreetJunkKit.gd")

## Pontos onde o jogador fica; a câmera olha para o norte, 25 m atrás e 25 m acima.
var points := {
	"cais": Vector3(280.0, 0.0, 214.0), # pátio do porto sul entre a borda do cais e a via do porto
	"centro": Vector3(52.0, 0.0, 84.0), # Market Street: lanchonete, lavanderia e oficina
	# A faixa ao sul da Dock Street é do BRT (reservada); a orla com mesas fica no calçadão da ilha.
	"orla": Vector3(350.0, 0.0, 149.0), # calçadão do cais sul da ilha, entre a Island Dock Street e a água
	"bairro": Vector3(318.0, 0.0, 30.0), # sobrados da Foundry Avenue
}


func _initialize() -> void:
	create_timer(840).timeout.connect(func(): push_error("HARBOR_PROPS_CAPTURE timeout"); quit(3))
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("captura precisa de janela")
		quit(2)
		return
	var label := "depois"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/harbor-props-20261029"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var weather: Variant = world.session.weather
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	weather.time_of_day = 12.0 / 24.0
	var summary := {"label": label, "street_junk": OS.get_environment("GETECO_STREET_JUNK") != "0", "points": {}}
	for id in points:
		var point: Vector3 = points[id]
		world.player.teleport(point + Vector3.UP * .1)
		world.player.rotation.y = 0.0
		world.production.region.set_focus(point, true)
		for frame in 600:
			await process_frame
			if world.production.region.is_streaming_idle() and frame > 150: break
		for frame in 90: await process_frame
		var draws: Array[int] = []
		var objects: Array[int] = []
		var primitives: Array[int] = []
		for frame in 60:
			await process_frame
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		draws.sort()
		objects.sort()
		primitives.sort()
		var path := "%s/%s_%s.png" % [folder, id, label]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		var junk := _junk_census(world.production.region, point)
		summary.points[id] = {"draw_calls_median": draws[30], "draw_calls_min": draws[0], "draw_calls_max": draws[-1],
			"objects_median": objects[30], "primitives_median": primitives[30], "junk": junk}
		print("CAPTURE %s %s draws=%d (%d-%d) objects=%d junk=%s" % [id, ProjectSettings.globalize_path(path), draws[30], draws[0], draws[-1], objects[30], JSON.stringify(junk)])
	var file := FileAccess.open(ProjectSettings.globalize_path("%s/%s.json" % [folder, label]), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	quit(0)


## Peças e lotes do StreetJunk nos chunks carregados e nos 3 × 3 em volta do ponto (o quadro de jogo),
## mais o custo de montagem registrado pelo passo em cada chunk.
func _junk_census(region: Node, point: Vector3) -> Dictionary:
	var center := Vector2i(floori(point.x / 64.0), floori(point.z / 64.0))
	var result := {"near_items": 0, "near_batches": 0, "near_shadow_batches": 0, "kinds": {}, "build_ms_max": 0.0, "step_ms_max": 0.0, "chunks": 0}
	for key: Vector2i in region.chunks:
		var chunk: Node3D = region.chunks[key]
		if not is_instance_valid(chunk): continue
		if chunk.has_meta("street_junk_ms"):
			result.chunks = int(result.chunks) + 1
			result.build_ms_max = maxf(float(result.build_ms_max), float(chunk.get_meta("street_junk_ms")))
			result.step_ms_max = maxf(float(result.step_ms_max), float(chunk.get_meta("street_junk_step_max_ms", 0.0)))
		if absi(key.x - center.x) > 1 or absi(key.y - center.y) > 1: continue
		# Inventário do que já existe: toda MultiMesh do CityLook que não é decalque nem telhado.
		for view in chunk.get_children():
			if not view is MultiMeshInstance3D: continue
			var node_name := String(view.name)
			if not node_name.begins_with("CityLook_") or node_name.begins_with("CityLook_decal") or node_name.begins_with("CityLook_roofmat") or node_name.begins_with("CityLook_graffiti"): continue
			var kind := node_name.trim_prefix("CityLook_")
			if (view as MultiMeshInstance3D).multimesh == null: continue
			var all: Dictionary = result.get("all_kinds", {})
			all[kind] = int(all.get(kind, 0)) + (view as MultiMeshInstance3D).multimesh.instance_count
			result.all_kinds = all
		for kind: String in JUNK_KIT.KINDS:
			var view := chunk.get_node_or_null("CityLook_" + kind) as MultiMeshInstance3D
			if view == null: continue
			result.near_batches = int(result.near_batches) + 1
			if view.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: result.near_shadow_batches = int(result.near_shadow_batches) + 1
			result.near_items = int(result.near_items) + view.multimesh.instance_count
			result.kinds[kind] = int(result.kinds.get(kind, 0)) + view.multimesh.instance_count
	return result
