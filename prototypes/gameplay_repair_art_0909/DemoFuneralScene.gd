extends Node3D

## Demonstração interativa do funeral completo:
## Cortejo dos 4 carregadores + Caixão 3D -> Cerimônia com espera solene ->
## Descida suave do caixão -> Coveiro cobrindo com a pá -> Conclusão e dispersão.
## Mantém o corredor central desobstruído e limpa todos os nós ao fim.

const FUNERAL_CTRL_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/FuneralSequenceController.gd")
const WORKER_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/CemeteryWorkerModel.gd")

var controller: Node3D
var worker: Node3D

var cam_gameplay: Camera3D
var cam_closeup: Camera3D
var active_cam_mode := 0

var canvas_layer: CanvasLayer
var status_label: Label
var btn_start: Button
var btn_cancel: Button
var btn_repeat: Button
var btn_cam: Button

func _ready() -> void:
	_build_cemetery_ground()
	_setup_lighting()
	_setup_cameras()
	_setup_controller()
	_build_hud()

func _build_cemetery_ground() -> void:
	var mat_grass := StandardMaterial3D.new()
	mat_grass.albedo_color = Color("#223326")
	mat_grass.roughness = 0.95

	var ground := _create_box(Vector3(18.0, 0.2, 24.0), mat_grass)
	ground.position = Vector3(0.0, -0.1, 0.0)
	add_child(ground)

	var mat_path := StandardMaterial3D.new()
	mat_path.albedo_color = Color("#555955")
	mat_path.roughness = 0.80

	var path := _create_box(Vector3(2.2, 0.02, 24.0), mat_path)
	path.position = Vector3(0.0, 0.01, 0.0)
	add_child(path)

	var mat_wall := StandardMaterial3D.new()
	mat_wall.albedo_color = Color("#424744")
	mat_wall.roughness = 0.85

	var wall_l := _create_box(Vector3(7.2, 0.9, 0.35), mat_wall)
	wall_l.position = Vector3(-4.9, 0.45, -8.5)
	add_child(wall_l)

	var wall_r := _create_box(Vector3(7.2, 0.9, 0.35), mat_wall)
	wall_r.position = Vector3(4.9, 0.45, -8.5)
	add_child(wall_r)

	for s in [-1.3, 1.3]:
		var post := _create_box(Vector3(0.45, 1.3, 0.45), mat_wall)
		post.position = Vector3(s, 0.65, -8.5)
		add_child(post)

	var mat_pine := StandardMaterial3D.new()
	mat_pine.albedo_color = Color("#1e3025")
	mat_pine.roughness = 0.90

	for z in [-6.0, -1.0, 4.0]:
		for s in [-6.5, 6.5]:
			var tree_trunk := _create_cylinder(0.18, 1.4, mat_wall)
			tree_trunk.position = Vector3(s, 0.7, z)
			add_child(tree_trunk)

			var tree_crown := _create_cylinder(0.9, 3.2, mat_pine)
			tree_crown.position = Vector3(s, 2.8, z)
			add_child(tree_crown)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color("#18201a")
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color("#606b65")
	env.environment = env_res
	add_child(env)

func _setup_cameras() -> void:
	cam_gameplay = Camera3D.new()
	cam_gameplay.name = "CamGameplay"
	cam_gameplay.position = Vector3(1.2, 9.5, 8.2)
	cam_gameplay.fov = 42.0
	add_child(cam_gameplay)
	cam_gameplay.look_at(Vector3(1.5, 0.0, 0.0), Vector3.UP)

	cam_closeup = Camera3D.new()
	cam_closeup.name = "CamCloseup"
	cam_closeup.position = Vector3(3.4, 2.2, 4.5)
	cam_closeup.fov = 48.0
	add_child(cam_closeup)
	cam_closeup.look_at(Vector3(3.4, 0.4, 0.0), Vector3.UP)

	cam_gameplay.current = true

func _setup_controller() -> void:
	controller = FUNERAL_CTRL_SCRIPT.new()
	controller.name = "FuneralController"
	add_child(controller)

	worker = WORKER_SCRIPT.new()
	worker.name = "GravediggerWorker"
	add_child(worker)
	controller.set_gravedigger(worker)

	controller.sequence_started.connect(func(): _set_status("Cortejo iniciando pelo corredor central..."))
	controller.procession_arrived.connect(func(): _set_status("Cortejo chegou ao lote lateral. Caixão posicionado sobre a cova."))
	controller.ceremony_started.connect(func(): _set_status("Cerimônia em andamento (corredor livre)..."))
	controller.lowering_started.connect(func(): _set_status("Descida do caixão para dentro da cavidade..."))
	controller.lowering_completed.connect(func(): _set_status("Caixão repousado no fundo da cova."))
	controller.filling_started.connect(func(): _set_status("Coveiro cobrindo a sepultura com a pá..."))
	controller.filling_completed.connect(func(): _set_status("Sepultura concluída! Montículo formado com cruz e flores."))
	controller.dispersal_started.connect(func(): _set_status("Dispersão solene em direção à saída..."))
	controller.sequence_completed.connect(func(): _set_status("Ciclo finalizado. Atores limpos com sucesso. Pronto para repetir."))
	controller.sequence_cancelled.connect(func(): _set_status("Ciclo cancelado. Recursos restaurados com segurança."))

func _build_hud() -> void:
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)

	var panel := Panel.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(460, 160)
	canvas_layer.add_child(panel)

	var title := Label.new()
	title.text = "DEMONSTRAÇÃO 1: FUNERAL COMPLETO E COVA DINÂMICA"
	title.position = Vector2(15, 10)
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)

	status_label = Label.new()
	status_label.text = "Status: Aguardando início da demonstração."
	status_label.position = Vector2(15, 36)
	status_label.size = Vector2(430, 45)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("#f1c40f"))
	panel.add_child(status_label)

	btn_start = Button.new()
	btn_start.text = "Iniciar Ciclo"
	btn_start.position = Vector2(15, 95)
	btn_start.size = Vector2(100, 32)
	btn_start.pressed.connect(func(): controller.start_sequence())
	panel.add_child(btn_start)

	btn_cancel = Button.new()
	btn_cancel.text = "Cancelar"
	btn_cancel.position = Vector2(125, 95)
	btn_cancel.size = Vector2(85, 32)
	btn_cancel.pressed.connect(func(): controller.cancel_sequence())
	panel.add_child(btn_cancel)

	btn_repeat = Button.new()
	btn_repeat.text = "Repetir"
	btn_repeat.position = Vector2(220, 95)
	btn_repeat.size = Vector2(85, 32)
	btn_repeat.pressed.connect(func():
		controller.cancel_sequence()
		controller.start_sequence()
	)
	panel.add_child(btn_repeat)

	btn_cam = Button.new()
	btn_cam.text = "Câmera (Gameplay)"
	btn_cam.position = Vector2(315, 95)
	btn_cam.size = Vector2(130, 32)
	btn_cam.pressed.connect(_toggle_camera)
	panel.add_child(btn_cam)

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = "Status: " + msg

func _toggle_camera() -> void:
	active_cam_mode = (active_cam_mode + 1) % 2
	if active_cam_mode == 0:
		cam_gameplay.current = true
		btn_cam.text = "Câmera (Gameplay)"
	else:
		cam_closeup.current = true
		btn_cam.text = "Câmera (Close-up)"

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi

func _create_cylinder(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 2
	mi.mesh = cyl
	mi.material_override = mat
	return mi
