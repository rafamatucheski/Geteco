extends Node3D

## Demonstração interativa da retirada policial do motorista (Entrega 3).
## Demonstra:
##   - Abordagem à porta do motorista (esquerda) ou passageiro (direita)
##   - Abertura suave da porta articulada do veículo
##   - Alcance e condução de Dante para fora do carro
##   - Algemamento com postura defensiva e aplicação de algemas
##   - Interrupção imediata a qualquer momento (rollback seguro com fechamento de porta e pose tática)
##   - Visualização em close-up e na escala da câmera de gameplay

const EXTRACTION_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/PoliceDriverExtraction.gd")
const RIG_FACTORY := preload("res://prototypes/gameplay_repair_art_0909/ExtractionDemoRigFactory.gd")

var extraction: Node3D
var vehicle: Node3D
var door_left: Node3D
var door_right: Node3D
var officer: Node3D
var dante: Node3D

var cam_gameplay: Camera3D
var cam_closeup: Camera3D
var active_cam_mode := 1

var canvas_layer: CanvasLayer
var status_label: Label
var btn_extract_left: Button
var btn_extract_right: Button
var btn_interrupt: Button
var btn_reset: Button
var btn_cam: Button

func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_extraction()
	_setup_cameras()
	_build_hud()

func _setup_environment() -> void:
	var mat_road := StandardMaterial3D.new()
	mat_road.albedo_color = Color("#222426")
	mat_road.roughness = 0.85

	var road := _create_box(Vector3(12.0, 0.2, 14.0), mat_road)
	road.position = Vector3(0.0, -0.1, 0.0)
	add_child(road)

	var mat_sidewalk := StandardMaterial3D.new()
	mat_sidewalk.albedo_color = Color("#55595c")
	mat_sidewalk.roughness = 0.80

	var sidewalk := _create_box(Vector3(3.2, 0.35, 14.0), mat_sidewalk)
	sidewalk.position = Vector3(-4.5, 0.05, 0.0)
	add_child(sidewalk)

	var mat_stripe := StandardMaterial3D.new()
	mat_stripe.albedo_color = Color("#d8d5ca")
	mat_stripe.roughness = 0.60

	for z in [-4.0, 0.0, 4.0]:
		var stripe := _create_box(Vector3(0.18, 0.01, 1.8), mat_stripe)
		stripe.position = Vector3(2.5, 0.01, z)
		add_child(stripe)

func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 40.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color("#12151a")
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color("#626a75")
	env.environment = env_res
	add_child(env)

func _setup_extraction() -> void:
	var car_data: Dictionary = RIG_FACTORY.build_muscle_car()
	vehicle = car_data["vehicle"]
	door_left = car_data["door_left"]
	door_right = car_data["door_right"]
	add_child(vehicle)

	officer = RIG_FACTORY.build_police_officer()
	add_child(officer)

	dante = RIG_FACTORY.build_dante_character()
	add_child(dante)

	extraction = EXTRACTION_SCRIPT.new()
	extraction.name = "PoliceExtraction"
	add_child(extraction)
	extraction.bind_actors(dante, officer, vehicle, door_left, door_right)

	extraction.extraction_started.connect(func(side: float):
		var side_str := "Porta Esquerda (Motorista)" if side < 0 else "Porta Direita (Passageiro)"
		_set_status("Abordagem iniciada: " + side_str + ". Policial avançando...")
	)
	extraction.door_opened.connect(func(_side: float):
		_set_status("Porta aberta pelo policial. Ordenando saída do motorista...")
	)
	extraction.driver_extracted.connect(func():
		_set_status("Motorista Dante retirado do habitáculo com firmeza para o solo exterior.")
	)
	extraction.suspect_handcuffed.connect(func():
		_set_status("Suspeito dominado de costas para o veículo. Algemas de aço acopladas.")
	)
	extraction.sequence_completed.connect(func():
		_set_status("Prisão e retirada concluídas com sucesso. Pronto para novo teste.")
	)
	extraction.extraction_interrupted.connect(func(reason: String):
		_set_status("INTERRUPÇÃO: " + reason)
	)

func _setup_cameras() -> void:
	cam_closeup = Camera3D.new()
	cam_closeup.name = "CamCloseup"
	cam_closeup.position = Vector3(-2.2, 1.45, -1.2)
	cam_closeup.fov = 42.0
	add_child(cam_closeup)
	cam_closeup.look_at(Vector3(-0.6, 0.85, 0.2), Vector3.UP)

	cam_gameplay = Camera3D.new()
	cam_gameplay.name = "CamGameplay"
	cam_gameplay.position = Vector3(0.0, 9.2, 7.5)
	cam_gameplay.fov = 38.0
	add_child(cam_gameplay)
	cam_gameplay.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

	cam_closeup.current = true

func _build_hud() -> void:
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)

	var panel := Panel.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(520, 165)
	canvas_layer.add_child(panel)

	var title := Label.new()
	title.text = "DEMONSTRAÇÃO 3: RETIRADA POLICIAL DO MOTORISTA"
	title.position = Vector2(15, 10)
	title.add_theme_font_size_override("font_size", 14)
	panel.add_child(title)

	status_label = Label.new()
	status_label.text = "Status: Aguardando comando. Escolha a porta para iniciar a abordagem."
	status_label.position = Vector2(15, 36)
	status_label.size = Vector2(490, 45)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("#f1c40f"))
	panel.add_child(status_label)

	btn_extract_left = Button.new()
	btn_extract_left.text = "Retirar (Motorista / Esq)"
	btn_extract_left.position = Vector2(15, 95)
	btn_extract_left.size = Vector2(155, 32)
	btn_extract_left.pressed.connect(func():
		cam_closeup.position = Vector3(-2.2, 1.45, -1.2)
		cam_closeup.look_at(Vector3(-0.6, 0.85, 0.2), Vector3.UP)
		extraction.start_extraction(-1.0)
	)
	panel.add_child(btn_extract_left)

	btn_extract_right = Button.new()
	btn_extract_right.text = "Retirar (Passageiro / Dir)"
	btn_extract_right.position = Vector2(180, 95)
	btn_extract_right.size = Vector2(160, 32)
	btn_extract_right.pressed.connect(func():
		cam_closeup.position = Vector3(2.2, 1.45, -1.2)
		cam_closeup.look_at(Vector3(0.6, 0.85, 0.2), Vector3.UP)
		extraction.start_extraction(1.0)
	)
	panel.add_child(btn_extract_right)

	btn_interrupt = Button.new()
	btn_interrupt.text = "Interromper"
	btn_interrupt.position = Vector2(350, 95)
	btn_interrupt.size = Vector2(90, 32)
	btn_interrupt.pressed.connect(func(): extraction.interrupt_extraction())
	panel.add_child(btn_interrupt)

	btn_reset = Button.new()
	btn_reset.text = "Reset"
	btn_reset.position = Vector2(450, 95)
	btn_reset.size = Vector2(55, 32)
	btn_reset.pressed.connect(func(): extraction.reset_poses())
	panel.add_child(btn_reset)

	btn_cam = Button.new()
	btn_cam.text = "Alternar Câmera (Close-up / Gameplay)"
	btn_cam.position = Vector2(15, 132)
	btn_cam.size = Vector2(250, 24)
	btn_cam.add_theme_font_size_override("font_size", 10)
	btn_cam.pressed.connect(_toggle_camera)
	panel.add_child(btn_cam)

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = "Status: " + msg

func _toggle_camera() -> void:
	active_cam_mode = (active_cam_mode + 1) % 2
	if active_cam_mode == 0:
		cam_gameplay.current = true
		btn_cam.text = "Câmera Ativa: Gameplay"
	else:
		cam_closeup.current = true
		btn_cam.text = "Câmera Ativa: Close-up"

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi
