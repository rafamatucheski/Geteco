class_name DanteVisualAdapter
extends RefCounted

## Production Dante: proportions, dark flannel, burgundy henley and swept
## black hair follow prototypes/menu_concept/dante_sunset_preview.png.
## Articulated nodes retain the combat, wardrobe and vehicle contracts.

static var _cached_plaid_texture: ImageTexture = null

static func get_plaid_texture() -> ImageTexture:
	if _cached_plaid_texture != null:
		return _cached_plaid_texture

	var plaid_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var col_base := Color("#1a2028") # Carvão escuro base
	var col_navy := Color("#131b26") # Faixa azul marinho profundo
	var col_slate := Color("#252b32") # Linha cinza ardósia média
	var col_accent := Color("#303239") # Fio sutil de realce

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

	if is_canonical:
		mat_jacket = StandardMaterial3D.new()
		mat_jacket.albedo_color = Color(1.15, 1.15, 1.15)
		mat_jacket.albedo_texture = get_plaid_texture()
		mat_jacket.uv1_scale = Vector3(1.0, 1.0, 1.0)
		mat_jacket.roughness = 0.82
		mat_jacket.metallic = 0.02
	else:
		var j_col: Color = data.get("jacket_color", Color("121214"))
		mat_jacket = _make_mat(j_col, 0.5)

	# Guardar referência no Player para efeito de dano (flash vermelho)
	mat_jacket.set_meta("rest_albedo", mat_jacket.albedo_color)
	player.mat_black_jacket = mat_jacket

	# Tom de pele moreno oliva quente autêntico da CGI (#b47852)
	var mat_skin: StandardMaterial3D = _make_mat(Color("#a97653"), 0.55, 0.0)
	var mat_shirt: StandardMaterial3D = _make_mat(Color("#5e1924") if is_canonical else data.get("trim_color", Color("#d63031")), 0.76)
	var mat_pants: StandardMaterial3D = _make_mat(Color("#151c27") if is_canonical else data.get("pants_color", Color("18181b")), 0.70)
	var mat_hair: StandardMaterial3D = _make_mat(Color("#141316"), 0.85, 0.02)
	mat_hair.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mat_stubble: StandardMaterial3D = _make_mat(Color("#181514"), 0.92, 0.0)
	var mat_boots: StandardMaterial3D = _make_mat(Color("#1e1915") if is_canonical else data.get("shoes_color", Color("191919")), 0.45)
	var mat_boot_sole: StandardMaterial3D = _make_mat(Color("#0a0b0d"), 0.92)
	var mat_belt: StandardMaterial3D = _make_mat(Color("#1c1815"), 0.50)
	var mat_brass: StandardMaterial3D = _make_mat(Color("#776753"), 0.25, 0.85)
	var mat_silver_btn: StandardMaterial3D = _make_mat(Color("#ecf0f1"), 0.20, 0.90)

	# -------------------------------------------------------------
	# 4. TORSO (tronco muscular atlético, jaqueta xadrez e camisa henley)
	# -------------------------------------------------------------
	player.torso_node = Node3D.new()
	player.torso_node.name = "TorsoNode"
	player.torso_node.position = Vector3(0.0, 0.85, 0.0)
	player.model_root.add_child(player.torso_node)

	# Pescoço anatômico moreno oliva afilando suavemente para a cabeça
	var neck := _make_tapered_limb(0.050, 0.065, 0.14, mat_skin, Vector3(0.0, 0.24, 0.0))
	player.torso_node.add_child(neck)

	# Trapézios musculares conectando pescoço e ombros com caimento orgânico
	for s in [-1, 1]:
		var trap := _make_ellipsoid(Vector3(0.085, 0.07, 0.15), mat_jacket, Vector3(float(s) * 0.09, 0.22, 0.0))
		trap.rotation_degrees = Vector3(0, 0, float(-s) * 22)
		player.torso_node.add_child(trap)

	# Camisa henley vinho/bordô rica (centro do peito e abdômen atlético)
	var henley_chest := _make_box(Vector3(0.16, 0.36, 0.055), mat_shirt, Vector3(0.0, 0.04, -0.062))
	player.torso_node.add_child(henley_chest)

	# Abertura em V da gola henley (pele exposta na clavícula)
	var chest_v := _make_box(Vector3(0.040, 0.060, 0.02), mat_skin, Vector3(0.0, 0.18, -0.10))
	player.torso_node.add_child(chest_v)

	# Carcela e botões metálicos
	var placket := _make_box(Vector3(0.026, 0.16, 0.008), mat_shirt, Vector3(0.0, 0.08, -0.089))
	player.torso_node.add_child(placket)

	for b in 3:
		var btn := _make_tapered_limb(0.007, 0.007, 0.006, mat_silver_btn, Vector3(0.0, 0.13 - float(b) * 0.045, -0.093))
		btn.rotation_degrees = Vector3(90, 0, 0)
		player.torso_node.add_child(btn)

	var jacket_back := _make_loft([
		Vector4(-0.16, 0.142, 0.074, 0.016), Vector4(-0.04, 0.148, 0.080, 0.016),
		Vector4(0.12, 0.175, 0.084, 0.012), Vector4(0.20, 0.177, 0.076, 0.012),
		Vector4(0.235, 0.095, 0.065, 0.012)], mat_jacket)
	jacket_back.name = "OvershirtBody"
	player.torso_node.add_child(jacket_back)

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

	var buckle := _make_box(Vector3(0.042, 0.032, 0.018), mat_brass, Vector3(0.0, -0.17, -0.095))
	player.torso_node.add_child(buckle)

	# Acessórios de trajes de loja quando não canônico
	if not is_canonical:
		_apply_extra_outfit_accessories(player.torso_node, data)

	# -------------------------------------------------------------
	# 5. CABEÇA & ROSTO CANÔNICO DO DANTE (CGI FIDELITY)
	# -------------------------------------------------------------
	player.head_node = Node3D.new()
	player.head_node.name = "HeadNode"
	player.head_node.position = Vector3(0.0, 1.21, 0.0)
	player.model_root.add_child(player.head_node)

	_build_menu_face(player.head_node, mat_skin, mat_hair, mat_stubble)

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

		var deltoid := _make_ellipsoid(Vector3(0.108, 0.080, 0.104), mat_jacket, Vector3(0.0, -0.018, 0.0))
		upper_arm.add_child(deltoid)

		var uarm_mesh := _make_tapered_limb(0.055, 0.046, 0.22, mat_jacket, Vector3(0.0, -0.11, 0.0))
		upper_arm.add_child(uarm_mesh)

		var elbow_mesh := _make_ellipsoid(Vector3(0.094, 0.088, 0.094), mat_jacket, Vector3(0.0, -0.21, 0.0))
		upper_arm.add_child(elbow_mesh)

		var lower_arm := Node3D.new()
		lower_arm.name = side_str + "LowerArm"
		lower_arm.position = Vector3(0.0, -0.22, 0.0)
		upper_arm.add_child(lower_arm)
		if s < 0: player.left_lower_arm = lower_arm
		else: player.right_lower_arm = lower_arm

		var larm_mesh := _make_tapered_limb(0.046, 0.036, 0.18, mat_jacket, Vector3(0.0, -0.09, 0.0))
		lower_arm.add_child(larm_mesh)

		var cuff_mesh := _make_tapered_limb(0.039, 0.039, 0.024, mat_jacket, Vector3(0.0, -0.165, 0.0))
		lower_arm.add_child(cuff_mesh)

		var hand_mesh := _make_box(Vector3(0.054, 0.058, 0.048), mat_skin, Vector3(0.0, -0.20, 0.0))
		var palm := Node3D.new()
		palm.name = "Palm"
		palm.position = Vector3(0, -0.20, 0)
		lower_arm.add_child(palm)
		hand_mesh.position -= palm.position
		hand_mesh.name = "PalmBack"
		hand_mesh.set_meta("rest_transform", hand_mesh.transform)
		palm.add_child(hand_mesh)

		var thumb_mesh := _make_ellipsoid(Vector3(0.024, 0.042, 0.024), mat_skin, Vector3(float(s) * 0.028, -0.19, -0.016))
		thumb_mesh.rotation_degrees = Vector3(-15, float(s) * 25, float(-s) * 15)
		thumb_mesh.position -= palm.position
		thumb_mesh.name = "Thumb"
		thumb_mesh.set_meta("rest_transform", thumb_mesh.transform)
		palm.add_child(thumb_mesh)

		var fingers_mesh := _make_box(Vector3(0.048, 0.026, 0.022), mat_skin, Vector3(0.0, -0.228, -0.012))
		fingers_mesh.position -= palm.position
		fingers_mesh.name = "Fingers"
		fingers_mesh.set_meta("rest_transform", fingers_mesh.transform)
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
		upper_leg.position = Vector3(float(s) * 0.088, 0.684, 0.0)
		player.model_root.add_child(upper_leg)
		if s < 0: player.left_upper_leg = upper_leg
		else: player.right_upper_leg = upper_leg

		var hip_mesh := _make_ellipsoid(Vector3(0.082, 0.082, 0.082), mat_pants, Vector3(0.0, 0.0, 0.0))
		upper_leg.add_child(hip_mesh)

		var uleg_mesh := _make_tapered_limb(0.078, 0.062, 0.32, mat_pants, Vector3(0.0, -0.16, 0.0))
		upper_leg.add_child(uleg_mesh)

		var knee_mesh := _make_ellipsoid(Vector3(0.124, 0.100, 0.124), mat_pants, Vector3(0.0, -0.32, 0.0))
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

		var foot := Node3D.new()
		foot.name = "Foot"
		foot.position = Vector3(0, -0.30, 0)
		lower_leg.add_child(foot)
		var boot_shaft := _make_box(Vector3(0.092, 0.082, 0.11), mat_boots, Vector3(0.0, 0.04, 0.0))
		foot.add_child(boot_shaft)

		var boot_toe := _make_ellipsoid(Vector3(0.105, 0.085, 0.17), mat_boots, Vector3(0.0, 0.02, -0.07))
		foot.add_child(boot_toe)

		var boot_heel := _make_ellipsoid(Vector3(0.088, 0.065, 0.08), mat_boots, Vector3(0.0, 0.02, 0.04))
		foot.add_child(boot_heel)

		var sole_tread := _make_box(Vector3(0.108, 0.024, 0.205), mat_boot_sole, Vector3(0.0, -0.015, -0.04))
		foot.add_child(sole_tread)

		var heel_block := _make_box(Vector3(0.098, 0.036, 0.07), mat_boot_sole, Vector3(0.0, -0.025, 0.04))
		foot.add_child(heel_block)

static func _build_menu_face(head: Node3D, skin: Material, hair: Material, beard: Material) -> void:
	# Narrow temples, cheekbones and a tapered square jaw; no spherical head.
	head.scale = Vector3(0.94, 0.88, 0.94)
	var face := _make_loft([
		Vector4(-0.125, 0.054, 0.052, -0.018), Vector4(-0.095, 0.082, 0.066, -0.009),
		Vector4(-0.045, 0.102, 0.078, 0.0), Vector4(0.025, 0.107, 0.083, 0.0),
		Vector4(0.085, 0.102, 0.080, 0.006), Vector4(0.125, 0.075, 0.062, 0.012),
		Vector4(0.14, 0.018, 0.025, 0.012)], skin)
	face.name = "Face"
	head.add_child(face)
	var beard_base := _make_loft([
		Vector4(-0.135, 0.051, 0.049, -0.024), Vector4(-0.113, 0.072, 0.064, -0.019),
		Vector4(-0.081, 0.092, 0.075, -0.013), Vector4(-0.048, 0.102, 0.079, -0.005)], beard)
	beard_base.name = "ShortBeard"
	head.add_child(beard_base)
	var lip := _make_ellipsoid(Vector3(0.054, 0.010, 0.012), _make_mat(Color("704734"), 0.9), Vector3(0, -0.065, -0.097))
	head.add_child(lip)
	for side in [-1, 1]:
		var mustache := _make_ellipsoid(Vector3(0.048, 0.019, 0.018), beard, Vector3(side * 0.022, -0.049, -0.092))
		mustache.rotation.z = side * -0.15
		head.add_child(mustache)
		var cheek_beard := _make_ellipsoid(Vector3(0.030, 0.065, 0.115), beard, Vector3(side * 0.085, -0.046, -0.008))
		cheek_beard.rotation.z = side * -0.35
		head.add_child(cheek_beard)
		var ear := _make_ellipsoid(Vector3(0.026, 0.051, 0.029), skin, Vector3(side * 0.107, -0.008, 0.008))
		head.add_child(ear)
		var socket := _make_ellipsoid(Vector3(0.052, 0.023, 0.018), _make_mat(Color("754d38"), 0.9), Vector3(side * 0.044, 0.020, -0.080))
		head.add_child(socket)
		var eye := _make_ellipsoid(Vector3(0.034, 0.012, 0.012), _make_mat(Color("b6a08a"), 0.65), Vector3(side * 0.044, 0.019, -0.090))
		head.add_child(eye)
		head.add_child(_make_ellipsoid(Vector3(0.014, 0.012, 0.010), hair, Vector3(side * 0.043, 0.019, -0.096)))
		var brow := _make_ellipsoid(Vector3(0.060, 0.016, 0.020), hair, Vector3(side * 0.044, 0.039, -0.087))
		brow.rotation.z = side * 0.14
		head.add_child(brow)
	var nose := _make_loft([
		Vector4(-0.031, 0.018, 0.012, -0.103), Vector4(-0.019, 0.017, 0.022, -0.106),
		Vector4(0.043, 0.009, 0.012, -0.082)], skin, 8)
	head.add_child(nose)
	_build_menu_hair(head, hair)

static func _build_menu_hair(head: Node3D, hair: Material) -> void:
	# One continuous scalp with a shaped hairline, covered by curved clumps.
	# The locks follow the skull instead of radiating out like triangular spikes.
	var matte := hair.duplicate() as StandardMaterial3D
	matte.albedo_color = Color("101013")
	matte.roughness = 1.0
	matte.metallic = 0.0
	matte.metallic_specular = 0.12
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 32
	const RINGS := 12
	for row in RINGS + 1:
		for column in SEGMENTS + 1:
			var theta := float(column) / SEGMENTS * TAU
			var front := maxf(0.0, -cos(theta))
			var back := maxf(0.0, cos(theta))
			var boundary := 1.92 - 0.58 * pow(front, 3.0) + 0.25 * back
			boundary += sin(theta * 5.0 + 0.6) * 0.025
			var phi := float(row) / RINGS * boundary
			var point := Vector3(sin(theta) * sin(phi) * 0.113,
				0.026 + cos(phi) * 0.144, 0.014 + cos(theta) * sin(phi) * 0.100)
			surface.add_vertex(point)
	for row in RINGS:
		for column in SEGMENTS:
			var index := row * (SEGMENTS + 1) + column
			for vertex in [index, index + 1, index + SEGMENTS + 2, index, index + SEGMENTS + 2, index + SEGMENTS + 1]:
				surface.add_index(vertex)
	surface.generate_normals()
	var crown := MeshInstance3D.new()
	crown.name = "HairCrown"
	crown.mesh = surface.commit()
	crown.material_override = matte
	head.add_child(crown)
	# Broad overlapping waves: an off-centre part and a few uneven fringe ends.
	var fringe := [
		[Vector3(-0.066, 0.133, 0.016), Vector3(-0.100, 0.149, -0.073), Vector3(-0.092, 0.034, -0.065), 0.020],
		[Vector3(-0.030, 0.160, 0.020), Vector3(-0.070, 0.166, -0.070), Vector3(-0.060, 0.035, -0.083), 0.024],
		[Vector3(0.008, 0.163, 0.015), Vector3(-0.020, 0.167, -0.095), Vector3(-0.035, 0.050, -0.093), 0.024],
		[Vector3(0.042, 0.153, 0.023), Vector3(0.025, 0.173, -0.079), Vector3(0.006, 0.042, -0.096), 0.023],
		[Vector3(0.068, 0.140, 0.025), Vector3(0.069, 0.142, -0.084), Vector3(0.052, 0.058, -0.089), 0.024],
		[Vector3(0.087, 0.120, 0.024), Vector3(0.109, 0.110, -0.051), Vector3(0.084, 0.026, -0.064), 0.020]]
	for lock in fringe:
		_add_hair_lock(head, lock[0], lock[1], lock[2], lock[3], matte)
	# Close-fitting temple and nape layers; nothing fans outward at ear level.
	for side in [-1, 1]:
		for i in 4:
			var z := -0.032 + i * 0.030
			_add_hair_lock(head, Vector3(side * 0.078, 0.127, z),
				Vector3(side * 0.116, 0.062, z + 0.010),
				Vector3(side * 0.096, -0.027 + float(i % 2) * 0.012, z + 0.020), 0.018, matte)
	for i in 5:
		var x := (i - 2) * 0.036
		_add_hair_lock(head, Vector3(x, 0.132, 0.058),
			Vector3(x + 0.010, 0.073, 0.124),
			Vector3(x + 0.007, -0.060 + float(i % 2) * 0.012, 0.085), 0.022, matte)

static func _add_hair_lock(parent: Node3D, start: Vector3, control: Vector3, tip: Vector3, width: float, mat: Material) -> void:
	# A solid curved ribbon, softly rounded across its width and tapered at
	# the end. Shared vertices give continuous normals along each lock.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 8
	const SIDES := 8
	for step in STEPS + 1:
		var t := float(step) / STEPS
		var point := start.bezier_interpolate(control, control, tip, t)
		var axis := (control - start).lerp(tip - control, t).normalized()
		var outward := (point - Vector3(0, 0.020, 0.008)).normalized()
		var across := axis.cross(outward).normalized()
		var normal := across.cross(axis).normalized()
		var taper := maxf(0.025, sin((0.20 + 0.80 * t) * PI))
		for side in SIDES:
			var angle := float(side) / SIDES * TAU
			surface.add_vertex(point + across * cos(angle) * width * taper + normal * sin(angle) * 0.006 * taper)
	for step in STEPS:
		for side in SIDES:
			var a := step * SIDES + side
			var b := step * SIDES + (side + 1) % SIDES
			for vertex in [a, b + SIDES, b, a, a + SIDES, b + SIDES]:
				surface.add_index(vertex)
	surface.generate_normals()
	var lock := MeshInstance3D.new()
	lock.name = "HairLock"
	lock.mesh = surface.commit()
	lock.material_override = mat
	parent.add_child(lock)

static func _make_loft(rings: Array, mat: Material, segments: int = 16) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size() - 1):
		for column in segments:
			for corner in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var ring: Vector4 = rings[row + corner.y]
				var u := float(column + corner.x) / segments
				var angle := u * TAU
				surface.set_uv(Vector2(u, float(row + corner.y) / (rings.size() - 1)))
				surface.add_vertex(Vector3(sin(angle) * ring.y, ring.x, cos(angle) * ring.z + ring.w))
	surface.generate_normals()
	var result := MeshInstance3D.new()
	result.mesh = surface.commit()
	result.material_override = mat
	return result

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
