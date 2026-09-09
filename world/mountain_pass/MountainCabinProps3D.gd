class_name MountainCabinProps3D
extends Node2D

## Renderizador de Props 3D para o Interior do Chale Alpino:
## Renderiza em tempo real malhas 3D com materiais PBR (madeira nobre, aco azulado,
## osso, ferro fundido, cobre polido e couro) via SubViewport top-down/isometrico,
## integrando-se nativamente ao ciclo de vida e renderizacao do Godot.

enum PropType {
	ANTLER_TROPHY,    ## Troféu de Cabeça de Cervo com Galhadas 3D
	GUN_RACK,         ## Suporte de Parede com Rifles de Caça e Luneta 3D
	CAST_IRON_STOVE,  ## Fogão/Lareira a Lenha de Ferro Fundido 3D com Chaleira de Cobre
	BEAR_RUG_HEAD,    ## Cabeça 3D de Urso Pardo Esculpida com Presas e Focinho
	RADIO_TRANSCEIVER ## Rádio Comunicador Militar/Florestal 3D com Antena e Dials
}

@export var prop_type: PropType = PropType.ANTLER_TROPHY
@export var viewport_size: Vector2i = Vector2i(160, 160)
@export var camera_ortho_size: float = 2.4
@export var camera_tilt_deg: float = 35.0

var viewport_3d: SubViewport
var sprite_display: Sprite2D
var prop_root: Node3D
var materials: Dictionary = {}

func _ready() -> void:
	_setup_3d_viewport()
	_build_prop_mesh()
	_setup_2d_display()

func _setup_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "PropViewport3D"
	viewport_3d.size = viewport_size
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport_3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.90, 0.82)
	env.ambient_light_energy = 1.3
	var world := viewport_3d.find_world_3d()
	if world:
		world.environment = env

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = camera_ortho_size
	# Posicionamento com inclinacao isometrica suave para ressaltar profundidade 3D
	viewport_3d.add_child(cam)
	var rad_tilt := deg_to_rad(camera_tilt_deg)
	cam.position = Vector3(0.0, 8.0, 8.0 * tan(rad_tilt))
	cam.rotation_degrees = Vector3(-90.0 + camera_tilt_deg, 0.0, 0.0)
	cam.current = true

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	key_light.light_color = Color(1.0, 0.96, 0.88)
	key_light.light_energy = 1.8
	viewport_3d.add_child(key_light)

	var warm_fill := DirectionalLight3D.new()
	warm_fill.rotation_degrees = Vector3(-20.0, -130.0, 0.0)
	warm_fill.light_color = Color(1.0, 0.65, 0.35)
	warm_fill.light_energy = 0.9
	viewport_3d.add_child(warm_fill)

	prop_root = Node3D.new()
	prop_root.name = "PropRoot"
	viewport_3d.add_child(prop_root)

func _setup_2d_display() -> void:
	sprite_display = Sprite2D.new()
	sprite_display.name = "PropSprite2D"
	sprite_display.texture = viewport_3d.get_texture()
	sprite_display.position = Vector2.ZERO
	add_child(sprite_display)

func _mat(key: String, color: Color, metallic: float = 0.0, roughness: float = 0.6, glow: float = 0.0) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	materials[key] = m
	return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi

func _build_prop_mesh() -> void:
	match prop_type:
		PropType.ANTLER_TROPHY:
			_build_antler_trophy()
		PropType.GUN_RACK:
			_build_gun_rack()
		PropType.CAST_IRON_STOVE:
			_build_cast_iron_stove()
		PropType.BEAR_RUG_HEAD:
			_build_bear_rug_head()
		PropType.RADIO_TRANSCEIVER:
			_build_radio_transceiver()

func _build_antler_trophy() -> void:
	var wood_plaque := _mat("plaque", Color("#3d2314"), 0.0, 0.45)
	var bone_mat := _mat("bone", Color("#e6dac8"), 0.1, 0.35)
	var antler_mat := _mat("antler", Color("#c4ab80"), 0.1, 0.5)
	var dark_antler := _mat("dark_antler", Color("#826848"), 0.05, 0.6)

	# 1. Escudo de madeira entalhada de fixação
	var plaque := _box(prop_root, Vector3(0.0, 0.0, -0.08), Vector3(0.70, 0.85, 0.08), wood_plaque)
	plaque.rotation_degrees.x = -15.0

	# 2. Crânio de cervo / ossatura
	var skull := _box(prop_root, Vector3(0.0, 0.08, 0.12), Vector3(0.26, 0.34, 0.30), bone_mat)
	var snout := _box(prop_root, Vector3(0.0, -0.12, 0.24), Vector3(0.18, 0.22, 0.32), bone_mat)
	snout.rotation_degrees.x = 22.0

	# 3. Galhadas 3D ramificadas (Hastes principais e pontas pontiagudas)
	for s in [-1.0, 1.0]:
		# Haste principal que sobe e curva para fora
		var main_beam := _cyl(prop_root, Vector3(s * 0.28, 0.42, 0.14), 0.038, 0.62, antler_mat)
		main_beam.rotation_degrees = Vector3(-12.0, s * 22.0, s * -35.0)

		# Ponta frontal (brow tine) apontando para a frente
		var brow_tine := _cyl(prop_root, Vector3(s * 0.20, 0.26, 0.30), 0.024, 0.30, dark_antler)
		brow_tine.rotation_degrees = Vector3(45.0, s * 20.0, s * -15.0)

		# Ponta média (bez tine) apontando para cima e fora
		var bez_tine := _cyl(prop_root, Vector3(s * 0.42, 0.55, 0.18), 0.022, 0.32, antler_mat)
		bez_tine.rotation_degrees = Vector3(10.0, s * 35.0, s * -55.0)

		# Ponta superior do topo (crown tine)
		var crown := _cyl(prop_root, Vector3(s * 0.36, 0.72, 0.06), 0.018, 0.28, dark_antler)
		crown.rotation_degrees = Vector3(-25.0, s * 10.0, s * -20.0)

func _build_gun_rack() -> void:
	var walnut := _mat("walnut", Color("#2e1c0c"), 0.0, 0.4)
	var blued_steel := _mat("blued_steel", Color("#222831"), 0.85, 0.25)
	var gun_wood := _mat("gun_wood", Color("#5c381e"), 0.1, 0.4)
	var brass := _mat("brass", Color("#c59b27"), 0.9, 0.2)
	var glass := _mat("scope_glass", Color("#4bcffa"), 0.4, 0.1, 0.3)

	# 1. Suporte vertical duplo de parede em nogueira nobre
	for s in [-0.55, 0.55]:
		_box(prop_root, Vector3(s, 0.0, -0.06), Vector3(0.10, 0.90, 0.08), walnut)
		# Ganchos de apoio em metal
		for y in [-0.22, 0.22]:
			_box(prop_root, Vector3(s, y, 0.06), Vector3(0.08, 0.06, 0.16), brass)

	# 2. Fuzil Superior: Rifle de Precisão Sniper / Caça Pesada com Luneta
	var r1_root := Node3D.new()
	r1_root.position = Vector3(0.0, 0.22, 0.12)
	prop_root.add_child(r1_root)
	# Coronha de nogueira
	_box(r1_root, Vector3(-0.45, -0.04, 0.0), Vector3(0.42, 0.13, 0.06), gun_wood)
	# Corpo/Culatra de aço temperado
	_box(r1_root, Vector3(-0.08, 0.0, 0.0), Vector3(0.35, 0.08, 0.07), blued_steel)
	# Ferrolho
	var bolt := _cyl(r1_root, Vector3(-0.12, 0.06, 0.04), 0.015, 0.09, blued_steel)
	bolt.rotation_degrees.z = 90.0
	# Cano longo estriado
	var barrel1 := _cyl(r1_root, Vector3(0.45, 0.0, 0.0), 0.022, 0.76, blued_steel)
	barrel1.rotation_degrees.z = 90.0
	# Luneta telescópica com anéis de montagem
	var scope := _cyl(r1_root, Vector3(-0.06, 0.08, 0.0), 0.028, 0.36, blued_steel)
	scope.rotation_degrees.z = 90.0
	_cyl(r1_root, Vector3(0.12, 0.08, 0.0), 0.035, 0.06, glass).rotation_degrees.z = 90.0

	# 3. Fuzil Inferior: Espingarda de Repetição Lever-Action / Shotgun de Caça
	var r2_root := Node3D.new()
	r2_root.position = Vector3(0.0, -0.22, 0.12)
	prop_root.add_child(r2_root)
	# Coronha curva
	_box(r2_root, Vector3(-0.42, -0.03, 0.0), Vector3(0.38, 0.12, 0.06), gun_wood)
	# Receptor em latão envelhecido
	_box(r2_root, Vector3(-0.10, 0.0, 0.0), Vector3(0.30, 0.09, 0.07), brass)
	# Cano e tubo de munição duplo
	var barrel2 := _cyl(r2_root, Vector3(0.38, 0.02, 0.0), 0.024, 0.70, blued_steel)
	barrel2.rotation_degrees.z = 90.0
	var mag_tube := _cyl(r2_root, Vector3(0.35, -0.03, 0.0), 0.018, 0.65, blued_steel)
	mag_tube.rotation_degrees.z = 90.0

func _build_cast_iron_stove() -> void:
	var iron := _mat("cast_iron", Color("#23272a"), 0.7, 0.6)
	var copper := _mat("copper", Color("#d35400"), 0.85, 0.25)
	var brass := _mat("brass", Color("#e58e26"), 0.85, 0.3)
	var embers := _mat("embers", Color("#ff5722"), 0.2, 0.2, 2.5)

	# 1. 4 Pés curvos de ferro forjado
	for sx in [-0.34, 0.34]:
		for sz in [-0.34, 0.34]:
			var leg := _cyl(prop_root, Vector3(sx, -0.42, sz), 0.04, 0.24, iron)
			leg.rotation_degrees = Vector3(sz * 18.0, 0.0, sx * -18.0)

	# 2. Corpo cilíndrico robusto do fogão a lenha
	_cyl(prop_root, Vector3(0.0, -0.06, 0.0), 0.44, 0.60, iron)
	# Borda reforçada do topo
	_cyl(prop_root, Vector3(0.0, 0.26, 0.0), 0.48, 0.06, iron)

	# 3. Porta frontal com fresta de vidro e braseiro ardente
	_box(prop_root, Vector3(0.0, -0.06, 0.43), Vector3(0.32, 0.30, 0.05), iron)
	_box(prop_root, Vector3(0.0, -0.06, 0.45), Vector3(0.24, 0.18, 0.03), embers)
	# Maçaneta de latão
	_cyl(prop_root, Vector3(0.13, -0.06, 0.48), 0.02, 0.07, brass).rotation_degrees.z = 90.0

	# 4. Chaminé / Tubo de exaustão preto subindo para o telhado
	_cyl(prop_root, Vector3(0.0, 0.70, -0.12), 0.11, 0.90, iron)

	# 5. Chaleira de Cobre Polido em cima da chapa quente
	var kettle_root := Node3D.new()
	kettle_root.position = Vector3(0.08, 0.38, 0.10)
	prop_root.add_child(kettle_root)
	_cyl(kettle_root, Vector3(0.0, 0.0, 0.0), 0.14, 0.16, copper)
	_cyl(kettle_root, Vector3(0.0, 0.09, 0.0), 0.08, 0.04, brass) # Tampa
	# Bico da chaleira inclinado
	var spout := _cyl(kettle_root, Vector3(-0.14, 0.06, 0.0), 0.025, 0.12, copper)
	spout.rotation_degrees.z = 45.0

func _build_bear_rug_head() -> void:
	var fur := _mat("bear_fur", Color("#2c1b0e"), 0.0, 0.85)
	var dark_fur := _mat("dark_fur", Color("#190f07"), 0.0, 0.9)
	var nose_mat := _mat("bear_nose", Color("#0e0d0c"), 0.3, 0.3)
	var fangs_mat := _mat("fangs", Color("#f5f6fa"), 0.1, 0.2)
	var mouth_mat := _mat("mouth", Color("#78281f"), 0.1, 0.4)

	# 1. Base da cabeça achatada no chão
	_box(prop_root, Vector3(0.0, 0.08, -0.10), Vector3(0.58, 0.22, 0.48), fur)

	# 2. Focinho projetado para a frente
	var muzzle := _box(prop_root, Vector3(0.0, 0.12, 0.26), Vector3(0.36, 0.20, 0.38), dark_fur)
	muzzle.rotation_degrees.x = -8.0

	# 3. Nariz grande e escuro
	_box(prop_root, Vector3(0.0, 0.19, 0.45), Vector3(0.16, 0.09, 0.10), nose_mat)

	# 4. Boca aberta com língua e presas brancas
	_box(prop_root, Vector3(0.0, 0.04, 0.30), Vector3(0.28, 0.08, 0.26), mouth_mat)
	# 4 Presas afiadas
	for sx in [-0.10, 0.10]:
		# Presas superiores
		_box(prop_root, Vector3(sx, 0.09, 0.40), Vector3(0.025, 0.07, 0.025), fangs_mat)
		# Presas inferiores
		_box(prop_root, Vector3(sx * 0.85, 0.03, 0.38), Vector3(0.022, 0.06, 0.022), fangs_mat)

	# 5. Orelhas arredondadas
	for sx in [-0.28, 0.28]:
		var ear := _cyl(prop_root, Vector3(sx, 0.24, -0.22), 0.09, 0.04, fur)
		ear.rotation_degrees = Vector3(18.0, 0.0, sx * -25.0)

	# 6. Olhos castanhos brilhantes
	for sx in [-0.16, 0.16]:
		_box(prop_root, Vector3(sx, 0.22, 0.14), Vector3(0.04, 0.04, 0.04), nose_mat)

func _build_radio_transceiver() -> void:
	var case_mat := _mat("radio_case", Color("#2c3a2f"), 0.4, 0.5) # Verde militar oliva
	var face_mat := _mat("radio_face", Color("#19201a"), 0.3, 0.6)
	var chrome := _mat("chrome", Color("#bdc3c7"), 0.85, 0.2)
	var dial_led := _mat("dial_led", Color("#2ecc71"), 0.1, 0.2, 2.0)
	var mic_mat := _mat("mic", Color("#111111"), 0.1, 0.7)

	# 1. Caixa pesada de rádio militar com alça de transporte
	_box(prop_root, Vector3(0.0, 0.0, 0.0), Vector3(0.68, 0.36, 0.42), case_mat)
	_box(prop_root, Vector3(0.0, 0.0, 0.215), Vector3(0.60, 0.28, 0.02), face_mat)

	# 2. Tela de display de frequência iluminada em verde fosforescente
	_box(prop_root, Vector3(-0.14, 0.05, 0.23), Vector3(0.24, 0.10, 0.015), dial_led)

	# 3. Dials de sintonia de volume e canal
	for dx in [0.08, 0.20]:
		_cyl(prop_root, Vector3(dx, 0.05, 0.24), 0.045, 0.04, chrome).rotation_degrees.x = 90.0

	# 4. Alto-falante perfurado
	for y in [-0.08, -0.03]:
		for x in [-0.20, -0.10, 0.0, 0.10, 0.20]:
			_box(prop_root, Vector3(x, y, 0.23), Vector3(0.04, 0.015, 0.01), chrome)

	# 5. Antena telescópica longa inclinada
	var ant := _cyl(prop_root, Vector3(0.28, 0.50, -0.12), 0.012, 0.80, chrome)
	ant.rotation_degrees.z = -14.0

	# 6. Microfone PTT na lateral com cabo espiral
	_box(prop_root, Vector3(-0.40, -0.04, 0.06), Vector3(0.09, 0.16, 0.07), mic_mat)
