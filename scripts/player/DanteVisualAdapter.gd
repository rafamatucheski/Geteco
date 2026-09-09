class_name DanteVisualAdapter
extends RefCounted

## Adaptador visual do Dante para o Player real em produção.
## Fornece a malha 3D procedural do Dante fiel à CGI oficial (cutscenes/opening/frames/frame_v2_*.png):
## - Tom de pele moreno oliva quente e bronzeado (pele latina autêntica, #b47852)
## - Rosto viril e maduro (~30 anos) com mandíbula quadrada forte, barba por fazer (stubble) e bigode definidos
## - Olhos escuros amendoados e expressivos sob sobrancelhas marcantes
## - Cabelo preto/espresso volumoso em mechas onduladas e desfiadas com costeletas integradas à barba
## - Sobrecamisa/jaqueta flanela xadrez carvão/marinho/ardósia aberta com gola dobrada e bolsos com aba
## - Camisa henley vinho/bordô rica (#5e1924) com decote em V pronunciado e botões metálicos
## - Ombros atléticos retos e silhueta masculina V-taper
## - Cinto de couro escuro com fivela retangular de latão
## - Calça jeans azul índigo clássica com dobras sobre as botas
## - Botas pesadas de trabalho em couro com sola tratorada
## - Conexão 100% compatível com os nós de PlayerCombatPose (1H, 2H, miras, recargas),
##   ciclos de animação de caminhada/corrida, dano e catálogo de trajes.

static var _cached_plaid_texture: ImageTexture = null

static func get_plaid_texture() -> ImageTexture:
	if _cached_plaid_texture != null:
		return _cached_plaid_texture

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

	_cached_plaid_texture = ImageTexture.create_from_image(plaid_img)
	return _cached_plaid_texture

static func build_dante_rig(player: CharacterBody2D, outfit_id: String) -> void:
	if not is_instance_valid(player.model_root):
		return

	# 1. Preservar o primeiro filho da raiz (a sombra 3D) e limpar geometria anterior
	var children: Array = player.model_root.get_children()
	for i in range(children.size() - 1, 0, -1):
		var c = children[i]
		player.model_root.remove_child(c)
		c.queue_free()

	# 2. Obter dados do traje
	var data: Dictionary = OutfitCatalog.get_outfit(outfit_id) if OutfitCatalog != null else {}
	var is_canonical: bool = (outfit_id == "dante_classic" or outfit_id == "")

	# 3. Construir materiais PBR canônicos fiéis à CGI oficial
	var mat_jacket: StandardMaterial3D
	var original_jacket_color: Color

	if is_canonical:
		mat_jacket = StandardMaterial3D.new()
		mat_jacket.albedo_color = Color(1.15, 1.15, 1.15)
		mat_jacket.albedo_texture = get_plaid_texture()
		mat_jacket.uv1_scale = Vector3(3.0, 3.0, 3.0)
		mat_jacket.roughness = 0.82
		mat_jacket.metallic = 0.02
		original_jacket_color = Color(1.15, 1.15, 1.15)
	else:
		var j_col: Color = data.get("jacket_color", Color("121214"))
		mat_jacket = _make_mat(j_col, 0.5)
		original_jacket_color = j_col

	# Guardar referência no Player para efeito de dano (flash vermelho)
	player.mat_black_jacket = mat_jacket

	# Tom de pele moreno oliva quente autêntico da CGI (#b47852)
	var mat_skin: StandardMaterial3D = _make_mat(Color("#b47852"), 0.55, 0.0)
	var mat_shirt: StandardMaterial3D = _make_mat(Color("#5e1924") if is_canonical else data.get("trim_color", Color("#d63031")), 0.76)
	var mat_pants: StandardMaterial3D = _make_mat(Color("#223348") if is_canonical else data.get("pants_color", Color("18181b")), 0.70)
	var mat_hair: StandardMaterial3D = _make_mat(Color("#141316"), 0.85, 0.02)
	var mat_stubble: StandardMaterial3D = _make_mat(Color("#181514"), 0.92, 0.0)
	var mat_boots: StandardMaterial3D = _make_mat(Color("#1e1915") if is_canonical else data.get("shoes_color", Color("191919")), 0.45)
	var mat_boot_sole: StandardMaterial3D = _make_mat(Color("#0a0b0d"), 0.92)
	var mat_belt: StandardMaterial3D = _make_mat(Color("#1c1815"), 0.50)
	var mat_brass: StandardMaterial3D = _make_mat(Color("#d4ac0d"), 0.25, 0.85)
	var mat_silver_btn: StandardMaterial3D = _make_mat(Color("#ecf0f1"), 0.20, 0.90)
	var mat_sclera: StandardMaterial3D = _make_mat(Color("#e2deda"), 0.35)
	var mat_dark_pupil: StandardMaterial3D = _make_mat(Color("#120e0c"), 0.15)

	# -------------------------------------------------------------
	# 4. TORSO (tronco muscular atlético, jaqueta xadrez e camisa henley)
	# -------------------------------------------------------------
	player.torso_node = Node3D.new()
	player.torso_node.name = "TorsoNode"
	player.torso_node.position = Vector3(0.0, 0.85, 0.0)
	player.model_root.add_child(player.torso_node)

	# Pescoço anatômico moreno oliva afilando suavemente para a cabeça
	var neck := _make_tapered_limb(0.080, 0.096, 0.14, mat_skin, Vector3(0.0, 0.24, 0.0))
	player.torso_node.add_child(neck)

	# Trapézios musculares conectando pescoço e ombros com caimento orgânico
	for s in [-1, 1]:
		var trap := _make_ellipsoid(Vector3(0.085, 0.07, 0.15), mat_jacket, Vector3(float(s) * 0.09, 0.22, 0.0))
		trap.rotation_degrees = Vector3(0, 0, float(-s) * 22)
		player.torso_node.add_child(trap)

	# Camisa henley vinho/bordô rica (centro do peito e abdômen atlético)
	var henley_chest := _make_box(Vector3(0.16, 0.36, 0.17), mat_shirt, Vector3(0.0, 0.04, 0.0))
	player.torso_node.add_child(henley_chest)

	# Abertura em V da gola henley (pele exposta na clavícula)
	var chest_v := _make_box(Vector3(0.070, 0.090, 0.02), mat_skin, Vector3(0.0, 0.17, -0.09))
	player.torso_node.add_child(chest_v)

	# Carcela e botões metálicos
	var placket := _make_box(Vector3(0.026, 0.16, 0.008), mat_shirt, Vector3(0.0, 0.08, -0.089))
	player.torso_node.add_child(placket)

	for b in 3:
		var btn := _make_tapered_limb(0.007, 0.007, 0.006, mat_silver_btn, Vector3(0.0, 0.13 - float(b) * 0.045, -0.093))
		btn.rotation_degrees = Vector3(90, 0, 0)
		player.torso_node.add_child(btn)

	# Costas e tórax com silhueta V-Taper (peito superior atlético e cintura afilada)
	var jacket_back := _make_box(Vector3(0.33, 0.24, 0.18), mat_jacket, Vector3(0.0, 0.10, 0.01))
	player.torso_node.add_child(jacket_back)

	var jacket_waist := _make_box(Vector3(0.28, 0.18, 0.16), mat_jacket, Vector3(0.0, -0.07, 0.01))
	player.torso_node.add_child(jacket_waist)

	# Base dos ombros arqueada harmônica natural
	var shoulder_bar := _make_box(Vector3(0.36, 0.07, 0.17), mat_jacket, Vector3(0.0, 0.21, 0.0))
	player.torso_node.add_child(shoulder_bar)

	# Pontas dos ombros arredondadas com caimento da jaqueta
	for s in [-1, 1]:
		var shoulder_cap := _make_ellipsoid(Vector3(0.072, 0.058, 0.15), mat_jacket, Vector3(float(s) * 0.17, 0.20, 0.0))
		player.torso_node.add_child(shoulder_cap)

	# Abas frontais e bolsos com aba da sobrecamisa flanela
	for s in [-1, 1]:
		var flap := _make_box(Vector3(0.068, 0.34, 0.025), mat_jacket, Vector3(float(s) * 0.10, 0.02, -0.09))
		flap.rotation_degrees = Vector3(0, float(-s) * 6, float(s) * 2)
		player.torso_node.add_child(flap)

		var pocket := _make_box(Vector3(0.055, 0.07, 0.016), mat_jacket, Vector3(float(s) * 0.10, 0.08, -0.105))
		player.torso_node.add_child(pocket)

		var col := _make_box(Vector3(0.065, 0.065, 0.022), mat_jacket, Vector3(float(s) * 0.10, 0.21, -0.09))
		col.rotation_degrees = Vector3(16, float(-s) * 12, float(s) * 22)
		player.torso_node.add_child(col)

	# Cinto de couro com passantes e fivela retangular de latão
	var belt := _make_box(Vector3(0.29, 0.045, 0.17), mat_belt, Vector3(0.0, -0.17, 0.0))
	player.torso_node.add_child(belt)

	var buckle := _make_box(Vector3(0.054, 0.045, 0.018), mat_brass, Vector3(0.0, -0.17, -0.095))
	player.torso_node.add_child(buckle)

	# Acessórios de trajes de loja quando não canônico
	if not is_canonical:
		_apply_extra_outfit_accessories(player.torso_node, data)

	# -------------------------------------------------------------
	# 5. CABEÇA & ROSTO CANÔNICO DO DANTE (CGI FIDELITY)
	# -------------------------------------------------------------
	player.head_node = Node3D.new()
	player.head_node.name = "HeadNode"
	player.head_node.position = Vector3(0.0, 1.25, 0.0)
	player.model_root.add_child(player.head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.16
	sph_h.height = 0.30
	sph_h.radial_segments = 14
	sph_h.rings = 8
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	player.head_node.add_child(head_mesh)

	# Mandíbula quadrada e queixo firme masculino
	var jaw := MeshInstance3D.new()
	var box_jaw := BoxMesh.new()
	box_jaw.size = Vector3(0.180, 0.095, 0.145)
	jaw.mesh = box_jaw
	jaw.material_override = mat_skin
	jaw.position = Vector3(0.0, -0.09, -0.05)
	jaw.rotation_degrees = Vector3(-14, 0, 0)
	player.head_node.add_child(jaw)

	# -------------------------------------------------------------
	# BARBA CURTA CHEIA (Fiel a frame_v2_call.png e frame_v2_decision.png)
	# Barba fechada cobrindo mandíbula, queixo, cavanhaque, bigode e costeletas
	# -------------------------------------------------------------
	# Base de barba sob a mandíbula
	var stubble_jaw := _make_box(Vector3(0.188, 0.078, 0.152), mat_stubble, Vector3(0.0, -0.10, -0.055))
	stubble_jaw.rotation_degrees = Vector3(-14, 0, 0)
	player.head_node.add_child(stubble_jaw)

	# Barba cheia do queixo e cavanhaque volumoso
	var beard_chin_base := _make_box(Vector3(0.125, 0.070, 0.080), mat_stubble, Vector3(0.0, -0.115, -0.115))
	player.head_node.add_child(beard_chin_base)

	var beard_chin_front := _make_box(Vector3(0.095, 0.055, 0.035), mat_stubble, Vector3(0.0, -0.115, -0.155))
	player.head_node.add_child(beard_chin_front)

	# Bigode completo e volumoso com arco do filtro labial
	var mustache_main := _make_box(Vector3(0.118, 0.034, 0.032), mat_stubble, Vector3(0.0, -0.040, -0.168))
	player.head_node.add_child(mustache_main)

	# Soul patch (mosca) sob o lábio inferior conectando ao queixo
	var soul_patch := _make_box(Vector3(0.030, 0.036, 0.026), mat_stubble, Vector3(0.0, -0.075, -0.165))
	player.head_node.add_child(soul_patch)

	# Barba lateral ao longo da linha da mandíbula e descida dos cantos da boca
	for s in [-1, 1]:
		var mustache_tip := _make_box(Vector3(0.026, 0.034, 0.022), mat_stubble, Vector3(float(s) * 0.056, -0.056, -0.164))
		player.head_node.add_child(mustache_tip)

		var mouth_connector := _make_box(Vector3(0.028, 0.048, 0.024), mat_stubble, Vector3(float(s) * 0.048, -0.075, -0.160))
		player.head_node.add_child(mouth_connector)

		var jaw_flank := _make_box(Vector3(0.055, 0.075, 0.135), mat_stubble, Vector3(float(s) * 0.088, -0.095, -0.065))
		jaw_flank.rotation_degrees = Vector3(-14, float(s) * 6, float(s) * 4)
		player.head_node.add_child(jaw_flank)

	# Garganta e base do pescoço coberta por barba aparada
	var throat_beard := _make_box(Vector3(0.135, 0.045, 0.110), mat_stubble, Vector3(0.0, -0.138, -0.045))
	player.head_node.add_child(throat_beard)

	# Nariz angular firme masculino
	var nose := MeshInstance3D.new()
	var box_n := BoxMesh.new()
	box_n.size = Vector3(0.028, 0.058, 0.040)
	nose.mesh = box_n
	nose.material_override = mat_skin
	nose.position = Vector3(0.0, 0.015, -0.175)
	nose.rotation_degrees = Vector3(-12, 0, 0)
	player.head_node.add_child(nose)

	# Olhos profundos expressivos com esclera suave e íris escuras
	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var box_e := BoxMesh.new()
		box_e.size = Vector3(0.042, 0.022, 0.016)
		eye.mesh = box_e
		eye.material_override = mat_sclera
		eye.position = Vector3(float(side) * 0.056, 0.038, -0.158)
		player.head_node.add_child(eye)

		var pupil := MeshInstance3D.new()
		var box_p := BoxMesh.new()
		box_p.size = Vector3(0.024, 0.022, 0.016)
		pupil.mesh = box_p
		pupil.material_override = mat_dark_pupil
		pupil.position = Vector3(float(side) * 0.056, 0.038, -0.165)
		player.head_node.add_child(pupil)

		# -------------------------------------------------------------
		# SOBRANCELHAS GROSSAS (Fiel à CGI: densas, anguladas e marcantes)
		# -------------------------------------------------------------
		var brow_inner := _make_box(Vector3(0.056, 0.028, 0.026), mat_hair, Vector3(float(side) * 0.048, 0.065, -0.166))
		brow_inner.rotation_degrees = Vector3(-5, float(side) * 5, float(side) * 12)
		player.head_node.add_child(brow_inner)

		var brow_outer := _make_box(Vector3(0.042, 0.022, 0.022), mat_hair, Vector3(float(side) * 0.086, 0.058, -0.160))
		brow_outer.rotation_degrees = Vector3(-4, float(side) * 10, float(-side) * 16)
		player.head_node.add_child(brow_outer)

		# Orelhas anatômicas
		var ear := MeshInstance3D.new()
		var box_ear := BoxMesh.new()
		box_ear.size = Vector3(0.024, 0.062, 0.042)
		ear.mesh = box_ear
		ear.material_override = mat_skin
		ear.position = Vector3(float(side) * 0.165, 0.01, -0.01)
		player.head_node.add_child(ear)

	# Fissura glabelar sutil entre as sobrancelhas (determinação e foco)
	var brow_center := _make_box(Vector3(0.022, 0.024, 0.016), mat_hair, Vector3(0.0, 0.068, -0.170))
	player.head_node.add_child(brow_center)

	# Cabelo preto curto e espetado (fiel à CGI e frame_v2_call.png)
	_build_cgi_hair(player.head_node, mat_hair)

	# -------------------------------------------------------------
	# 6. BRAÇOS & ARTICULAÇÕES (Deltoides, Bíceps, Cotovelos e Mãos com Dedos)
	# -------------------------------------------------------------
	for s in [-1, 1]:
		var side_str := "Left" if s < 0 else "Right"
		var upper_arm := Node3D.new()
		upper_arm.name = side_str + "UpperArm"
		upper_arm.position = Vector3(float(s) * 0.185, 1.05, 0.0)
		player.model_root.add_child(upper_arm)
		if s < 0: player.left_upper_arm = upper_arm
		else: player.right_upper_arm = upper_arm

		var deltoid := _make_ellipsoid(Vector3(0.072, 0.082, 0.074), mat_jacket, Vector3(0.0, 0.0, 0.0))
		upper_arm.add_child(deltoid)

		var uarm_mesh := _make_tapered_limb(0.068, 0.055, 0.22, mat_jacket, Vector3(0.0, -0.11, 0.0))
		upper_arm.add_child(uarm_mesh)

		var elbow_mesh := _make_ellipsoid(Vector3(0.056, 0.056, 0.056), mat_jacket, Vector3(0.0, -0.21, 0.0))
		upper_arm.add_child(elbow_mesh)

		var lower_arm := Node3D.new()
		lower_arm.name = side_str + "LowerArm"
		lower_arm.position = Vector3(0.0, -0.22, 0.0)
		upper_arm.add_child(lower_arm)
		if s < 0: player.left_lower_arm = lower_arm
		else: player.right_lower_arm = lower_arm

		var larm_mesh := _make_tapered_limb(0.054, 0.042, 0.18, mat_jacket, Vector3(0.0, -0.09, 0.0))
		lower_arm.add_child(larm_mesh)

		var cuff_mesh := _make_tapered_limb(0.048, 0.048, 0.024, mat_jacket, Vector3(0.0, -0.165, 0.0))
		lower_arm.add_child(cuff_mesh)

		var hand_mesh := _make_box(Vector3(0.054, 0.058, 0.048), mat_skin, Vector3(0.0, -0.20, 0.0))
		var palm := Node3D.new()
		palm.name = "Palm"
		palm.position = Vector3(0, -0.20, 0)
		lower_arm.add_child(palm)
		hand_mesh.position -= palm.position
		palm.add_child(hand_mesh)

		var thumb_mesh := _make_ellipsoid(Vector3(0.024, 0.042, 0.024), mat_skin, Vector3(float(s) * 0.028, -0.19, -0.016))
		thumb_mesh.rotation_degrees = Vector3(-15, float(s) * 25, float(-s) * 15)
		thumb_mesh.position -= palm.position
		palm.add_child(thumb_mesh)

		var fingers_mesh := _make_box(Vector3(0.048, 0.026, 0.022), mat_skin, Vector3(0.0, -0.228, -0.012))
		fingers_mesh.position -= palm.position
		palm.add_child(fingers_mesh)

		if s > 0:
			player.weapon_mount_node = Node3D.new()
			player.weapon_mount_node.name = "WeaponMount"
			player.weapon_mount_node.position = Vector3(0.0, -0.20, 0.0)
			lower_arm.add_child(player.weapon_mount_node)
			player._update_equipped_weapon_3d_mesh()

	# -------------------------------------------------------------
	# 7. PERNAS & ARTICULAÇÕES (Coxas, Joelhos, Canelas e Botas com Solado)
	# -------------------------------------------------------------
	for s in [-1, 1]:
		var side_str := "Left" if s < 0 else "Right"
		var upper_leg := Node3D.new()
		upper_leg.name = side_str + "UpperLeg"
		upper_leg.position = Vector3(float(s) * 0.088, 0.70, 0.0)
		player.model_root.add_child(upper_leg)
		if s < 0: player.left_upper_leg = upper_leg
		else: player.right_upper_leg = upper_leg

		var hip_mesh := _make_ellipsoid(Vector3(0.082, 0.082, 0.082), mat_pants, Vector3(0.0, 0.0, 0.0))
		upper_leg.add_child(hip_mesh)

		var uleg_mesh := _make_tapered_limb(0.078, 0.062, 0.32, mat_pants, Vector3(0.0, -0.16, 0.0))
		upper_leg.add_child(uleg_mesh)

		var knee_mesh := _make_ellipsoid(Vector3(0.062, 0.062, 0.062), mat_pants, Vector3(0.0, -0.32, 0.0))
		upper_leg.add_child(knee_mesh)

		var lower_leg := Node3D.new()
		lower_leg.name = side_str + "LowerLeg"
		lower_leg.position = Vector3(0.0, -0.34, 0.0)
		upper_leg.add_child(lower_leg)
		if s < 0: player.left_lower_leg = lower_leg
		else: player.right_lower_leg = lower_leg

		var lleg_mesh := _make_tapered_limb(0.060, 0.052, 0.30, mat_pants, Vector3(0.0, -0.15, 0.0))
		lower_leg.add_child(lleg_mesh)

		var cuff_fold := _make_tapered_limb(0.056, 0.056, 0.040, mat_pants, Vector3(0.0, -0.24, 0.0))
		lower_leg.add_child(cuff_fold)

		var boot_shaft := _make_box(Vector3(0.092, 0.082, 0.11), mat_boots, Vector3(0.0, -0.26, 0.0))
		lower_leg.add_child(boot_shaft)

		var boot_toe := _make_ellipsoid(Vector3(0.094, 0.065, 0.12), mat_boots, Vector3(0.0, -0.28, -0.07))
		lower_leg.add_child(boot_toe)

		var boot_heel := _make_ellipsoid(Vector3(0.088, 0.065, 0.08), mat_boots, Vector3(0.0, -0.28, 0.04))
		lower_leg.add_child(boot_heel)

		var sole_tread := _make_box(Vector3(0.098, 0.024, 0.16), mat_boot_sole, Vector3(0.0, -0.315, -0.04))
		lower_leg.add_child(sole_tread)

		var heel_block := _make_box(Vector3(0.098, 0.036, 0.07), mat_boot_sole, Vector3(0.0, -0.325, 0.04))
		lower_leg.add_child(heel_block)

static func _build_cgi_hair(head: Node3D, mat_hair: Material) -> void:
	# -------------------------------------------------------------
	# CABELO PRETO CURTO E ESPETADO (CGI FIDELITY)
	# Fiel a cutscenes/opening/frames/frame_v2_call.png e frame_v2_decision.png:
	# Base compacta anatômica, mechas espetadas anguladas irradiando na coroa,
	# franja com pontas desfiadas sobre a testa e costeletas integradas à barba.
	# -------------------------------------------------------------
	# 1. Base Craniana Compacta (sem aspecto de capacete ou ondas bulbosas)
	var skull_base := _make_ellipsoid(Vector3(0.33, 0.19, 0.32), mat_hair, Vector3(0.0, 0.075, 0.005))
	skull_base.name = "HairSkullBase"
	head.add_child(skull_base)

	# 2. Feixe Central e Pontas Espetadas na Coroa (Spikes do Topo)
	var crown_spike_center := _make_box(Vector3(0.052, 0.085, 0.052), mat_hair, Vector3(0.0, 0.170, 0.020))
	crown_spike_center.name = "CrownSpikeCenter"
	crown_spike_center.rotation_degrees = Vector3(14, 0, 4)
	head.add_child(crown_spike_center)

	var crown_spike_l := _make_box(Vector3(0.046, 0.082, 0.046), mat_hair, Vector3(-0.065, 0.162, -0.035))
	crown_spike_l.name = "CrownSpikeL"
	crown_spike_l.rotation_degrees = Vector3(18, -14, -18)
	head.add_child(crown_spike_l)

	var crown_spike_r := _make_box(Vector3(0.046, 0.082, 0.046), mat_hair, Vector3(0.065, 0.162, -0.030))
	crown_spike_r.name = "CrownSpikeR"
	crown_spike_r.rotation_degrees = Vector3(16, 12, 16)
	head.add_child(crown_spike_r)

	var crown_spike_back := _make_box(Vector3(0.054, 0.078, 0.050), mat_hair, Vector3(0.0, 0.158, 0.075))
	crown_spike_back.name = "CrownSpikeBack"
	crown_spike_back.rotation_degrees = Vector3(-16, 0, 0)
	head.add_child(crown_spike_back)

	var crown_spike_bl := _make_box(Vector3(0.046, 0.074, 0.046), mat_hair, Vector3(-0.075, 0.148, 0.060))
	crown_spike_bl.name = "CrownSpikeBL"
	crown_spike_bl.rotation_degrees = Vector3(-14, -22, -18)
	head.add_child(crown_spike_bl)

	var crown_spike_br := _make_box(Vector3(0.046, 0.074, 0.046), mat_hair, Vector3(0.075, 0.148, 0.055))
	crown_spike_br.name = "CrownSpikeBR"
	crown_spike_br.rotation_degrees = Vector3(-12, 18, 16)
	head.add_child(crown_spike_br)

	# 3. Franja Espetada em Mechas Afuniladas sobre a Testa (Fringe Locks da CGI)
	var fringe_center := _make_box(Vector3(0.038, 0.072, 0.032), mat_hair, Vector3(0.0, 0.105, -0.158))
	fringe_center.name = "FringeCenter"
	fringe_center.rotation_degrees = Vector3(28, 0, 0)
	head.add_child(fringe_center)

	var fringe_in_l := _make_box(Vector3(0.034, 0.068, 0.030), mat_hair, Vector3(-0.044, 0.108, -0.152))
	fringe_in_l.name = "FringeInL"
	fringe_in_l.rotation_degrees = Vector3(26, -12, -14)
	head.add_child(fringe_in_l)

	var fringe_in_r := _make_box(Vector3(0.034, 0.068, 0.030), mat_hair, Vector3(0.044, 0.110, -0.150))
	fringe_in_r.name = "FringeInR"
	fringe_in_r.rotation_degrees = Vector3(24, 10, 12)
	head.add_child(fringe_in_r)

	var fringe_out_l := _make_box(Vector3(0.032, 0.064, 0.028), mat_hair, Vector3(-0.082, 0.100, -0.142))
	fringe_out_l.name = "FringeOutL"
	fringe_out_l.rotation_degrees = Vector3(22, -20, -22)
	head.add_child(fringe_out_l)

	var fringe_out_r := _make_box(Vector3(0.032, 0.064, 0.028), mat_hair, Vector3(0.082, 0.102, -0.140))
	fringe_out_r.name = "FringeOutR"
	fringe_out_r.rotation_degrees = Vector3(20, 18, 20)
	head.add_child(fringe_out_r)

	# Pontas menores desfiadas na linha da testa (locks afiados)
	var flick_l := _make_box(Vector3(0.022, 0.046, 0.020), mat_hair, Vector3(-0.022, 0.076, -0.166))
	flick_l.name = "FlickL"
	flick_l.rotation_degrees = Vector3(34, -6, -10)
	head.add_child(flick_l)

	var flick_r := _make_box(Vector3(0.022, 0.046, 0.020), mat_hair, Vector3(0.024, 0.078, -0.164))
	flick_r.name = "FlickR"
	flick_r.rotation_degrees = Vector3(32, 8, 12)
	head.add_child(flick_r)

	# 4. Spikes Laterais e Têmporas (irradiando para fora)
	for s in [-1, 1]:
		var side_top_spike := _make_box(Vector3(0.044, 0.062, 0.052), mat_hair, Vector3(float(s) * 0.152, 0.112, -0.020))
		side_top_spike.name = ("SideTopSpikeL" if s < 0 else "SideTopSpikeR")
		side_top_spike.rotation_degrees = Vector3(8, float(-s) * 12, float(s) * 30)
		head.add_child(side_top_spike)

		var side_mid_spike := _make_box(Vector3(0.040, 0.058, 0.048), mat_hair, Vector3(float(s) * 0.158, 0.065, 0.010))
		side_mid_spike.name = ("SideMidSpikeL" if s < 0 else "SideMidSpikeR")
		side_mid_spike.rotation_degrees = Vector3(0, float(-s) * 15, float(s) * 34)
		head.add_child(side_mid_spike)

		# Costeletas conectadas à barba cheia
		var burn := _make_box(Vector3(0.026, 0.072, 0.042), mat_hair, Vector3(float(s) * 0.160, 0.020, -0.065))
		burn.name = ("SideburnL" if s < 0 else "SideburnR")
		burn.rotation_degrees = Vector3(10, float(-s) * 8, float(s) * 4)
		head.add_child(burn)

		var burn_low := _make_box(Vector3(0.026, 0.052, 0.038), mat_hair, Vector3(float(s) * 0.154, -0.032, -0.078))
		burn_low.name = ("SideburnLowL" if s < 0 else "SideburnLowR")
		burn_low.rotation_degrees = Vector3(12, float(-s) * 8, float(s) * 4)
		head.add_child(burn_low)

	# 5. Camadas Traseiras Espetadas na Nuca
	for s in [-1, 0, 1]:
		var nape_spike_u := _make_box(Vector3(0.062, 0.062, 0.048), mat_hair, Vector3(float(s) * 0.072, 0.055, 0.142))
		nape_spike_u.name = "NapeSpikeU" + str(s)
		nape_spike_u.rotation_degrees = Vector3(-26, float(-s) * 14, float(s) * 10)
		head.add_child(nape_spike_u)

		var nape_spike_d := _make_box(Vector3(0.052, 0.052, 0.044), mat_hair, Vector3(float(s) * 0.062, -0.015, 0.138))
		nape_spike_d.name = "NapeSpikeD" + str(s)
		nape_spike_d.rotation_degrees = Vector3(-32, float(-s) * 12, float(s) * 8)
		head.add_child(nape_spike_d)

static func _apply_extra_outfit_accessories(torso: Node3D, data: Dictionary) -> void:
	var accessory: String = data.get("accessory_type", "")
	if accessory == "fur_hood":
		var fabric := _make_mat(data.get("jacket_color",Color("2e86de")),.9)
		for y in [-.09,0,.09]:
			torso.add_child(_make_ellipsoid(Vector3(.34,.10,.24),fabric,Vector3(0,y,0)))
		var fur := _make_mat(Color("bcb7a7"),.95)
		for side in [-1,1]:
			torso.add_child(_make_ellipsoid(Vector3(.09,.12,.19),fur,Vector3(side*.13,.24,.025)))
		torso.add_child(_make_ellipsoid(Vector3(.28,.10,.12),fur,Vector3(0,.25,.12)))
	elif accessory == "scarf_red":
		var wool := _make_mat(Color("8c3238"),.95)
		torso.add_child(_make_ellipsoid(Vector3(.30,.10,.23),wool,Vector3(0,.23,0)))
		torso.add_child(_make_box(Vector3(.075,.28,.035),wool,Vector3(.08,.06,-.14)))
	var cat: String = data.get("category", "")
	if cat == "biker":
		var chain := _make_box(Vector3(0.03, 0.12, 0.01), _make_mat(Color("bdc3c7"), 0.2, 0.9), Vector3(0.13, -0.08, 0.09))
		torso.add_child(chain)
	elif cat == "military":
		for s in [-1, 1]:
			var epaulet := _make_box(Vector3(0.06, 0.015, 0.08), _make_mat(Color("192a56"), 0.5), Vector3(float(s) * 0.16, 0.23, 0.0))
			torso.add_child(epaulet)

static func _make_mat(albedo: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m

static func _make_ellipsoid(scale_vec: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_vec
	return mi

static func _make_tapered_limb(top_r: float, bot_r: float, h: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = h
	mesh.radial_segments = 14
	mesh.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi

static func _make_box(size_vec: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_vec
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi
