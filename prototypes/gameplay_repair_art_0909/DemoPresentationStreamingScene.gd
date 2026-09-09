class_name DemoPresentationStreamingScene
extends Node3D

## Cena de demonstracao isolada de Carregamento sob Demanda (Presentation Streaming),
## Compartilhamento de Geometrias e Materiais Imutaveis, e Isolamento de Danos.

const MOURNER_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/StreamableMournerModel.gd")
const ELIAS_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/StreamableEliasModel.gd")
const WORKER_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/StreamableWorkerModel.gd")

var actors: Array[StreamableActorPresentation] = []
var stream_queue: Array[StreamableActorPresentation] = []
var stream_active: bool = false
var stream_interval: float = 0.12 # intervalo demonstrativo perceptivel
var stream_timer: float = 0.0

var hud_label: Label
var hud_status: Label
var camera: Camera3D

# Metricas instrumentadas
var last_build_time_ms: float = 0.0
var total_build_time_ms: float = 0.0
var builds_completed: int = 0

func _ready() -> void:
	_setup_environment()
	_setup_hud()
	spawn_actors_deferred()

func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color("#181a1d")
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color("#cfd6df")
	env_res.ambient_light_energy = 0.85
	env.environment = env_res
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	light.light_color = Color("#fff8ee")
	light.light_energy = 1.2
	add_child(light)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 3.2, 5.8)
	camera.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

	# Piso do cemiterio
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#222823")
	floor_mat.roughness = 0.95
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	hud_label = Label.new()
	hud_label.position = Vector2(24.0, 20.0)
	hud_label.text = "DEMONSTRACAO: PRESENTATION STREAMING SOB DEMANDA"
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color("#f0e6d2"))
	canvas.add_child(hud_label)

	hud_status = Label.new()
	hud_status.position = Vector2(24.0, 52.0)
	hud_status.text = "Iniciando..."
	hud_status.add_theme_font_size_override("font_size", 14)
	hud_status.add_theme_color_override("font_color", Color("#a0b2c6"))
	canvas.add_child(hud_status)

func spawn_actors_deferred() -> void:
	# Limpa atores anteriores se existirem
	for a in actors:
		if is_instance_valid(a):
			a.queue_free()
	actors.clear()
	stream_queue.clear()
	total_build_time_ms = 0.0
	builds_completed = 0

	# 1. Spawna 6 Mourners em fila (lado esquerdo X < 0)
	for i in range(6):
		var mourner: StreamableMournerModel = MOURNER_SCRIPT.new(0, i % 3, true)
		mourner.position = Vector3(-3.2 + (i % 3) * 1.3, 0.0, -1.2 + int(i / 3) * 1.8)
		add_child(mourner)
		actors.append(mourner)
		stream_queue.append(mourner)

	# 2. Spawna Coveiro com pa em diferido
	var worker: StreamableWorkerModel = WORKER_SCRIPT.new(true)
	worker.position = Vector3(1.6, 0.0, -0.6)
	worker.set_worker_pose(StreamableWorkerModel.WorkerPose.CARRY)
	add_child(worker)
	actors.append(worker)
	stream_queue.append(worker)

	# 3. Spawna Elias em diferido
	var elias: StreamableEliasModel = ELIAS_SCRIPT.new(true)
	elias.position = Vector3(3.2, 0.0, -0.6)
	elias.set_pose(StreamableEliasModel.Pose.TALK)
	add_child(elias)
	actors.append(elias)
	stream_queue.append(elias)

	_update_hud("Atores instanciados em modo diferido (Silhuetas ativas). Pressione [ESPACO] para iniciar streaming.")

func _process(delta: float) -> void:
	if stream_active and not stream_queue.is_empty():
		stream_timer += delta
		if stream_timer >= stream_interval:
			stream_timer = 0.0
			build_next_actor()

func build_next_actor() -> void:
	if stream_queue.is_empty():
		stream_active = false
		_update_hud("Streaming concluido! Todos os %d rigs montados. Total: %.2f ms (Media: %.2f ms/ator)." % [
			builds_completed, total_build_time_ms, total_build_time_ms / max(1, builds_completed)
		])
		return

	var actor: StreamableActorPresentation = stream_queue.pop_front()
	if is_instance_valid(actor):
		actor.ensure_presentation()
		last_build_time_ms = actor.build_duration_ms
		total_build_time_ms += last_build_time_ms
		builds_completed += 1

		_update_hud("Montando sob demanda: %d/%d concluídos. Último rig: %.2f ms. Fila restante: %d." % [
			builds_completed, actors.size(), last_build_time_ms, stream_queue.size()
		])

func trigger_start_streaming() -> void:
	stream_active = true
	stream_timer = stream_interval # Dispara o primeiro imediatamente

func trigger_damage_isolation_test() -> Dictionary:
	# Garante que todos estejam com rig montado
	for a in actors:
		a.ensure_presentation()

	# Aplica dano severo de sangue e fuligem no Mourner 0 (que usa suit variante 0)
	var mourner_0: StreamableMournerModel = actors[0] as StreamableMournerModel
	var mourner_3: StreamableMournerModel = actors[3] as StreamableMournerModel # Tambem usa suit variante 0!

	var pre_color_m3: Color = mourner_3.coat_mesh.material_override.albedo_color

	# Danifica Mourner 0
	mourner_0.apply_damage("blood", 1.0, "torso")
	var post_color_m0: Color = mourner_0.coat_mesh.material_override.albedo_color
	var post_color_m3: Color = mourner_3.coat_mesh.material_override.albedo_color

	var isolation_ok: bool = (post_color_m0 != post_color_m3) and (post_color_m3 == pre_color_m3)

	_update_hud("Teste de Isolamento de Material: %s (Mourner 0 danificado, Mourner 3 intacto)." % [
		"PASS" if isolation_ok else "FAIL"
	])

	return {
		"isolation_passed": isolation_ok,
		"mourner_0_color": post_color_m0,
		"mourner_3_color": post_color_m3,
		"pre_color": pre_color_m3
	}

func trigger_recycle_test() -> Dictionary:
	# Recicla Mourner 0
	var mourner_0: StreamableMournerModel = actors[0] as StreamableMournerModel
	mourner_0.recycle_presentation()

	var suit_restored: bool = (mourner_0.coat_mesh.material_override == ArtPresentationCache.get_suit_material(mourner_0.variant_index))
	var arms_restored: bool = (mourner_0.left_arm.rotation == Vector3.ZERO and mourner_0.right_arm.rotation == Vector3.ZERO)

	var recycle_ok: bool = suit_restored and arms_restored
	_update_hud("Teste de Reciclagem: %s (Dano limpo, material compartilhado restaurado, membros em repouso)." % [
		"PASS" if recycle_ok else "FAIL"
	])

	return {
		"recycle_passed": recycle_ok,
		"suit_restored": suit_restored,
		"arms_restored": arms_restored
	}

func _update_hud(msg: String) -> void:
	if hud_status != null:
		hud_status.text = msg

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			trigger_start_streaming()
		elif event.keycode == KEY_1:
			trigger_damage_isolation_test()
		elif event.keycode == KEY_2:
			trigger_recycle_test()
		elif event.keycode == KEY_R:
			spawn_actors_deferred()