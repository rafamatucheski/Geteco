extends Node
## Carrega a sessão escolhida só depois do clique, sob a tela de carregamento opaca.
signal boot_finished
signal released
const MAIN := "res://Main.tscn"
const CURTAIN := preload("res://runtime/StartupCurtain.gd")
var menu: Control
var world: Node3D
var is_ready := false
var loading := false
var transferred := false
var failed := false
var continuing := false
var preview_path := ""
var preview_fingerprint := ""
var ui_layer: CanvasLayer
var loading_cover: Control
var curtain: CanvasLayer
var held_nodes: Array[Dictionary] = []
var hidden_layers: Array[CanvasLayer] = []
var reveal: Tween

func install(source: Control) -> void:
	menu = source
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 126
	menu.add_child(ui_layer)
	for child in menu.get_children():
		if child is Control: child.reparent(ui_layer)
	loading_cover = menu.presentation.background
	set_process(false)
	# Listar saves não pode instanciar nem aquecer o mundo atrás de um menu ocioso.
	# O MainMenu só inicia boot_path depois que begin_continue cobriu a interface.

static func fingerprint(path: String) -> String:
	var result := ""
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): result += FileAccess.get_sha256(path + suffix)
	return result

func boot_path(path: String) -> void:
	if loading or is_ready: return
	loading = true
	failed = false
	preview_path = path
	preview_fingerprint = fingerprint(path)
	var packed: PackedScene
	if DisplayServer.get_name() == "headless":
		# Dummy rendering cannot safely preload shared UI resources on a worker.
		packed = load(MAIN)
	else:
		var error := ResourceLoader.load_threaded_request(MAIN)
		if error != OK:
			_boot_failed()
			return
		while ResourceLoader.load_threaded_get_status(MAIN) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(MAIN) == ResourceLoader.THREAD_LOAD_LOADED:
			packed = ResourceLoader.load_threaded_get(MAIN)
	if packed == null:
		_boot_failed()
		return
	# Termina a transferência da arte imutável antes que construtores possam travar o motor.
	if is_instance_valid(curtain): await curtain.prepare_presentation()
	world = packed.instantiate()
	world.set_meta("menu_preview", self)
	world.set_meta("menu_save_path", path)
	get_tree().root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _boot_failed() -> void:
	loading = false
	failed = true
	boot_finished.emit()

## Faz o fade da capa estática de carregamento antes de esconder os controles do menu.
func begin_continue() -> void:
	if continuing: return
	continuing = true
	var focused := menu.get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	curtain = CURTAIN.new()
	add_child(curtain)
	curtain.layer = 127
	curtain.set_stage(.04, "Carregando…")
	curtain._root.modulate.a = 0.0
	await curtain.prepare_presentation()
	reveal = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	reveal.tween_property(curtain._root, "modulate:a", 1.0, .35)
	var music := menu.get_node_or_null("MenuMusic")
	if music != null: reveal.tween_property(music, "volume_db", -40.0, .35)
	set_process(true)
	await reveal.finished
	if not continuing: return
	loading_cover = curtain._root
	ui_layer.hide()

func cancel_continue() -> void:
	continuing = false
	if reveal != null: reveal.kill()
	if is_instance_valid(curtain): curtain.queue_free()
	curtain = null
	ui_layer.show()
	loading_cover = menu.presentation.background
	set_process(false)

## Restoration/population finish first; simulation stays frozen until fade-out.
func hold_world(scene: Node3D) -> void:
	world = scene
	while _vehicle_restore_pending():
		await get_tree().physics_frame
	world.camera._process(0.0)
	_hold_always_nodes(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true
	for region in world.production.regions.values():
		while not region.is_streaming_idle():
			region._process(0.0)
			await get_tree().process_frame
	world.player.controlled_automatically = false
	world.reset_physics_interpolation()
	world.camera.make_current()
	# Aquece a câmera salva real sob uma capa opaca e depois para o desenho escondido.
	for i in 3: await get_tree().process_frame
	world.hide()
	loading = false
	is_ready = true
	boot_finished.emit()
	await released

func _vehicle_restore_pending() -> bool:
	if world.driving.is_body_transition_active(): return true
	for car in world.production.vehicles:
		if is_instance_valid(car) and car.get_meta("garage_driver_pending", false): return true
	return false

func _hold_always_nodes(node: Node) -> void:
	for child in node.get_children():
		if child.process_mode in [Node.PROCESS_MODE_ALWAYS, Node.PROCESS_MODE_WHEN_PAUSED]:
			held_nodes.append({"node": child, "mode": child.process_mode})
			child.process_mode = Node.PROCESS_MODE_DISABLED
		if child is CanvasLayer and child.visible:
			hidden_layers.append(child)
			child.hide()
		_hold_always_nodes(child)

func _process(_delta: float) -> void:
	if not is_instance_valid(curtain) or not is_instance_valid(world): return
	var progress = world.get_node_or_null("LoadingCurtain")
	if progress != null:
		curtain.set_stage(progress._target, progress.stage_message if not is_ready else "Pronto")

func continue_game() -> bool:
	begin_continue()
	if loading: await boot_finished
	if failed or not is_ready: return false
	if reveal != null and reveal.is_running(): await reveal.finished
	world.show()
	world.camera.make_current()
	for i in 3: await get_tree().process_frame
	set_process(false)
	var progress = world.get_node_or_null("LoadingCurtain")
	if progress != null: progress.queue_free()
	for layer in hidden_layers:
		if is_instance_valid(layer) and layer != progress: layer.show()
	# O fade revela a câmera exata do jogo; os controles ficam travados até ele acabar.
	await curtain.lift(0)
	for entry in held_nodes:
		if is_instance_valid(entry.node): entry.node.process_mode = entry.mode
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.production.no_save = "--no-save" in OS.get_cmdline_user_args()
	world.remove_meta("menu_preview")
	world.remove_meta("menu_save_path")
	transferred = true
	get_tree().current_scene = world
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	released.emit()
	menu.queue_free()
	return true

func discard_preview() -> void:
	if loading: await boot_finished
	if is_instance_valid(world):
		world.queue_free()
		released.emit()
		world = null
	get_tree().paused = false
	is_ready = false
	held_nodes.clear()
	hidden_layers.clear()
	await get_tree().process_frame

func _exit_tree() -> void:
	if not transferred and is_instance_valid(world):
		world.queue_free()
		get_tree().paused = false
