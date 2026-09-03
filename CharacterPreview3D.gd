class_name CharacterPreview3D
extends SubViewportContainer

@export var auto_rotate: bool = true
@export var rotate_speed: float = 0.85

var viewport: SubViewport
var camera: Camera3D
var model_root: Node3D
var dante_root: Node3D
var active_outfit_id: String = "dante_classic"
var is_dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(320, 420)
	stretch = true
	
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 420)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	# 1. Câmera 3D em Ângulo Top-Down Frontal de Alta Definição
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.35, 2.45)
	camera.fov = 32.0
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.82, 0.0), Vector3.UP)

	# 2. Iluminação de Estúdio 3D com Luz Principal, Luz de Preenchimento e Rim Light
	var key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	key_light.light_energy = 1.45
	key_light.light_color = Color(1.0, 0.98, 0.95)
	viewport.add_child(key_light)

	var fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, -50.0, 0.0)
	fill_light.light_energy = 0.70
	fill_light.light_color = Color(0.85, 0.90, 1.0)
	viewport.add_child(fill_light)

	var rim_light = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-15.0, 180.0, 0.0)
	rim_light.light_energy = 0.95
	rim_light.light_color = Color(1.0, 0.85, 0.65)
	viewport.add_child(rim_light)

	var env = WorldEnvironment.new()
	var env_res = Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0, 0, 0, 0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.40, 0.42, 0.50)
	env.environment = env_res
	viewport.add_child(env)

	# 3. Plataforma Giratória (Turntable Pedestal)
	model_root = Node3D.new()
	viewport.add_child(model_root)

	var platform_mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.58
	cyl.height = 0.06
	platform_mesh.mesh = cyl
	var mat_plat = StandardMaterial3D.new()
	mat_plat.albedo_color = Color("1e272e")
	mat_plat.metallic = 0.6
	mat_plat.roughness = 0.3
	platform_mesh.material_override = mat_plat
	platform_mesh.position = Vector3(0.0, 0.03, 0.0)
	model_root.add_child(platform_mesh)

	var glow_ring = MeshInstance3D.new()
	var ring_cyl = CylinderMesh.new()
	ring_cyl.top_radius = 0.56
	ring_cyl.bottom_radius = 0.56
	ring_cyl.height = 0.02
	glow_ring.mesh = ring_cyl
	var mat_glow = StandardMaterial3D.new()
	mat_glow.albedo_color = Color("f39c12")
	mat_glow.emission_enabled = true
	mat_glow.emission = Color("f39c12")
	mat_glow.emission_energy_multiplier = 2.5
	glow_ring.material_override = mat_glow
	glow_ring.position = Vector3(0.0, 0.065, 0.0)
	model_root.add_child(glow_ring)

	dante_root = Node3D.new()
	model_root.add_child(dante_root)

	set_outfit("dante_classic")

func _process(delta: float) -> void:
	if auto_rotate and not is_dragging and model_root:
		model_root.rotation.y += rotate_speed * delta

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			last_mouse_pos = event.position
	elif event is InputEventMouseMotion and is_dragging:
		var diff = event.position.x - last_mouse_pos.x
		if model_root:
			model_root.rotation.y += diff * 0.015
		last_mouse_pos = event.position

func set_outfit(outfit_id: String) -> void:
	active_outfit_id = outfit_id
	var data := OutfitCatalog.get_outfit(outfit_id)
	_rebuild_dante_mesh(data)

func _rebuild_dante_mesh(data: Dictionary) -> void:
	if not dante_root:
		return
	for child in dante_root.get_children():
		child.queue_free()

	var col_jacket: Color = data.get("jacket_color", Color("121214"))
	var col_pants: Color = data.get("pants_color", Color("18181b"))
	var col_skin: Color = data.get("skin_color", Color(0.86, 0.70, 0.56))
	var col_hair: Color = data.get("hair_color", Color(0.08, 0.08, 0.10))
	var col_head: Color = data.get("headwear_color", Color("1a1a1e"))
	var col_shoes: Color = data.get("shoes_color", Color(0.06, 0.06, 0.08))
	var col_trim: Color = data.get("trim_color", Color.WHITE)
	var headwear_type: String = data.get("headwear_type", "cap")
	var accessory_type: String = data.get("accessory_type", "shades")

	var mat_jacket = _make_mat(col_jacket, 0.5)
	var mat_pants = _make_mat(col_pants, 0.6)
	var mat_skin = _make_mat(col_skin, 0.5)
	var mat_hair = _make_mat(col_hair, 0.8)
	var mat_head = _make_mat(col_head, 0.4)
	var mat_shoes = _make_mat(col_shoes, 0.3)
	var mat_trim = _make_mat(col_trim, 0.2)
	var mat_dark_shades = _make_mat(Color(0.05, 0.05, 0.07), 0.1)
	var mat_gold = _make_mat(Color(0.95, 0.80, 0.25), 0.2)
	var mat_silver = _make_mat(Color(0.85, 0.88, 0.92), 0.2)
	var mat_white = _make_mat(Color(0.98, 0.98, 1.0), 0.3)
	var mat_pupil = _make_mat(Color(0.05, 0.05, 0.05), 0.1)
	var mat_lips = _make_mat(col_skin.darkened(0.20), 0.6)

	# --- PESCOÇO & TORSO ---
	var torso = Node3D.new()
	torso.position = Vector3(0.0, 0.85, 0.0)
	dante_root.add_child(torso)

	# Pescoço
	var neck = MeshInstance3D.new()
	var cyl_nk = CylinderMesh.new()
	cyl_nk.top_radius = 0.09
	cyl_nk.bottom_radius = 0.10
	cyl_nk.height = 0.14
	neck.mesh = cyl_nk
	neck.material_override = mat_skin
	neck.position = Vector3(0.0, 0.26, 0.0)
	torso.add_child(neck)

	# Torso Principal
	var torso_mesh = MeshInstance3D.new()
	var cap_t = CapsuleMesh.new()
	cap_t.radius = 0.175
	cap_t.height = 0.48
	torso_mesh.mesh = cap_t
	torso_mesh.material_override = mat_jacket
	torso.add_child(torso_mesh)

	# Lapelas / Abertura da Roupa
	var lapel_l = MeshInstance3D.new()
	var box_ll = BoxMesh.new()
	box_ll.size = Vector3(0.045, 0.28, 0.02)
	lapel_l.mesh = box_ll
	lapel_l.material_override = mat_jacket
	lapel_l.position = Vector3(-0.06, 0.05, -0.175)
	lapel_l.rotation_degrees = Vector3(0, 0, -8)
	torso.add_child(lapel_l)

	var lapel_r = MeshInstance3D.new()
	var box_lr = BoxMesh.new()
	box_lr.size = Vector3(0.045, 0.28, 0.02)
	lapel_r.mesh = box_lr
	lapel_r.material_override = mat_jacket
	lapel_r.position = Vector3(0.06, 0.05, -0.175)
	lapel_r.rotation_degrees = Vector3(0, 0, 8)
	torso.add_child(lapel_r)

	# Detalhe do Torso de acordo com o Traje
	if accessory_type == "tie_red":
		# Camisa social branca sob o terno
		var shirt = MeshInstance3D.new()
		var box_sh = BoxMesh.new()
		box_sh.size = Vector3(0.08, 0.26, 0.015)
		shirt.mesh = box_sh
		shirt.material_override = mat_white
		shirt.position = Vector3(0.0, 0.06, -0.172)
		torso.add_child(shirt)

		# Gravata Vermelha de Seda com Nó Elegante
		var tie_knot = MeshInstance3D.new()
		var box_tk = BoxMesh.new()
		box_tk.size = Vector3(0.04, 0.04, 0.02)
		tie_knot.mesh = box_tk
		tie_knot.material_override = mat_trim
		tie_knot.position = Vector3(0.0, 0.17, -0.18)
		torso.add_child(tie_knot)

		var tie = MeshInstance3D.new()
		var box_tie = BoxMesh.new()
		box_tie.size = Vector3(0.038, 0.26, 0.016)
		tie.mesh = box_tie
		tie.material_override = mat_trim
		tie.position = Vector3(0.0, 0.03, -0.182)
		torso.add_child(tie)

	elif accessory_type == "scarf_red":
		# Cachecol Britânico envolvente ao redor da gola com nó e ponta caída
		var scarf_collar = MeshInstance3D.new()
		var cyl_sc = CylinderMesh.new()
		cyl_sc.top_radius = 0.17
		cyl_sc.bottom_radius = 0.19
		cyl_sc.height = 0.08
		scarf_collar.mesh = cyl_sc
		scarf_collar.material_override = mat_trim
		scarf_collar.position = Vector3(0.0, 0.20, 0.0)
		torso.add_child(scarf_collar)

		var scarf_knot = MeshInstance3D.new()
		var box_sk = BoxMesh.new()
		box_sk.size = Vector3(0.07, 0.08, 0.05)
		scarf_knot.mesh = box_sk
		scarf_knot.material_override = mat_trim
		scarf_knot.position = Vector3(0.03, 0.16, -0.18)
		torso.add_child(scarf_knot)

		var scarf_tail = MeshInstance3D.new()
		var box_st = BoxMesh.new()
		box_st.size = Vector3(0.06, 0.26, 0.025)
		scarf_tail.mesh = box_st
		scarf_tail.material_override = mat_trim
		scarf_tail.position = Vector3(0.03, 0.02, -0.185)
		scarf_tail.rotation_degrees = Vector3(-4, 0, -2)
		torso.add_child(scarf_tail)

	elif accessory_type == "fur_hood":
		# Capuz de Pele Polar Felpudo Envolvente
		var fur = MeshInstance3D.new()
		var cyl_fur = CylinderMesh.new()
		cyl_fur.top_radius = 0.21
		cyl_fur.bottom_radius = 0.23
		cyl_fur.height = 0.09
		fur.mesh = cyl_fur
		fur.material_override = mat_trim
		fur.position = Vector3(0.0, 0.20, 0.0)
		torso.add_child(fur)

	elif accessory_type == "bandana":
		# Bandana do Pistoleiro Triangular Dobrada
		var bandana = MeshInstance3D.new()
		var box_bn = BoxMesh.new()
		box_bn.size = Vector3(0.12, 0.14, 0.03)
		bandana.mesh = box_bn
		bandana.material_override = mat_trim
		bandana.position = Vector3(0.0, 0.16, -0.16)
		bandana.rotation_degrees = Vector3(-16, 0, 0)
		torso.add_child(bandana)

	elif accessory_type == "shoulder_pad":
		# Ombreira de Aço Mad Max no Ombro Esquerdo
		var pad = MeshInstance3D.new()
		var sph_p = SphereMesh.new()
		sph_p.radius = 0.09
		pad.mesh = sph_p
		pad.material_override = mat_silver
		pad.scale = Vector3(0.9, 0.6, 1.2)
		pad.position = Vector3(-0.24, 0.20, 0.0)
		torso.add_child(pad)

		# Correia de Couro Atravessando o Peito
		var strap = MeshInstance3D.new()
		var box_str = BoxMesh.new()
		box_str.size = Vector3(0.04, 0.36, 0.015)
		strap.mesh = box_str
		strap.material_override = _make_mat(Color("2d3436"), 0.4)
		strap.position = Vector3(-0.04, 0.05, -0.176)
		strap.rotation_degrees = Vector3(0, 0, -38)
		torso.add_child(strap)

	else:
		# Zíper Metálico
		var zipper = MeshInstance3D.new()
		var box_z = BoxMesh.new()
		box_z.size = Vector3(0.02, 0.34, 0.02)
		zipper.mesh = box_z
		zipper.material_override = mat_silver
		zipper.position = Vector3(0.0, 0.05, -0.175)
		torso.add_child(zipper)

	# Cinto com Fivela Cromada
	var belt = MeshInstance3D.new()
	var box_b = BoxMesh.new()
	box_b.size = Vector3(0.35, 0.045, 0.33)
	belt.mesh = box_b
	belt.material_override = _make_mat(Color("0d0d10"), 0.4)
	belt.position = Vector3(0.0, -0.18, 0.0)
	torso.add_child(belt)

	var buckle = MeshInstance3D.new()
	var box_bk = BoxMesh.new()
	box_bk.size = Vector3(0.06, 0.05, 0.025)
	buckle.mesh = box_bk
	buckle.material_override = mat_silver if accessory_type != "tie_red" else mat_gold
	buckle.position = Vector3(0.0, -0.18, -0.172)
	torso.add_child(buckle)

	# --- CABEÇA & ROSTO HIPER-DETALHADO DO DANTE ---
	var head = Node3D.new()
	head.position = Vector3(0.0, 1.25, 0.0)
	dante_root.add_child(head)

	# 1. Crânio & Mandíbula
	var head_mesh = MeshInstance3D.new()
	var sph_h = SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.32
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head.add_child(head_mesh)

	var jaw = MeshInstance3D.new()
	var box_jaw = BoxMesh.new()
	box_jaw.size = Vector3(0.18, 0.09, 0.14)
	jaw.mesh = box_jaw
	jaw.material_override = mat_skin
	jaw.position = Vector3(0.0, -0.10, -0.06)
	jaw.rotation_degrees = Vector3(-16, 0, 0)
	head.add_child(jaw)

	# 2. Orelhas 3D
	var ear_l = MeshInstance3D.new()
	var box_el = BoxMesh.new()
	box_el.size = Vector3(0.02, 0.06, 0.04)
	ear_l.mesh = box_el
	ear_l.material_override = mat_skin
	ear_l.position = Vector3(-0.175, 0.0, 0.0)
	head.add_child(ear_l)

	var ear_r = MeshInstance3D.new()
	var box_er = BoxMesh.new()
	box_er.size = Vector3(0.02, 0.06, 0.04)
	ear_r.mesh = box_er
	ear_r.material_override = mat_skin
	ear_r.position = Vector3(0.175, 0.0, 0.0)
	head.add_child(ear_r)

	# 3. Olhos Expressivos (Esclera Branca + Íris Escura + Destaque Frontal)
	var eye_l = MeshInstance3D.new()
	var box_eyl = BoxMesh.new()
	box_eyl.size = Vector3(0.046, 0.026, 0.018)
	eye_l.mesh = box_eyl
	eye_l.material_override = mat_white
	eye_l.position = Vector3(-0.060, 0.038, -0.170)
	head.add_child(eye_l)

	var pupil_l = MeshInstance3D.new()
	var box_pl = BoxMesh.new()
	box_pl.size = Vector3(0.022, 0.022, 0.015)
	pupil_l.mesh = box_pl
	pupil_l.material_override = mat_pupil
	pupil_l.position = Vector3(-0.060, 0.038, -0.178)
	head.add_child(pupil_l)

	var eye_r = MeshInstance3D.new()
	var box_eyr = BoxMesh.new()
	box_eyr.size = Vector3(0.046, 0.026, 0.018)
	eye_r.mesh = box_eyr
	eye_r.material_override = mat_white
	eye_r.position = Vector3(0.060, 0.038, -0.170)
	head.add_child(eye_r)

	var pupil_r = MeshInstance3D.new()
	var box_pr = BoxMesh.new()
	box_pr.size = Vector3(0.022, 0.022, 0.015)
	pupil_r.mesh = box_pr
	pupil_r.material_override = mat_pupil
	pupil_r.position = Vector3(0.060, 0.038, -0.178)
	head.add_child(pupil_r)

	# 4. Sobrancelhas Estilizadas & Expressivas
	var brow_l = MeshInstance3D.new()
	var box_brl = BoxMesh.new()
	box_brl.size = Vector3(0.052, 0.014, 0.016)
	brow_l.mesh = box_brl
	brow_l.material_override = mat_hair
	brow_l.position = Vector3(-0.060, 0.065, -0.172)
	brow_l.rotation_degrees = Vector3(0, 0, 8)
	head.add_child(brow_l)

	var brow_r = MeshInstance3D.new()
	var box_brr = BoxMesh.new()
	box_brr.size = Vector3(0.052, 0.014, 0.016)
	brow_r.mesh = box_brr
	brow_r.material_override = mat_hair
	brow_r.position = Vector3(0.060, 0.065, -0.172)
	brow_r.rotation_degrees = Vector3(0, 0, -8)
	head.add_child(brow_r)

	# 5. Nariz Esculpido em 3D
	var nose_bridge = MeshInstance3D.new()
	var box_nb = BoxMesh.new()
	box_nb.size = Vector3(0.022, 0.050, 0.026)
	nose_bridge.mesh = box_nb
	nose_bridge.material_override = mat_skin
	nose_bridge.position = Vector3(0.0, 0.022, -0.176)
	nose_bridge.rotation_degrees = Vector3(-12, 0, 0)
	head.add_child(nose_bridge)

	var nose_tip = MeshInstance3D.new()
	var box_nt = BoxMesh.new()
	box_nt.size = Vector3(0.034, 0.024, 0.028)
	nose_tip.mesh = box_nt
	nose_tip.material_override = mat_skin
	nose_tip.position = Vector3(0.0, -0.008, -0.188)
	head.add_child(nose_tip)

	# 6. Boca e Lábios Definidos
	var lips = MeshInstance3D.new()
	var box_lp = BoxMesh.new()
	box_lp.size = Vector3(0.054, 0.014, 0.016)
	lips.mesh = box_lp
	lips.material_override = mat_lips
	lips.position = Vector3(0.0, -0.060, -0.168)
	head.add_child(lips)

	# 7. Óculos Escuros Elegantes (Apenas quando o traje solicitar shades!)
	if accessory_type == "shades":
		var lens_l = MeshInstance3D.new()
		var box_llens = BoxMesh.new()
		box_llens.size = Vector3(0.048, 0.028, 0.012)
		lens_l.mesh = box_llens
		lens_l.material_override = mat_dark_shades
		lens_l.position = Vector3(-0.060, 0.038, -0.182)
		head.add_child(lens_l)

		var lens_r = MeshInstance3D.new()
		var box_rlens = BoxMesh.new()
		box_rlens.size = Vector3(0.048, 0.028, 0.012)
		lens_r.mesh = box_rlens
		lens_r.material_override = mat_dark_shades
		lens_r.position = Vector3(0.060, 0.038, -0.182)
		head.add_child(lens_r)

		var glasses_bridge = MeshInstance3D.new()
		var box_gbr = BoxMesh.new()
		box_gbr.size = Vector3(0.035, 0.006, 0.010)
		glasses_bridge.mesh = box_gbr
		glasses_bridge.material_override = mat_silver
		glasses_bridge.position = Vector3(0.0, 0.042, -0.184)
		head.add_child(glasses_bridge)

	# 8. Chapéus, Bonés e Cabelos Estilizados
	if headwear_type == "cowboy_hat":
		var hat_crown = MeshInstance3D.new()
		var cyl_c = CylinderMesh.new()
		cyl_c.top_radius = 0.16
		cyl_c.bottom_radius = 0.18
		cyl_c.height = 0.16
		hat_crown.mesh = cyl_c
		hat_crown.material_override = mat_head
		hat_crown.position = Vector3(0.0, 0.18, -0.01)
		head.add_child(hat_crown)

		var hat_band = MeshInstance3D.new()
		var cyl_bnd = CylinderMesh.new()
		cyl_bnd.top_radius = 0.182
		cyl_bnd.bottom_radius = 0.182
		cyl_bnd.height = 0.025
		hat_band.mesh = cyl_bnd
		hat_band.material_override = mat_trim
		hat_band.position = Vector3(0.0, 0.11, -0.01)
		head.add_child(hat_band)

		var hat_brim = MeshInstance3D.new()
		var cyl_br = CylinderMesh.new()
		cyl_br.top_radius = 0.32
		cyl_br.bottom_radius = 0.32
		cyl_br.height = 0.02
		hat_brim.mesh = cyl_br
		hat_brim.material_override = mat_head
		hat_brim.position = Vector3(0.0, 0.10, -0.01)
		head.add_child(hat_brim)

	elif headwear_type == "beanie":
		var beanie = MeshInstance3D.new()
		var sph_bn = SphereMesh.new()
		sph_bn.radius = 0.185
		sph_bn.height = 0.24
		beanie.mesh = sph_bn
		beanie.material_override = mat_head
		beanie.position = Vector3(0.0, 0.09, 0.0)
		head.add_child(beanie)

	elif headwear_type == "cap":
		var cap_body = MeshInstance3D.new()
		var sph_cp = SphereMesh.new()
		sph_cp.radius = 0.185
		sph_cp.height = 0.22
		cap_body.mesh = sph_cp
		cap_body.material_override = mat_head
		cap_body.position = Vector3(0.0, 0.08, -0.01)
		head.add_child(cap_body)

		var cap_brim = MeshInstance3D.new()
		var box_br = BoxMesh.new()
		box_br.size = Vector3(0.24, 0.020, 0.16)
		cap_brim.mesh = box_br
		cap_brim.material_override = mat_head
		cap_brim.position = Vector3(0.0, 0.07, -0.19)
		cap_brim.rotation_degrees = Vector3(12, 0, 0)
		head.add_child(cap_brim)

		var logo = MeshInstance3D.new()
		var box_lg = BoxMesh.new()
		box_lg.size = Vector3(0.06, 0.05, 0.01)
		logo.mesh = box_lg
		logo.material_override = mat_white
		logo.position = Vector3(0.0, 0.11, -0.16)
		head.add_child(logo)

	elif headwear_type == "cap_backwards":
		var cap_b = MeshInstance3D.new()
		var sph_cpb = SphereMesh.new()
		sph_cpb.radius = 0.185
		sph_cpb.height = 0.22
		cap_b.mesh = sph_cpb
		cap_b.material_override = mat_head
		cap_b.position = Vector3(0.0, 0.08, -0.01)
		head.add_child(cap_b)

		var brim_b = MeshInstance3D.new()
		var box_brb = BoxMesh.new()
		box_brb.size = Vector3(0.22, 0.020, 0.14)
		brim_b.mesh = box_brb
		brim_b.material_override = mat_head
		brim_b.position = Vector3(0.0, 0.07, 0.16)
		brim_b.rotation_degrees = Vector3(-12, 0, 0)
		head.add_child(brim_b)

	elif headwear_type == "tactical_helmet":
		var helmet = MeshInstance3D.new()
		var sph_hl = SphereMesh.new()
		sph_hl.radius = 0.195
		sph_hl.height = 0.24
		helmet.mesh = sph_hl
		helmet.material_override = mat_head
		helmet.position = Vector3(0.0, 0.09, 0.0)
		head.add_child(helmet)

	elif headwear_type == "goggles":
		var gog = MeshInstance3D.new()
		var box_gg = BoxMesh.new()
		box_gg.size = Vector3(0.24, 0.06, 0.06)
		gog.mesh = box_gg
		gog.material_override = mat_head
		gog.position = Vector3(0.0, 0.04, -0.16)
		head.add_child(gog)

	# Cabelo do Dante (Mechas e Caimento Natural)
	if headwear_type in ["hair_only", "goggles", "cowboy_hat"]:
		var hair_top = MeshInstance3D.new()
		var sph_ht = SphereMesh.new()
		sph_ht.radius = 0.180
		sph_ht.height = 0.20
		hair_top.mesh = sph_ht
		hair_top.material_override = mat_hair
		hair_top.position = Vector3(0.0, 0.09, 0.01)
		head.add_child(hair_top)

	var hair_back = MeshInstance3D.new()
	var box_hb = BoxMesh.new()
	box_hb.size = Vector3(0.24, 0.30, 0.10)
	hair_back.mesh = box_hb
	hair_back.material_override = mat_hair
	hair_back.position = Vector3(0.0, -0.06, 0.12)
	head.add_child(hair_back)

	var hair_l = MeshInstance3D.new()
	var box_hl = BoxMesh.new()
	box_hl.size = Vector3(0.06, 0.24, 0.08)
	hair_l.mesh = box_hl
	hair_l.material_override = mat_hair
	hair_l.position = Vector3(-0.155, -0.05, 0.02)
	head.add_child(hair_l)

	var hair_r = MeshInstance3D.new()
	var box_hr = BoxMesh.new()
	box_hr.size = Vector3(0.06, 0.24, 0.08)
	hair_r.mesh = box_hr
	hair_r.material_override = mat_hair
	hair_r.position = Vector3(0.155, -0.05, 0.02)
	head.add_child(hair_r)

	# --- BRAÇOS E MÃOS ---
	# Braço Esquerdo
	var l_arm = Node3D.new()
	l_arm.position = Vector3(-0.24, 1.05, 0.0)
	dante_root.add_child(l_arm)
	l_arm.add_child(_create_limb_mesh(0.050, 0.22, mat_jacket, Vector3(0, -0.11, 0)))

	var l_forearm = Node3D.new()
	l_forearm.position = Vector3(0, -0.22, 0)
	l_arm.add_child(l_forearm)
	l_forearm.add_child(_create_limb_mesh(0.042, 0.18, mat_jacket, Vector3(0, -0.09, 0)))

	# Relógio no pulso
	var watch = MeshInstance3D.new()
	var box_w = BoxMesh.new()
	box_w.size = Vector3(0.05, 0.03, 0.05)
	watch.mesh = box_w
	watch.material_override = mat_gold if accessory_type == "tie_red" else mat_trim
	watch.position = Vector3(-0.01, -0.14, 0.0)
	l_forearm.add_child(watch)

	var l_hand = MeshInstance3D.new()
	var box_lh = BoxMesh.new()
	box_lh.size = Vector3(0.045, 0.065, 0.05)
	l_hand.mesh = box_lh
	l_hand.material_override = mat_skin if (data.get("id") == "dante_hawaii" or data.get("id") == "dante_badboy") else mat_head
	l_hand.position = Vector3(0.0, -0.17, 0.0)
	l_forearm.add_child(l_hand)

	# Braço Direito
	var r_arm = Node3D.new()
	r_arm.position = Vector3(0.24, 1.05, 0.0)
	dante_root.add_child(r_arm)
	r_arm.add_child(_create_limb_mesh(0.050, 0.22, mat_jacket, Vector3(0, -0.11, 0)))

	var r_forearm = Node3D.new()
	r_forearm.position = Vector3(0, -0.22, 0)
	r_arm.add_child(r_forearm)
	r_forearm.add_child(_create_limb_mesh(0.042, 0.18, mat_jacket, Vector3(0, -0.09, 0)))

	var r_hand = MeshInstance3D.new()
	var box_rh = BoxMesh.new()
	box_rh.size = Vector3(0.045, 0.065, 0.05)
	r_hand.mesh = box_rh
	r_hand.material_override = mat_skin if (data.get("id") == "dante_hawaii" or data.get("id") == "dante_badboy") else mat_head
	r_hand.position = Vector3(0.0, -0.17, 0.0)
	r_forearm.add_child(r_hand)

	# --- PERNAS E BOTAS ---
	# Perna Esquerda
	var l_leg = Node3D.new()
	l_leg.position = Vector3(-0.11, 0.65, 0.0)
	dante_root.add_child(l_leg)
	l_leg.add_child(_create_limb_mesh(0.065, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	var l_lower = Node3D.new()
	l_lower.position = Vector3(0, -0.28, 0)
	l_leg.add_child(l_lower)
	l_lower.add_child(_create_limb_mesh(0.056, 0.26, mat_pants, Vector3(0, -0.13, 0)))

	var l_boot = MeshInstance3D.new()
	var box_lb = BoxMesh.new()
	box_lb.size = Vector3(0.085, 0.07, 0.16)
	l_boot.mesh = box_lb
	l_boot.material_override = mat_shoes
	l_boot.position = Vector3(0, -0.26, -0.02)
	l_lower.add_child(l_boot)

	# Perna Direita
	var r_leg = Node3D.new()
	r_leg.position = Vector3(0.11, 0.65, 0.0)
	dante_root.add_child(r_leg)
	r_leg.add_child(_create_limb_mesh(0.065, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	var r_lower = Node3D.new()
	r_lower.position = Vector3(0, -0.28, 0)
	r_leg.add_child(r_lower)
	r_lower.add_child(_create_limb_mesh(0.056, 0.26, mat_pants, Vector3(0, -0.13, 0)))

	var r_boot = MeshInstance3D.new()
	var box_rb = BoxMesh.new()
	box_rb.size = Vector3(0.085, 0.07, 0.16)
	r_boot.mesh = box_rb
	r_boot.material_override = mat_shoes
	r_boot.position = Vector3(0, -0.26, -0.02)
	r_lower.add_child(r_boot)

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb_mesh(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.88
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = offset
	return mesh_inst
