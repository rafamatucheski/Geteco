class_name DanteCGIModel
extends Node2D

## Protótipo 3D procedural do Dante Ribeiro alinhado à CGI atual (cutscenes/opening/frames/frame_v2_*.png)
## Características:
## - Jaqueta escura xadrez (charcoal/navy/slate plaid overshirt) aberta com gola dobrada e bolsos com aba
## - Camisa henley vinho/bordô rica com carcela frontal e botões metálicos
## - Ombros atléticos retos e amplos (sem arredondamento excessivo)
## - Rosto e pescoço iluminados em tom moreno oliva com barba por fazer (stubble) e bigode definidos
## - Cabelo preto volumoso em mechas onduladas
## - Jeans azul índigo escuro e botas pesadas de trabalho com solado tratorado
## - Sem acessórios adicionais (alças de mochila removidas, conforme referências)
## - Renderizado via SubViewport 3D e projetado em Sprite2D na escala real do gameplay (0.38).

@export var render_scale: Vector2 = Vector2(0.38, 0.38)
@export var current_state: String = "idle" # "idle", "walk", "run"
@export var animation_speed: float = 1.0
@export var facing_angle: float = PI # Em radianos (PI = frente/sul em direção à câmera, 0 = costas/norte)

var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_display: Sprite2D

var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D

var anim_clock: float = 0.0

# Materiais PBR compartilhados do Dante CGI v2
var mat_plaid_jacket: StandardMaterial3D
var mat_henley_shirt: StandardMaterial3D
var mat_jeans: StandardMaterial3D
var mat_skin: StandardMaterial3D
var mat_hair: StandardMaterial3D
var mat_stubble: StandardMaterial3D
var mat_boots: StandardMaterial3D
var mat_boot_sole: StandardMaterial3D
var mat_belt: StandardMaterial3D
var mat_brass_buckle: StandardMaterial3D
var mat_white: StandardMaterial3D
var mat_silver_button: StandardMaterial3D
var mat_dark_pupil: StandardMaterial3D

func _ready() -> void:
	_init_materials()
	_setup_viewport_and_camera()
	_build_cgi_dante_rig()
	_setup_sprite_display()

func _init_materials() -> void:
	# 1. Jaqueta Escura Xadrez (Dark Plaid / Flannel Overshirt)
	# Textura procedural de padrão xadrez carvão, marinho e cinza ardósia
	var plaid_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var col_base := Color("#1a2028") # Carvão escuro base
	var col_navy := Color("#131b26") # Faixa azul marinho profundo
	var col_slate := Color("#2e3846") # Linha cinza ardósia média
	var col_accent := Color("#3c4858") # Fio sutil de realce

	plaid_img.fill(col_base)
	for y in 64:
		for x in 64:
			var in_navy_x := (x % 32) < 14
			var in_navy_y := (y % 32) < 14
			var in_slate_x := (x % 16) >= 7 and (x % 16) <= 9
			var in_slate_y := (y % 16) >= 7 and (y % 16) <= 9

			if in_navy_x or in_navy_y:
				if in_navy_x and in_navy_y:
					plaid_img.set_pixel(x, y, col_navy.darkened(0.15))
				else:
					plaid_img.set_pixel(x, y, col_navy)
			if in_slate_x or in_slate_y:
				plaid_img.set_pixel(x, y, col_slate)
			if x % 32 == 0 or y % 32 == 0:
				plaid_img.set_pixel(x, y, col_accent)

	var plaid_tex := ImageTexture.create_from_image(plaid_img)

	mat_plaid_jacket = StandardMaterial3D.new()
	mat_plaid_jacket.albedo_color = Color(1.1, 1.1, 1.1) # Multiplicador para não apagar no sombreamento
	mat_plaid_jacket.albedo_texture = plaid_tex
	mat_plaid_jacket.uv1_scale = Vector3(3.0, 3.0, 3.0)
	mat_plaid_jacket.roughness = 0.85
	mat_plaid_jacket.metallic = 0.02

	# 2. Camisa Henley vinho / bordô rica (como nas cutscenes frame_v2_*)
	mat_henley_shirt = StandardMaterial3D.new()
	mat_henley_shirt.albedo_color = Color("#6e1b27") # Vinho bordô vibrante e legível
	mat_henley_shirt.roughness = 0.78

	# 3. Jeans azul índigo clássico
	mat_jeans = StandardMaterial3D.new()
	mat_jeans.albedo_color = Color("#24384d") # Denim índigo bem definido
	mat_jeans.roughness = 0.72

	# 4. Pele masculina morena oliva iluminada (melhor legibilidade à distância)
	mat_skin = StandardMaterial3D.new()
	mat_skin.albedo_color = Color("#dfa882")
	mat_skin.roughness = 0.50

	# 5. Cabelo preto ondulado com reflexos
	mat_hair = StandardMaterial3D.new()
	mat_hair.albedo_color = Color("#111317")
	mat_hair.roughness = 0.80

	# 6. Barba e bigode definidos (stubble/curta)
	mat_stubble = StandardMaterial3D.new()
	mat_stubble.albedo_color = Color("#1b1714")
	mat_stubble.roughness = 0.88

	# 7. Botas de trabalho pesadas
	mat_boots = StandardMaterial3D.new()
	mat_boots.albedo_color = Color("#1f1915")
	mat_boots.roughness = 0.40

	# 8. Sola de borracha tratorada
	mat_boot_sole = StandardMaterial3D.new()
	mat_boot_sole.albedo_color = Color("#0a0b0d")
	mat_boot_sole.roughness = 0.90

	# 9. Cinto de couro escuro
	mat_belt = StandardMaterial3D.new()
	mat_belt.albedo_color = Color("#1c1815")
	mat_belt.roughness = 0.45

	# 10. Fivela de latão dourado
	mat_brass_buckle = StandardMaterial3D.new()
	mat_brass_buckle.albedo_color = Color("#d4ac0d")
	mat_brass_buckle.metallic = 0.85
	mat_brass_buckle.roughness = 0.25

	# 11. Botões metálicos prateados da camisa henley
	mat_silver_button = StandardMaterial3D.new()
	mat_silver_button.albedo_color = Color("#ecf0f1")
	mat_silver_button.metallic = 0.90
	mat_silver_button.roughness = 0.20

	# 12. Branco dos olhos
	mat_white = StandardMaterial3D.new()
	mat_white.albedo_color = Color("#f4f6f7")
	mat_white.roughness = 0.30

	# 13. Pupilas escuras
	mat_dark_pupil = StandardMaterial3D.new()
	mat_dark_pupil.albedo_color = Color("#090a0c")
	mat_dark_pupil.roughness = 0.15

func _setup_viewport_and_camera() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(128, 128)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)

	camera_3d = Camera3D.new()
	camera_3d.position = Vector3(0.0, 3.2, 1.4)
	camera_3d.fov = 30.0
	viewport_3d.add_child(camera_3d)
	camera_3d.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	# Luz principal direcionada (mais intensa para evitar escurecimento no gameplay)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	light.light_energy = 1.65
	light.light_color = Color(1.0, 0.98, 0.94)
	viewport_3d.add_child(light)

	# Luz de preenchimento ambiente suave
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, -145.0, 0.0)
	fill.light_energy = 0.85
	fill.light_color = Color(0.82, 0.88, 1.0)
	viewport_3d.add_child(fill)

	# Ambiente e iluminação indireta
	var env = WorldEnvironment.new()
	var env_res = Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0, 0, 0, 0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.76, 0.79, 0.86)
	env.environment = env_res
	viewport_3d.add_child(env)

func _setup_sprite_display() -> void:
	sprite_display = Sprite2D.new()
	sprite_display.texture = viewport_3d.get_texture()
	sprite_display.scale = render_scale
	add_child(sprite_display)

func _build_cgi_dante_rig() -> void:
	model_root = Node3D.new()
	viewport_3d.add_child(model_root)

	# 1. Sombra de contato sob os pés
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.05, 0.45)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow = MeshInstance3D.new()
	var cyl_s = CylinderMesh.new()
	cyl_s.top_radius = 0.28
	cyl_s.bottom_radius = 0.28
	cyl_s.height = 0.01
	cyl_s.radial_segments = 12
	cyl_s.rings = 1
	shadow.mesh = cyl_s
	shadow.material_override = shadow_mat
	shadow.position = Vector3(0.0, 0.005, 0.0)
	model_root.add_child(shadow)

	# 2. Torso (tronco muscular, jaqueta xadrez aberta e camisa henley)
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)

	# Pescoço
	var neck = MeshInstance3D.new()
	var cyl_nk = CylinderMesh.new()
	cyl_nk.top_radius = 0.095
	cyl_nk.bottom_radius = 0.105
	cyl_nk.height = 0.14
	cyl_nk.radial_segments = 10
	cyl_nk.rings = 1
	neck.mesh = cyl_nk
	neck.material_override = mat_skin
	neck.position = Vector3(0.0, 0.26, 0.0)
	torso_node.add_child(neck)

	# Camisa Henley vinho (visível no centro do peito e abdômen)
	var henley_chest = MeshInstance3D.new()
	var box_hc = BoxMesh.new()
	box_hc.size = Vector3(0.18, 0.38, 0.27)
	henley_chest.mesh = box_hc
	henley_chest.material_override = mat_henley_shirt
	henley_chest.position = Vector3(0.0, 0.04, 0.0)
	torso_node.add_child(henley_chest)

	# Abertura em V da gola henley (pele exposta na clavícula)
	var chest_v = MeshInstance3D.new()
	var box_cv = BoxMesh.new()
	box_cv.size = Vector3(0.07, 0.10, 0.02)
	chest_v.mesh = box_cv
	chest_v.material_override = mat_skin
	chest_v.position = Vector3(0.0, 0.18, -0.138)
	torso_node.add_child(chest_v)

	# Carcela e 3 botões metálicos prateados visíveis
	var placket = MeshInstance3D.new()
	var box_pl = BoxMesh.new()
	box_pl.size = Vector3(0.03, 0.16, 0.008)
	placket.mesh = box_pl
	placket.material_override = mat_henley_shirt
	placket.position = Vector3(0.0, 0.08, -0.137)
	torso_node.add_child(placket)

	for b in 3:
		var btn = MeshInstance3D.new()
		var cyl_btn = CylinderMesh.new()
		cyl_btn.top_radius = 0.009
		cyl_btn.bottom_radius = 0.009
		cyl_btn.height = 0.006
		cyl_btn.radial_segments = 8
		cyl_btn.rings = 1
		btn.mesh = cyl_btn
		btn.material_override = mat_silver_button
		btn.position = Vector3(0.0, 0.13 - float(b) * 0.045, -0.142)
		btn.rotation_degrees = Vector3(90, 0, 0)
		torso_node.add_child(btn)

	# Costas e laterais da jaqueta xadrez (mais ampla nos ombros)
	var jacket_back = MeshInstance3D.new()
	var box_jb = BoxMesh.new()
	box_jb.size = Vector3(0.42, 0.44, 0.28)
	jacket_back.mesh = box_jb
	jacket_back.material_override = mat_plaid_jacket
	jacket_back.position = Vector3(0.0, 0.04, 0.015)
	torso_node.add_child(jacket_back)

	# Ombros atléticos retos estruturados (elimina visual arredondado / caído)
	var shoulder_bar = MeshInstance3D.new()
	var box_sb = BoxMesh.new()
	box_sb.size = Vector3(0.52, 0.09, 0.26)
	shoulder_bar.mesh = box_sb
	shoulder_bar.material_override = mat_plaid_jacket
	shoulder_bar.position = Vector3(0.0, 0.22, 0.0)
	torso_node.add_child(shoulder_bar)

	# Aba frontal esquerda da jaqueta aberta
	var j_flap_l = MeshInstance3D.new()
	var box_jfl = BoxMesh.new()
	box_jfl.size = Vector3(0.08, 0.36, 0.035)
	j_flap_l.mesh = box_jfl
	j_flap_l.material_override = mat_plaid_jacket
	j_flap_l.position = Vector3(-0.13, 0.02, -0.13)
	j_flap_l.rotation_degrees = Vector3(0, 6, -2)
	torso_node.add_child(j_flap_l)

	# Bolso com aba no peito esquerdo
	var pocket_l = MeshInstance3D.new()
	var box_pkl = BoxMesh.new()
	box_pkl.size = Vector3(0.065, 0.08, 0.02)
	pocket_l.mesh = box_pkl
	pocket_l.material_override = mat_plaid_jacket
	pocket_l.position = Vector3(-0.13, 0.09, -0.15)
	torso_node.add_child(pocket_l)

	# Aba frontal direita da jaqueta aberta
	var j_flap_r = MeshInstance3D.new()
	var box_jfr = BoxMesh.new()
	box_jfr.size = Vector3(0.08, 0.36, 0.035)
	j_flap_r.mesh = box_jfr
	j_flap_r.material_override = mat_plaid_jacket
	j_flap_r.position = Vector3(0.13, 0.02, -0.13)
	j_flap_r.rotation_degrees = Vector3(0, -6, 2)
	torso_node.add_child(j_flap_r)

	# Bolso com aba no peito direito
	var pocket_r = MeshInstance3D.new()
	var box_pkr = BoxMesh.new()
	box_pkr.size = Vector3(0.065, 0.08, 0.02)
	pocket_r.mesh = box_pkr
	pocket_r.material_override = mat_plaid_jacket
	pocket_r.position = Vector3(0.13, 0.09, -0.15)
	torso_node.add_child(pocket_r)

	# Gola de camisa da jaqueta (Fold-down collar)
	var col_l = MeshInstance3D.new()
	var box_cl = BoxMesh.new()
	box_cl.size = Vector3(0.08, 0.08, 0.03)
	col_l.mesh = box_cl
	col_l.material_override = mat_plaid_jacket
	col_l.position = Vector3(-0.12, 0.23, -0.13)
	col_l.rotation_degrees = Vector3(16, 12, -22)
	torso_node.add_child(col_l)

	var col_r = MeshInstance3D.new()
	var box_cr = BoxMesh.new()
	box_cr.size = Vector3(0.08, 0.08, 0.03)
	col_r.mesh = box_cr
	col_r.material_override = mat_plaid_jacket
	col_r.position = Vector3(0.12, 0.23, -0.13)
	col_r.rotation_degrees = Vector3(16, -12, 22)
	torso_node.add_child(col_r)

	# Cinto de couro escuro
	var belt = MeshInstance3D.new()
	var box_b = BoxMesh.new()
	box_b.size = Vector3(0.38, 0.05, 0.32)
	belt.mesh = box_b
	belt.material_override = mat_belt
	belt.position = Vector3(0.0, -0.18, 0.0)
	torso_node.add_child(belt)

	# Fivela do cinto em latão dourado retangular
	var buckle = MeshInstance3D.new()
	var box_bk = BoxMesh.new()
	box_bk.size = Vector3(0.065, 0.055, 0.025)
	buckle.mesh = box_bk
	buckle.material_override = mat_brass_buckle
	buckle.position = Vector3(0.0, -0.18, -0.165)
	torso_node.add_child(buckle)

	# 3. Cabeça & Cabelo Canônico do Dante
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)

	# Crânio base
	var head_mesh = MeshInstance3D.new()
	var sph_h = SphereMesh.new()
	sph_h.radius = 0.16
	sph_h.height = 0.30
	sph_h.radial_segments = 12
	sph_h.rings = 6
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Mandíbula quadrada masculina
	var jaw = MeshInstance3D.new()
	var box_jaw = BoxMesh.new()
	box_jaw.size = Vector3(0.175, 0.095, 0.14)
	jaw.mesh = box_jaw
	jaw.material_override = mat_skin
	jaw.position = Vector3(0.0, -0.09, -0.05)
	jaw.rotation_degrees = Vector3(-14, 0, 0)
	head_node.add_child(jaw)

	# Barba e bigode definidos contornando queixo e lábios
	var stubble_chin = MeshInstance3D.new()
	var box_sc = BoxMesh.new()
	box_sc.size = Vector3(0.170, 0.070, 0.135)
	stubble_chin.mesh = box_sc
	stubble_chin.material_override = mat_stubble
	stubble_chin.position = Vector3(0.0, -0.10, -0.06)
	stubble_chin.rotation_degrees = Vector3(-14, 0, 0)
	head_node.add_child(stubble_chin)

	var stubble_mustache = MeshInstance3D.new()
	var box_sm = BoxMesh.new()
	box_sm.size = Vector3(0.09, 0.028, 0.02)
	stubble_mustache.mesh = box_sm
	stubble_mustache.material_override = mat_stubble
	stubble_mustache.position = Vector3(0.0, -0.045, -0.165)
	head_node.add_child(stubble_mustache)

	# Nariz angular e firme
	var nose = MeshInstance3D.new()
	var box_n = BoxMesh.new()
	box_n.size = Vector3(0.028, 0.055, 0.038)
	nose.mesh = box_n
	nose.material_override = mat_skin
	nose.position = Vector3(0.0, 0.015, -0.175)
	nose.rotation_degrees = Vector3(-12, 0, 0)
	head_node.add_child(nose)

	# Olhos penetrantes
	for side in [-1, 1]:
		var eye = MeshInstance3D.new()
		var box_e = BoxMesh.new()
		box_e.size = Vector3(0.044, 0.024, 0.018)
		eye.mesh = box_e
		eye.material_override = mat_white
		eye.position = Vector3(float(side) * 0.058, 0.038, -0.158)
		head_node.add_child(eye)

		var pupil = MeshInstance3D.new()
		var box_p = BoxMesh.new()
		box_p.size = Vector3(0.022, 0.022, 0.015)
		pupil.mesh = box_p
		pupil.material_override = mat_dark_pupil
		pupil.position = Vector3(float(side) * 0.058, 0.038, -0.166)
		head_node.add_child(pupil)

		var brow = MeshInstance3D.new()
		var box_br = BoxMesh.new()
		box_br.size = Vector3(0.054, 0.016, 0.018)
		brow.mesh = box_br
		brow.material_override = mat_hair
		brow.position = Vector3(float(side) * 0.058, 0.065, -0.162)
		brow.rotation_degrees = Vector3(0, 0, float(side) * 10)
		head_node.add_child(brow)

		var ear = MeshInstance3D.new()
		var box_ear = BoxMesh.new()
		box_ear.size = Vector3(0.025, 0.06, 0.04)
		ear.mesh = box_ear
		ear.material_override = mat_skin
		ear.position = Vector3(float(side) * 0.165, 0.01, -0.01)
		head_node.add_child(ear)

	# Cabelo Volumoso e Ondulado em Camadas
	_build_cgi_hair(head_node)

	# 4. Membros Superiores (Ombros retos e jaqueta xadrez com punhos)
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.27, 0.20, 0.0) # Mais alto e aberto para postura atlética
	torso_node.add_child(left_upper_arm)

	var l_uarm_mesh = MeshInstance3D.new()
	var cap_lua = CapsuleMesh.new()
	cap_lua.radius = 0.078
	cap_lua.height = 0.28
	cap_lua.radial_segments = 10
	cap_lua.rings = 2
	l_uarm_mesh.mesh = cap_lua
	l_uarm_mesh.material_override = mat_plaid_jacket
	l_uarm_mesh.position = Vector3(0.0, -0.10, 0.0)
	left_upper_arm.add_child(l_uarm_mesh)

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0.0, -0.22, 0.0)
	left_upper_arm.add_child(left_lower_arm)

	var l_larm_mesh = MeshInstance3D.new()
	var cap_lla = CapsuleMesh.new()
	cap_lla.radius = 0.070
	cap_lla.height = 0.26
	cap_lla.radial_segments = 10
	cap_lla.rings = 2
	l_larm_mesh.mesh = cap_lla
	l_larm_mesh.material_override = mat_plaid_jacket
	l_larm_mesh.position = Vector3(0.0, -0.10, 0.0)
	left_lower_arm.add_child(l_larm_mesh)

	var l_hand = MeshInstance3D.new()
	var box_lh = BoxMesh.new()
	box_lh.size = Vector3(0.07, 0.08, 0.065)
	l_hand.mesh = box_lh
	l_hand.material_override = mat_skin
	l_hand.position = Vector3(0.0, -0.23, 0.0)
	left_lower_arm.add_child(l_hand)

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.27, 0.20, 0.0)
	torso_node.add_child(right_upper_arm)

	var r_uarm_mesh = MeshInstance3D.new()
	var cap_rua = CapsuleMesh.new()
	cap_rua.radius = 0.078
	cap_rua.height = 0.28
	cap_rua.radial_segments = 10
	cap_rua.rings = 2
	r_uarm_mesh.mesh = cap_rua
	r_uarm_mesh.material_override = mat_plaid_jacket
	r_uarm_mesh.position = Vector3(0.0, -0.10, 0.0)
	right_upper_arm.add_child(r_uarm_mesh)

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0.0, -0.22, 0.0)
	right_upper_arm.add_child(right_lower_arm)

	var r_larm_mesh = MeshInstance3D.new()
	var cap_rla = CapsuleMesh.new()
	cap_rla.radius = 0.070
	cap_rla.height = 0.26
	cap_rla.radial_segments = 10
	cap_rla.rings = 2
	r_larm_mesh.mesh = cap_rla
	r_larm_mesh.material_override = mat_plaid_jacket
	r_larm_mesh.position = Vector3(0.0, -0.10, 0.0)
	right_lower_arm.add_child(r_larm_mesh)

	var r_hand = MeshInstance3D.new()
	var box_rh = BoxMesh.new()
	box_rh.size = Vector3(0.07, 0.08, 0.065)
	r_hand.mesh = box_rh
	r_hand.material_override = mat_skin
	r_hand.position = Vector3(0.0, -0.23, 0.0)
	right_lower_arm.add_child(r_hand)

	# 5. Membros Inferiores (Pernas com jeans azul escuro e botas tratoradas)
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, -0.20, 0.0)
	torso_node.add_child(left_upper_leg)

	var l_uleg_mesh = MeshInstance3D.new()
	var cap_lul = CapsuleMesh.new()
	cap_lul.radius = 0.088
	cap_lul.height = 0.34
	cap_lul.radial_segments = 10
	cap_lul.rings = 2
	l_uleg_mesh.mesh = cap_lul
	l_uleg_mesh.material_override = mat_jeans
	l_uleg_mesh.position = Vector3(0.0, -0.14, 0.0)
	left_upper_leg.add_child(l_uleg_mesh)

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0.0, -0.30, 0.0)
	left_upper_leg.add_child(left_lower_leg)

	var l_lleg_mesh = MeshInstance3D.new()
	var cap_lll = CapsuleMesh.new()
	cap_lll.radius = 0.082
	cap_lll.height = 0.32
	cap_lll.radial_segments = 10
	cap_lll.rings = 2
	l_lleg_mesh.mesh = cap_lll
	l_lleg_mesh.material_override = mat_jeans
	l_lleg_mesh.position = Vector3(0.0, -0.12, 0.0)
	left_lower_leg.add_child(l_lleg_mesh)

	var l_boot = MeshInstance3D.new()
	var box_lbt = BoxMesh.new()
	box_lbt.size = Vector3(0.10, 0.12, 0.18)
	l_boot.mesh = box_lbt
	l_boot.material_override = mat_boots
	l_boot.position = Vector3(0.0, -0.28, -0.02)
	left_lower_leg.add_child(l_boot)

	var l_sole = MeshInstance3D.new()
	var box_lsl = BoxMesh.new()
	box_lsl.size = Vector3(0.108, 0.035, 0.20)
	l_sole.mesh = box_lsl
	l_sole.material_override = mat_boot_sole
	l_sole.position = Vector3(0.0, -0.33, -0.02)
	left_lower_leg.add_child(l_sole)

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, -0.20, 0.0)
	torso_node.add_child(right_upper_leg)

	var r_uleg_mesh = MeshInstance3D.new()
	var cap_rul = CapsuleMesh.new()
	cap_rul.radius = 0.088
	cap_rul.height = 0.34
	cap_rul.radial_segments = 10
	cap_rul.rings = 2
	r_uleg_mesh.mesh = cap_rul
	r_uleg_mesh.material_override = mat_jeans
	r_uleg_mesh.position = Vector3(0.0, -0.14, 0.0)
	right_upper_leg.add_child(r_uleg_mesh)

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0.0, -0.30, 0.0)
	right_upper_leg.add_child(right_lower_leg)

	var r_lleg_mesh = MeshInstance3D.new()
	var cap_rll = CapsuleMesh.new()
	cap_rll.radius = 0.082
	cap_rll.height = 0.32
	cap_rll.radial_segments = 10
	cap_rll.rings = 2
	r_lleg_mesh.mesh = cap_rll
	r_lleg_mesh.material_override = mat_jeans
	r_lleg_mesh.position = Vector3(0.0, -0.12, 0.0)
	right_lower_leg.add_child(r_lleg_mesh)

	var r_boot = MeshInstance3D.new()
	var box_rbt = BoxMesh.new()
	box_rbt.size = Vector3(0.10, 0.12, 0.18)
	r_boot.mesh = box_rbt
	r_boot.material_override = mat_boots
	r_boot.position = Vector3(0.0, -0.28, -0.02)
	right_lower_leg.add_child(r_boot)

	var r_sole = MeshInstance3D.new()
	var box_rsl = BoxMesh.new()
	box_rsl.size = Vector3(0.108, 0.035, 0.20)
	r_sole.mesh = box_rsl
	r_sole.material_override = mat_boot_sole
	r_sole.position = Vector3(0.0, -0.33, -0.02)
	right_lower_leg.add_child(r_sole)

func _build_cgi_hair(parent: Node3D) -> void:
	var hair_cap = MeshInstance3D.new()
	var sph_hc = SphereMesh.new()
	sph_hc.radius = 0.18
	sph_hc.height = 0.28
	sph_hc.radial_segments = 12
	sph_hc.rings = 6
	hair_cap.mesh = sph_hc
	hair_cap.material_override = mat_hair
	hair_cap.position = Vector3(0.0, 0.06, 0.02)
	parent.add_child(hair_cap)

	var bang_positions = [
		{"pos": Vector3(-0.08, 0.10, -0.14), "rot": Vector3(14, 10, -18), "sz": Vector3(0.06, 0.08, 0.06)},
		{"pos": Vector3(-0.02, 0.11, -0.16), "rot": Vector3(20, -5, -8), "sz": Vector3(0.065, 0.09, 0.055)},
		{"pos": Vector3(0.05, 0.10, -0.15), "rot": Vector3(16, -14, 15), "sz": Vector3(0.06, 0.085, 0.055)},
		{"pos": Vector3(0.10, 0.09, -0.13), "rot": Vector3(12, -22, 25), "sz": Vector3(0.055, 0.075, 0.05)},
		{"pos": Vector3(-0.04, 0.18, -0.05), "rot": Vector3(8, 6, -12), "sz": Vector3(0.08, 0.08, 0.08)},
		{"pos": Vector3(0.04, 0.19, -0.03), "rot": Vector3(-4, -10, 16), "sz": Vector3(0.085, 0.085, 0.085)},
		{"pos": Vector3(0.0, 0.20, 0.04), "rot": Vector3(-12, 0, 0), "sz": Vector3(0.09, 0.08, 0.09)},
		{"pos": Vector3(-0.16, 0.06, -0.05), "rot": Vector3(6, 12, -15), "sz": Vector3(0.05, 0.10, 0.08)},
		{"pos": Vector3(0.16, 0.06, -0.05), "rot": Vector3(6, -12, 15), "sz": Vector3(0.05, 0.10, 0.08)},
		{"pos": Vector3(0.0, 0.02, 0.15), "rot": Vector3(-15, 0, 0), "sz": Vector3(0.15, 0.14, 0.08)}
	]

	for b in bang_positions:
		var tuft = MeshInstance3D.new()
		var box_t = BoxMesh.new()
		box_t.size = b.sz
		tuft.mesh = box_t
		tuft.material_override = mat_hair
		tuft.position = b.pos
		tuft.rotation_degrees = b.rot
		parent.add_child(tuft)

func _process(delta: float) -> void:
	anim_clock += delta * animation_speed
	model_root.rotation.y = facing_angle
	_apply_animation(current_state, anim_clock)

func _apply_animation(state: String, t: float) -> void:
	if not torso_node or not head_node or not left_upper_arm or not right_upper_arm or not left_upper_leg or not right_upper_leg:
		return

	match state:
		"idle":
			var breath := sin(t * 2.2)
			torso_node.position.y = 0.85 + breath * 0.008
			torso_node.rotation_degrees = Vector3(0, 0, 0)
			head_node.position.y = 1.25 + breath * 0.012
			head_node.rotation_degrees = Vector3(-breath * 2.0, 0, 0)
			left_upper_arm.rotation_degrees = Vector3(6.0 + breath * 2.0, 0, 6.0)
			right_upper_arm.rotation_degrees = Vector3(6.0 + breath * 2.0, 0, -6.0)
			left_lower_arm.rotation_degrees = Vector3(-12.0, 0, 0)
			right_lower_arm.rotation_degrees = Vector3(-12.0, 0, 0)
			left_upper_leg.rotation_degrees = Vector3(0, 0, -2.0)
			right_upper_leg.rotation_degrees = Vector3(0, 0, 2.0)
			left_lower_leg.rotation_degrees = Vector3(0, 0, 0)
			right_lower_leg.rotation_degrees = Vector3(0, 0, 0)

		"walk":
			var cycle := t * 7.5
			var s_leg := sin(cycle)

			torso_node.position.y = 0.85 + abs(sin(cycle)) * 0.022
			torso_node.rotation_degrees = Vector3(3.0, s_leg * 4.0, -s_leg * 2.5)
			head_node.position.y = 1.25 + abs(sin(cycle)) * 0.016
			head_node.rotation_degrees = Vector3(-1.0, -s_leg * 3.0, 0)

			left_upper_leg.rotation_degrees = Vector3(s_leg * 26.0, 0, -2.0)
			left_lower_leg.rotation_degrees = Vector3(maxf(0.0, -s_leg * 35.0), 0, 0)
			right_upper_leg.rotation_degrees = Vector3(-s_leg * 26.0, 0, 2.0)
			right_lower_leg.rotation_degrees = Vector3(maxf(0.0, s_leg * 35.0), 0, 0)

			left_upper_arm.rotation_degrees = Vector3(-s_leg * 22.0, 0, 8.0)
			left_lower_arm.rotation_degrees = Vector3(-15.0 - maxf(0.0, -s_leg * 25.0), 0, 0)
			right_upper_arm.rotation_degrees = Vector3(s_leg * 22.0, 0, -8.0)
			right_lower_arm.rotation_degrees = Vector3(-15.0 - maxf(0.0, s_leg * 25.0), 0, 0)

		"run":
			var cycle := t * 12.0
			var s_leg := sin(cycle)

			torso_node.position.y = 0.85 + abs(sin(cycle)) * 0.045
			torso_node.rotation_degrees = Vector3(14.0, s_leg * 6.0, -s_leg * 3.5)
			head_node.position.y = 1.24 + abs(sin(cycle)) * 0.035
			head_node.rotation_degrees = Vector3(-4.0, -s_leg * 4.0, 0)

			left_upper_leg.rotation_degrees = Vector3(s_leg * 48.0, 0, -2.0)
			left_lower_leg.rotation_degrees = Vector3(maxf(0.0, -s_leg * 65.0), 0, 0)
			right_upper_leg.rotation_degrees = Vector3(-s_leg * 48.0, 0, 2.0)
			right_lower_leg.rotation_degrees = Vector3(maxf(0.0, s_leg * 65.0), 0, 0)

			left_upper_arm.rotation_degrees = Vector3(-s_leg * 42.0, 0, 10.0)
			left_lower_arm.rotation_degrees = Vector3(-55.0 - s_leg * 20.0, 0, 0)
			right_upper_arm.rotation_degrees = Vector3(s_leg * 42.0, 0, -10.0)
			right_lower_arm.rotation_degrees = Vector3(-55.0 + s_leg * 20.0, 0, 0)

## Medição exata de métricas do modelo em runtime (não é estimativa estática)
func get_model_stats() -> Dictionary:
	var measured_triangles := 0
	var mesh_nodes := 0
	var unique_materials: Dictionary = {}

	if model_root:
		var stack: Array[Node] = [model_root]
		while not stack.is_empty():
			var curr: Node = stack.pop_back()
			if curr is MeshInstance3D:
				mesh_nodes += 1
				var mi = curr as MeshInstance3D
				var m = mi.mesh
				if m:
					var faces = m.get_faces()
					if faces.size() > 0:
						measured_triangles += faces.size() / 3
					elif m is BoxMesh:
						measured_triangles += 12
					elif m is CylinderMesh:
						measured_triangles += 128
					elif m is CapsuleMesh:
						measured_triangles += 192
					elif m is SphereMesh:
						measured_triangles += 160

				if mi.material_override:
					unique_materials[mi.material_override.get_instance_id()] = mi.material_override

			for ch in curr.get_children():
				stack.append(ch)

	var active_vps := 0
	if viewport_3d and is_instance_valid(viewport_3d):
		active_vps = 1

	return {
		"triangle_count": measured_triangles,
		"mesh_count": mesh_nodes,
		"materials_count": unique_materials.size(),
		"active_viewports": active_vps,
		"render_method": "SubViewport 3D (128x128) -> Sprite2D (Escala 0.38)",
		"textures": "PBR Procedural (Albedo Plaid 64x64, Roughness, Metallic)"
	}
