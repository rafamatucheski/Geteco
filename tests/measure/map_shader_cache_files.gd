extends SceneTree
## Mapa arquivo do shader_cache -> material (28/10). O pico "surface" da primeira sessão grava uma versão de
## shader nova (SceneForwardClusteredShaderRD/<definições>/<código>.vulkan.cache), mas o nome do arquivo é um hash
## do GLSL gerado e não diz de qual material veio. Aqui o jogo carrega com cache frio, e cada material da árvore
## (inclusive os de nós escondidos e estacionados, que é o que aparece sem nó novo no quadro do pico) é desenhado
## sozinho num quad na frente da câmera; o arquivo que nasce naquele quadro é daquele material.
## Rode com janela e com APPDATA apontando para uma pasta vazia (cache frio sem tocar no do jogador):
##   APPDATA=<pasta vazia> tools/run_godot_locked.sh --path . --script res://tests/measure/map_shader_cache_files.gd -- --no-save [--target=<hash>]
## Assinatura e quad aproximam o motor: a mesma assinatura com outro nó pode cair em outro arquivo, por isso o
## alvo achado vale como pista para confirmar no export, não como prova.
const PROBE := preload("res://tests/measure/ShaderFirstUseProbe.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CACHE_DIR := "user://shader_cache/SceneForwardClusteredShaderRD"

var world: Node
var probe: Node
var known := {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		print("SHADER_MAP precisa de janela e --no-save")
		quit(2)
		return
	var target := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--target="): target = arg.trim_prefix("--target=")
	# Porto, perto da rota "oeste" da bancada fria onde o pico apareceu.
	var folder_fixture := FIXTURE.output_dir("shader-map-save")
	var save_path := FIXTURE.write_fixture(folder_fixture, "save.json", FIXTURE.full_snapshot(Vector3(300,.08,-742), true))
	# --watch (com os argumentos --benchmark... da bancada fria): a sonda acompanha o jogo rodando e, a cada arquivo
	# novo, imprime os materiais vistos pela primeira vez nos 3 quadros anteriores (SHADER_PROBE).
	if "--watch" in OS.get_cmdline_user_args():
		var watcher := PROBE.new()
		watcher.cache_dir = CACHE_DIR
		watcher.name = "ShaderFirstUseProbe"
		root.add_child(watcher)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline and (world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled): await physics_frame
	if world.session.modal: world.session.close_menu()
	root.gui_disable_input = true
	for node in world.find_children("*", "Node", true, false):
		node.set_process_input(false)
		node.set_process_unhandled_input(false)
	for frame in 30: await process_frame
	# A bancada sai sozinha quando acaba; o mapa por quad fica para a rodada sem --watch.
	if "--watch" in OS.get_cmdline_user_args(): return
	probe = PROBE.new()
	for key in _keys(): known[key] = "carga"
	var during_load := known.size()
	var materials := {}
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if node is SpriteBase3D or node is Label3D: continue
		for material in probe._materials(node):
			if not material is Material or material is ParticleProcessMaterial: continue
			var signature: String = probe._signature(material, node)
			if not materials.has(signature): materials[signature] = [material, node]
	print("SHADER_MAP carga=%d materiais=%d" % [during_load, materials.size()])
	var camera := root.get_viewport().get_camera_3d()
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5)
	quad.mesh = mesh
	quad.extra_cull_margin = 4.0
	world.add_child(quad)
	var mapped := {}
	var count := 0
	for signature in materials:
		var item: Array = materials[signature]
		if not is_instance_valid(item[1]): continue
		camera = root.get_viewport().get_camera_3d()
		if camera != null: quad.global_transform = camera.global_transform.translated_local(Vector3(0, 0, -1.2))
		quad.material_override = item[0]
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		count += 1
		for key in _keys():
			if known.has(key): continue
			var sample: Dictionary = probe._describe(item[1], item[0])
			sample.signature = signature
			known[key] = sample
			mapped[key] = sample
			print("SHADER_MAP ", key, " ", JSON.stringify(sample))
			if not target.is_empty() and key.contains(target.left(16)): print("SHADER_MAP_TARGET ", key, " ", JSON.stringify(sample))
	quad.queue_free()
	var folder := ProjectSettings.globalize_path("res://evidence/shader-map")
	DirAccess.make_dir_recursive_absolute(folder)
	var report := {"loaded_versions": during_load, "materials": materials.size(), "drawn": count, "mapped": mapped,
		"scope": "Material isolado num quad depois da carga; materiais criados só no tiro, na explosão ou por unidades que ainda não nasceram não entram."}
	FileAccess.open(folder.path_join("shader-map-%s.json" % Time.get_datetime_string_from_system().replace(":", "")), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SHADER_MAP desenhados=%d novos=%d" % [count, mapped.size()])
	quit(0)

## Chave como no StallLog: <hash das definições>/<hash do código>, sem extensão.
func _keys() -> PackedStringArray:
	var result: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(CACHE_DIR): return result
	for group in DirAccess.get_directories_at(CACHE_DIR):
		for file in DirAccess.get_files_at(CACHE_DIR.path_join(group)):
			result.append(group.left(12) + "/" + file.get_basename().get_basename())
	return result
