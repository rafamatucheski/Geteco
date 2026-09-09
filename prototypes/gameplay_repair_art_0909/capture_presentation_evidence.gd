extends SceneTree

## Captura evidencias visuais em alta definicao de Presentation Streaming,
## Isolamento de Materiais e Reciclagem de Rigs sob Vulkan Real.

const DEMO_SCENE := preload("res://prototypes/gameplay_repair_art_0909/DemoPresentationStreamingScene.gd")

var demo: DemoPresentationStreamingScene
var step: int = 0
var timer: float = 0.0

func _init() -> void:
	print("Iniciando captura de evidencias visuais em Vulkan Real...")
	call_deferred("_setup_scene")

func _setup_scene() -> void:
	demo = DEMO_SCENE.new()
	root.add_child(demo)
	call_deferred("_capture_loop")

func _capture_loop() -> void:
	# Aguarda 3 frames para estabilizar renderizacao Vulkan
	for i in range(3):
		await process_frame

	# FASE 1: Captura os atores em modo diferido (silhuetas proxy leves)
	print("Capturando: streaming_01_deferred_silhouettes.png...")
	_save_screenshot("res://prototypes/gameplay_repair_art_0909/captures/streaming_01_deferred_silhouettes.png")

	# FASE 2: Monta todos os rigs via ensure_presentation()
	for actor in demo.actors:
		actor.ensure_presentation()
	for i in range(3):
		await process_frame

	print("Capturando: streaming_02_transition_ready.png...")
	_save_screenshot("res://prototypes/gameplay_repair_art_0909/captures/streaming_02_transition_ready.png")

	# FASE 3: Teste de Isolamento de Materiais (Danifica Ator 0, mantém Ator 3 intacto)
	var isolation_res: Dictionary = demo.trigger_damage_isolation_test()
	print("Resultado de Isolamento: ", isolation_res)
	demo.camera.position = Vector3(-2.6, 1.8, 3.2)
	demo.camera.rotation_degrees = Vector3(-12.0, -15.0, 0.0)
	for i in range(3):
		await process_frame

	print("Capturando: streaming_03_material_isolation.png...")
	_save_screenshot("res://prototypes/gameplay_repair_art_0909/captures/streaming_03_material_isolation.png")

	# FASE 4: Teste de Reciclagem (Reseta Ator 0 para repouso e material original)
	var recycle_res: Dictionary = demo.trigger_recycle_test()
	print("Resultado de Reciclagem: ", recycle_res)
	for i in range(3):
		await process_frame

	print("Capturando: streaming_04_recycled_reset.png...")
	_save_screenshot("res://prototypes/gameplay_repair_art_0909/captures/streaming_04_recycled_reset.png")

	print("\nTodas as evidencias visuais foram gravadas com sucesso!")
	quit(0)

func _save_screenshot(target_path: String) -> void:
	var viewport := root.get_viewport()
	var img: Image = viewport.get_texture().get_image()
	var global_path := ProjectSettings.globalize_path(target_path)
	var dir := global_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(global_path)
	if err == OK:
		print("  Salvo: %s" % global_path)
	else:
		printerr("  Erro ao salvar: %d" % err)