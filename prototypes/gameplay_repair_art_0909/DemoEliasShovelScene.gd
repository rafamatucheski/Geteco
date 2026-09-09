extends Node3D

## Demonstração comparativa e articulada de:
## 1. Elias (o contador de histórias): roupa exclusiva, boina, óculos, barba e poses (Wait, Talk, Walk, Inspect).
## 2. Coveiro com a Pá 3D: ancoragem correta na mão, sem flutuação, em 3 poses (Hold, Carry sem clipping e Dig).
## Suporte a visão aproximada e câmera na escala real de gameplay.

const ELIAS_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/EliasStorytellerModel.gd")
const WORKER_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/CemeteryWorkerModel.gd")
const GRAVE_SITE_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/GraveSiteVisual.gd")

var elias: Node3D
var worker: Node3D

var cam_gameplay: Camera3D
var cam_closeup: Camera3D
var active_cam_mode := 1

var canvas_layer: CanvasLayer
var status_label: Label
var btn_elias_pose: Button
var btn_worker_pose: Button
var btn_walk_toggle: Button
var btn_cam_toggle: Button

var is_walking := false

func _ready() -> void:
	_setup_lighting()
	_setup_environment()
	_setup_actors()
	_setup_cameras()
	_build_hud()

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color("#17201c")
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color("#6c7570")
	env.environment = env_res
	add_child(env)

func _setup_environment() -> void:
	var mat_grass := StandardMaterial3D.new()
	mat_grass.albedo_color = Color("#253629")
	mat_grass.roughness = 0.95

	var ground := _create_box(Vector3(12.0, 0.2, 12.0), mat_grass)
	ground.position = Vector3(0.0, -0.1, 0.0)
	add_child(ground)

	var mat_path := StandardMaterial3D.new()
	mat_path.albedo_color = Color("#585d58")
	var path := _create_box(Vector3(1.8, 0.02, 12.0), mat_path)
	path.position = Vector3(0.0, 0.01, 0.0)
	add_child(path)

	var grave: Node3D = GRAVE_SITE_SCRIPT.new()
	grave.position = Vector3(-1.8, 0.0, -2.5)
	grave.set_state(3) # State.COMPLETED
	add_child(grave)

func _setup_actors() -> void:
	elias = ELIAS_SCRIPT.new()
	elias.name = "EliasStoryteller"
	elias.position = Vector3(-1.1, 0.0, 0.0)
	elias.rotation_degrees = Vector3(0.0, 172.0, 0.0)
	add_child(elias)

	worker = WORKER_SCRIPT.new()
	worker.name = "CemeteryWorker"
	worker.position = Vector3(1.1, 0.0, 0.0)
	worker.rotation_degrees = Vector3(0.0, 188.0, 0.0)
	add_child(worker)

func _setup_cameras() -> void:
	cam_closeup = Camera3D.new()
	cam_closeup.name = "CamCloseup"
	cam_closeup.position = Vector3(0.0, 1.4, 2.6)
	cam_closeup.fov = 40.0
	add_child(cam_closeup)
	cam_closeup.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)

	cam_gameplay = Camera3D.new()
	cam_gameplay.name = "CamGameplay"
	cam_gameplay.position = Vector3(0.0, 7.5, 6.2)
	cam_gameplay.fov = 38.0
	add_child(cam_gameplay)
	cam_gameplay.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

	cam_closeup.current = true

func _build_hud() -> void:
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)

	var panel := Panel.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(500, 175)
	canvas_layer.add_child(panel)

	var title := Label.new()
	title.text = "DEMONSTRAÇÃO 2: ELIAS (CONTADOR) VS. COVEIRO E PÁ 3D"
	title.position = Vector2(15, 10)
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)

	status_label = Label.new()
	status_label.text = "Elias: WAIT (Espera contemplativa) | Coveiro: HOLD (Pá ao lado do corpo sem atravessar o chão)"
	status_label.position = Vector2(15, 36)
	status_label.size = Vector2(470, 48)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("#f1c40f"))
	panel.add_child(status_label)

	btn_elias_pose = Button.new()
	btn_elias_pose.text = "Elias: Pose"
	btn_elias_pose.position = Vector2(15, 95)
	btn_elias_pose.size = Vector2(110, 32)
	btn_elias_pose.pressed.connect(_cycle_elias_pose)
	panel.add_child(btn_elias_pose)

	btn_worker_pose = Button.new()
	btn_worker_pose.text = "Pá: Pose"
	btn_worker_pose.position = Vector2(135, 95)
	btn_worker_pose.size = Vector2(110, 32)
	btn_worker_pose.pressed.connect(_cycle_worker_pose)
	panel.add_child(btn_worker_pose)

	btn_walk_toggle = Button.new()
	btn_walk_toggle.text = "Marcha: OFF"
	btn_walk_toggle.position = Vector2(255, 95)
	btn_walk_toggle.size = Vector2(100, 32)
	btn_walk_toggle.pressed.connect(_toggle_walk)
	panel.add_child(btn_walk_toggle)

	btn_cam_toggle = Button.new()
	btn_cam_toggle.text = "Câmera (Close-up)"
	btn_cam_toggle.position = Vector2(365, 95)
	btn_cam_toggle.size = Vector2(120, 32)
	btn_cam_toggle.pressed.connect(_toggle_camera)
	panel.add_child(btn_cam_toggle)

	var note := Label.new()
	note.text = "Proposta de Rota: Coveiro entra a pé pelo portão norte e caminha até o lote lateral. Sem spawn aéreo."
	note.position = Vector2(15, 138)
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color("#bdc3c7"))
	panel.add_child(note)

func _cycle_elias_pose() -> void:
	var next_p: int = (int(elias.get("current_pose")) + 1) % 4
	elias.set_pose(next_p)
	_update_hud_status()

func _cycle_worker_pose() -> void:
	var next_p: int = (int(worker.get("current_pose")) + 1) % 3
	worker.set_worker_pose(next_p)
	_update_hud_status()

func _toggle_walk() -> void:
	is_walking = not is_walking
	btn_walk_toggle.text = "Marcha: ON" if is_walking else "Marcha: OFF"
	elias.set("walking", is_walking)
	worker.set("walking", is_walking)
	_update_hud_status()

func _toggle_camera() -> void:
	active_cam_mode = (active_cam_mode + 1) % 2
	if active_cam_mode == 0:
		cam_gameplay.current = true
		btn_cam_toggle.text = "Câmera (Gameplay)"
	else:
		cam_closeup.current = true
		btn_cam_toggle.text = "Câmera (Close-up)"

func _update_hud_status() -> void:
	var elias_names := ["WAIT (Espera)", "TALK (Narrando com gestos)", "WALK (Caminhando)", "INSPECT (Inspecionando lápide)"]
	var worker_names := ["HOLD (Segurar em repouso)", "CARRY (Carregar no ombro sem tocar chão)", "DIG (Cavar)"]
	var march_str := " | Marcha: Ativa" if is_walking else ""
	var ep: int = int(elias.get("current_pose"))
	var wp: int = int(worker.get("current_pose"))
	status_label.text = "Elias: " + elias_names[ep] + " | Pá: " + worker_names[wp] + march_str

func _process(delta: float) -> void:
	if is_walking:
		worker.update_animation(delta, true)

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi
