class_name ChopShopCrusher3D
extends SubViewportContainer

## Janela de cutscene 3D do desmanche: um eletroímã pega o carro, leva até a
## prensa e esmaga na frente do jogador. É o único momento com 3D "de
## verdade" fora dos retratos de personagem — reaproveita o carro procedural
## de prototypes/living_cast (sem malha importada, mesma técnica já usada
## pelo resto do estúdio de veículos 3D do projeto).

signal finished()

const CAR_MODEL_SCRIPT := preload("res://prototypes/living_cast/RearEngineCoupe.gd")

var viewport: SubViewport
var camera: Camera3D
var car_model: Node3D
var magnet: Node3D
var _top_plate: MeshInstance3D
var _bottom_plate: MeshInstance3D

func _ready() -> void:
	custom_minimum_size = Vector2(520, 360)
	stretch = true

	viewport = SubViewport.new()
	viewport.size = Vector2i(520, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)

	camera = Camera3D.new()
	camera.position = Vector3(3.6, 2.5, 3.8)
	camera.fov = 42.0
	viewport.add_child(camera)
	camera.look_at(Vector3(0.4, 0.7, 0.0), Vector3.UP)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	key_light.light_energy = 1.3
	viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, -120.0, 0.0)
	fill_light.light_energy = 0.55
	fill_light.light_color = Color(0.6, 0.7, 0.85)
	viewport.add_child(fill_light)

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.03, 0.03, 0.04)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.22, 0.22, 0.24)
	env.environment = env_res
	viewport.add_child(env)

	_build_rig()

func _build_rig() -> void:
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(6.4, 0.1, 5.0)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0, -0.05, 0)
	floor_mesh.material_override = _make_mat("#2c2c2e", 0.2, 0.9)
	viewport.add_child(floor_mesh)

	var rail := MeshInstance3D.new()
	var rail_box := BoxMesh.new()
	rail_box.size = Vector3(6.0, 0.12, 0.12)
	rail.mesh = rail_box
	rail.position = Vector3(0, 2.6, 0)
	rail.material_override = _make_mat("#505459", 0.6, 0.4)
	viewport.add_child(rail)

	magnet = Node3D.new()
	viewport.add_child(magnet)
	magnet.position = Vector3(-1.9, 2.5, 0)

	var cable := MeshInstance3D.new()
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.02
	cable_mesh.bottom_radius = 0.02
	cable_mesh.height = 0.9
	cable.mesh = cable_mesh
	cable.position = Vector3(0, 0.45, 0)
	cable.material_override = _make_mat("#1a1a1a", 0.1, 0.8)
	magnet.add_child(cable)

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.55
	disc_mesh.bottom_radius = 0.55
	disc_mesh.height = 0.12
	disc.mesh = disc_mesh
	disc.material_override = _make_mat("#7f8c8d", 0.9, 0.3)
	magnet.add_child(disc)

	_top_plate = MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(1.7, 0.18, 1.7)
	_top_plate.mesh = plate_mesh
	_top_plate.position = Vector3(1.7, 2.35, 0)
	_top_plate.material_override = _make_mat("#636e72", 0.8, 0.45)
	viewport.add_child(_top_plate)

	_bottom_plate = MeshInstance3D.new()
	_bottom_plate.mesh = plate_mesh
	_bottom_plate.position = Vector3(1.7, 0.09, 0)
	_bottom_plate.material_override = _make_mat("#636e72", 0.8, 0.45)
	viewport.add_child(_bottom_plate)

	car_model = CAR_MODEL_SCRIPT.new()
	viewport.add_child(car_model)
	car_model.scale = Vector3.ONE * 0.42
	car_model.rotation.y = deg_to_rad(-30.0)
	car_model.position = Vector3(-1.9, 0.34, 0)

func _make_mat(hex: String, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.metallic = metallic
	m.roughness = roughness
	return m

## Sequência completa: pega, ergue, balança até a prensa, esmaga achatando
## o carro, some. Emite `finished` no final. ~3.5s.
func play_sequence() -> void:
	var tw := create_tween()
	# 1) Magneto desce até o carro e "gruda"
	tw.tween_property(magnet, "position:y", 0.90, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_attach_car_to_magnet)
	# 2) Sobe com o carro
	tw.tween_property(magnet, "position:y", 2.5, 0.55).set_trans(Tween.TRANS_SINE)
	# 3) Balança até a prensa
	tw.set_parallel(true)
	tw.tween_property(magnet, "position:x", 1.9, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(magnet, "rotation:z", deg_to_rad(7.0), 0.35).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(magnet, "rotation:z", deg_to_rad(-4.0), 0.40).set_trans(Tween.TRANS_SINE)
	# 4) Solta o carro na prensa
	tw.tween_callback(_release_car_onto_press)
	tw.tween_property(magnet, "position:y", 1.05, 0.25)
	# 5) A prensa fecha e achata o carro
	tw.set_parallel(true)
	tw.tween_property(_top_plate, "position:y", 0.56, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_bottom_plate, "position:y", 0.34, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if car_model:
		tw.tween_property(car_model, "scale:y", 0.10, 0.55)
		tw.tween_property(car_model, "scale:z", 0.68, 0.55)
		tw.tween_property(car_model, "position:y", 0.14, 0.55)
	tw.chain().tween_callback(_darken_car)
	tw.tween_interval(0.55)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): finished.emit())

func _attach_car_to_magnet() -> void:
	if not car_model or not is_instance_valid(car_model):
		return
	var global_pos := car_model.global_position
	car_model.reparent(magnet)
	car_model.global_position = global_pos

func _release_car_onto_press() -> void:
	if not car_model or not is_instance_valid(car_model):
		return
	car_model.reparent(viewport)
	car_model.position = Vector3(1.9, 0.34, 0)
	car_model.rotation.y = deg_to_rad(15.0)

func _darken_car() -> void:
	if car_model and is_instance_valid(car_model):
		_darken_node(car_model)

## Node3D não tem `modulate` — escurece direto nos materiais das peças.
## Cada CoupeModel instanciado tem seu próprio dicionário de materiais
## (não compartilhado entre instâncias), então mutar aqui é seguro.
func _darken_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := (node as MeshInstance3D).material_override
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_color = (mat as StandardMaterial3D).albedo_color.darkened(0.55)
	for child in node.get_children():
		_darken_node(child)
