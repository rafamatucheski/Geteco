extends Node3D
## Original JagerNPC visual extraction; no damage/death/gameplay dependencies.
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
var cane_mesh: Node3D = null
var mouth_node: Node3D
var left_hand: Node3D
var pointing_finger: Node3D
var cane_shaft: MeshInstance3D

func _ready() -> void:
	_build_jager_model()
	model_root.scale = Vector3.ONE * 1.28
	cane_mesh.position = Vector3(.27,.72,0)
	# Corpo articulado dos pedestres: terno roxo, camisa de onça, fedora, óculos
	# escuros e sapato roxo; a bengala continua, com a mão direita no castão.
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, {
		"variant": 8300, "female": false, "top": 2, "bottom": 0, "shoe": 2, "hat": 7, "glasses": true,
		"backpack": false, "bag": 0, "beard": 3, "hair": 0, "build": 1, "height": 1.0,
		"top_color": Color("6c3483"), "bottom_color": Color("5b2c6f"), "inner": Color("f5cd79"),
		"accent": Color("4a235a"), "skin": Color("a87858"), "hair_color": Color("17202a"), "shoe_color": Color("4a235a")}, [cane_mesh], true)
	body.hand_provider = func() -> Array: return [cane_mesh.global_position + Vector3.UP * 0.02, null] if cane_mesh.is_visible_in_tree() else [null, null]

var body: Node3D

func _build_jager_model() -> void:
	model_root = Node3D.new()
	model_root.name = "JagerRig"
	model_root.rotation.y = PI
	add_child(model_root)
	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.28
	shadow_mesh.bottom_radius = 0.28
	shadow_mesh.height = 0.01
	shadow.mesh = shadow_mesh
	var shadow_material := StandardMaterial3D.new()
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.albedo_color = Color(0.02, 0.02, 0.05, 0.50)
	shadow.material_override = shadow_material
	shadow.position.y = 0.01
	model_root.add_child(shadow)

	# Paleta de Cores Estilo "A Pimp Named Slickback" / Maciota
	var mat_purple_suit := _make_mat(Color("#6c3483"), 0.70) # Tecido roxo, sem reflexo plástico
	var mat_black_lapel := _make_mat(Color("#17202a"), 0.50) # Lapela Preta Acetinada
	var mat_gold := _make_mat(Color("#f1c40f"), 0.15)        # Ouro Maciço Puro
	mat_gold.metallic = 0.72
	var mat_skin := _make_mat(Color("#a87858"), 0.45)        # Pele Morena Clara
	var mat_leopard := _make_mat(Color("#f5cd79"), 0.60)     # Fita de Onça do Chapéu
	var mat_glasses := _make_mat(Color("#2c3e50"), 0.05)     # Lentes Escuras com Brilho
	var mat_shoes := _make_mat(Color("#4a235a"), 0.20)       # Sapatos Sociais Roxos Brilhantes

	# 1. Tronco (Paletó Roxo com corte esguio e elegante)
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.78, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var box_t := BoxMesh.new()
	box_t.size = Vector3(0.31, 0.48, 0.19)
	torso_mesh.mesh = box_t
	torso_mesh.material_override = mat_purple_suit
	torso_node.add_child(torso_mesh)

	# Lapelas Pretas do Paletó
	var lapel_l := MeshInstance3D.new()
	var box_ll := BoxMesh.new()
	box_ll.size = Vector3(0.07, 0.36, 0.03)
	lapel_l.mesh = box_ll
	lapel_l.material_override = mat_black_lapel
	lapel_l.position = Vector3(-0.11, 0.06, -0.11)
	lapel_l.rotation.z = -0.24
	torso_node.add_child(lapel_l)

	var lapel_r := MeshInstance3D.new()
	var box_lr := BoxMesh.new()
	box_lr.size = Vector3(0.07, 0.36, 0.03)
	lapel_r.mesh = box_lr
	lapel_r.material_override = mat_black_lapel
	lapel_r.position = Vector3(0.11, 0.06, -0.11)
	lapel_r.rotation.z = 0.24
	torso_node.add_child(lapel_r)

	# Camisa de Seda com Peito Aberto & Corrente Grossa de Ouro
	var shirt_open := MeshInstance3D.new()
	var box_so := BoxMesh.new()
	box_so.size = Vector3(0.12, 0.28, 0.02)
	shirt_open.mesh = box_so
	shirt_open.material_override = mat_skin
	shirt_open.position = Vector3(0.0, 0.10, -0.105)
	torso_node.add_child(shirt_open)

	var gold_chain := MeshInstance3D.new()
	var chain_ring := TorusMesh.new()
	chain_ring.inner_radius = 0.040
	chain_ring.outer_radius = 0.051
	chain_ring.rings = 12
	chain_ring.ring_segments = 6
	gold_chain.mesh = chain_ring
	gold_chain.rotation.x = PI * 0.5
	gold_chain.material_override = mat_gold
	gold_chain.position = Vector3(0.0, 0.13, -0.125)
	torso_node.add_child(gold_chain)

	# 2. Cabeça (Rosto Fino, Óculos Escuros, Cavanhaque e Chapéu Fedora Roxo)
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.26, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.155
	sph_h.height = 0.31
	sph_h.radial_segments = 16
	sph_h.rings = 8
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)
	head_mesh.scale = Vector3(0.89, 1.0, 0.89)

	# Cavanhaque Fino Elegante
	var beard_mesh := MeshInstance3D.new()
	var box_bd := BoxMesh.new()
	box_bd.size = Vector3(0.045, 0.055, 0.023)
	beard_mesh.mesh = box_bd
	beard_mesh.material_override = mat_black_lapel
	beard_mesh.position = Vector3(0.0, -0.105, -0.125)
	head_node.add_child(beard_mesh)

	# Óculos Escuros de Armação Dourada
	var glasses_mesh := MeshInstance3D.new()
	var box_gl := BoxMesh.new()
	box_gl.size = Vector3(0.098, 0.055, 0.025)
	glasses_mesh.mesh = box_gl
	glasses_mesh.material_override = mat_glasses
	glasses_mesh.position = Vector3(-0.065, 0.02, -0.137)
	head_node.add_child(glasses_mesh)
	var other_lens := glasses_mesh.duplicate() as MeshInstance3D
	other_lens.position.x = 0.065
	head_node.add_child(other_lens)

	var frame_mesh := MeshInstance3D.new()
	var box_fr := BoxMesh.new()
	box_fr.size = Vector3(0.25, 0.012, 0.028)
	frame_mesh.mesh = box_fr
	frame_mesh.material_override = mat_gold
	frame_mesh.position = Vector3(0.0, 0.046, -0.141)
	head_node.add_child(frame_mesh)

	# Chapéu Fedora Roxo com Aba Larga e Faixa Animal Print
	var hat_brim := MeshInstance3D.new()
	var cyl_b := CylinderMesh.new()
	cyl_b.top_radius = 0.265
	cyl_b.bottom_radius = 0.265
	cyl_b.height = 0.03
	cyl_b.radial_segments = 20
	hat_brim.mesh = cyl_b
	hat_brim.material_override = mat_purple_suit
	hat_brim.position = Vector3(0.0, 0.12, 0.0)
	hat_brim.scale.z = 0.84
	hat_brim.rotation.z = -0.10
	head_node.add_child(hat_brim)

	var hat_crown := MeshInstance3D.new()
	var crown := CylinderMesh.new()
	crown.top_radius = 0.115
	crown.bottom_radius = 0.15
	crown.height = 0.17
	crown.radial_segments = 12
	hat_crown.mesh = crown
	hat_crown.material_override = mat_purple_suit
	hat_crown.position = Vector3(0.0, 0.22, 0.0)
	hat_crown.scale.z = 0.85
	hat_crown.rotation.z = -0.10
	head_node.add_child(hat_crown)

	var hat_band := MeshInstance3D.new()
	var band := CylinderMesh.new()
	band.top_radius = 0.145
	band.bottom_radius = 0.153
	band.height = 0.04
	band.radial_segments = 12
	hat_band.mesh = band
	hat_band.material_override = mat_leopard
	hat_band.position = Vector3(0.0, 0.15, 0.0)
	hat_band.scale.z = 0.85
	hat_band.rotation.z = -0.10
	head_node.add_child(hat_band)

	# 3. Braços & Bengala Dourada
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.23, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.048, 0.22, mat_purple_suit, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.040, 0.15, mat_purple_suit, Vector3(0, -0.075, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.23, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.048, 0.22, mat_purple_suit, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.040, 0.15, mat_purple_suit, Vector3(0, -0.075, 0)))

	# Bengala de Ouro com Joia na Mão Direita
	cane_mesh = Node3D.new()
	var stick := MeshInstance3D.new()
	var cyl_s := CylinderMesh.new()
	cyl_s.top_radius = 0.016
	cyl_s.bottom_radius = 0.014
	cyl_s.height = 0.78
	stick.mesh = cyl_s
	stick.material_override = mat_gold
	stick.position = Vector3(0.0, -0.38, 0.0)
	cane_mesh.add_child(stick)
	cane_shaft = stick

	var orb := MeshInstance3D.new()
	var sph_o := SphereMesh.new()
	sph_o.radius = 0.045
	sph_o.height = 0.09
	orb.mesh = sph_o
	orb.material_override = _make_mat(Color("#9b59b6"), 0.10)
	orb.position = Vector3(0.0, 0.02, 0.0)
	cane_mesh.add_child(orb)

	# Grounded cane follows the grip, not the elbow's rotation; its ferrule
	# never sweeps through the floor while Maciota addresses the visitor.
	model_root.add_child(cane_mesh)

	# 4. Pernas & Sapatos Bico Fino
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.10, 0.52, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.054, 0.24, mat_purple_suit, Vector3(0, -0.12, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.24, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.046, 0.20, mat_purple_suit, Vector3(0, -0.10, 0)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.10, 0.52, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.054, 0.24, mat_purple_suit, Vector3(0, -0.12, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.24, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.046, 0.20, mat_purple_suit, Vector3(0, -0.10, 0)))
	_add_tailored_details(mat_purple_suit, mat_skin, mat_gold, mat_black_lapel, mat_shoes)
	# Merge ornamental meshes by material under each joint. Details are authored
	# separately but do not each become an extra draw call at runtime.
	for joint in [torso_node, head_node, left_upper_arm, left_lower_arm, right_upper_arm, right_lower_arm, left_upper_leg, left_lower_leg, right_upper_leg, right_lower_leg, left_hand]:
		_batch_joint_meshes(joint)

func _detail(parent: Node3D, at: Vector3, size: Vector3, material: Material, rounded: bool = false) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	if rounded:
		var shape := SphereMesh.new()
		shape.radius = 0.5
		shape.height = 1.0
		shape.radial_segments = 12
		shape.rings = 6
		piece.mesh = shape
		piece.scale = size
	else:
		var shape := BoxMesh.new()
		shape.size = size
		piece.mesh = shape
	piece.position = at
	piece.material_override = material
	parent.add_child(piece)
	return piece

func _add_tailored_details(suit: Material, skin: Material, gold: Material, dark: Material, shoes: Material) -> void:
	var silk := _make_mat(Color("d5becb"), 0.38)
	var hat_crease := _make_mat(Color("41204f"), 0.8)
	# Curved shoulders over a fitted waist, double vent and pocket square.
	for side in [-1.0, 1.0]:
		_detail(torso_node, Vector3(side * 0.105, 0.14, 0), Vector3(0.22, 0.30, 0.22), suit, true)
		_detail(torso_node, Vector3(side * 0.088, -0.21, 0.018), Vector3(0.17, 0.19, 0.21), suit)
		_detail(torso_node, Vector3(side * 0.103, -0.13, -0.112), Vector3(0.075, 0.016, 0.012), dark)
		_detail(head_node, Vector3(side * 0.135, -0.015, 0), Vector3(0.038, 0.073, 0.052), skin, true)
		_detail(head_node, Vector3(side * 0.121, 0.029, -0.076), Vector3(0.012, 0.015, 0.15), gold)
	_detail(torso_node, Vector3(-0.116, 0.065, -0.124), Vector3(0.045, 0.034, 0.016), silk).rotation.z = -0.25
	_detail(torso_node, Vector3(0, -0.085, -0.11), Vector3(0.022, 0.022, 0.015), gold, true)
	_detail(torso_node, Vector3(0, 0.068, -0.14), Vector3(0.022, 0.032, 0.012), gold)
	_detail(head_node, Vector3(0, 0.30, 0), Vector3(0.035, 0.011, 0.17), hat_crease)
	for spot in range(7):
		var angle := float(spot) * TAU / 7.0
		_detail(head_node, Vector3(cos(angle) * 0.149, 0.158, sin(angle) * 0.127), Vector3(0.025, 0.018, 0.025), dark, true)
	_detail(head_node, Vector3(0, -0.012, -0.142), Vector3(0.040, 0.066, 0.055), skin, true)
	_detail(head_node, Vector3(0, -0.052, -0.143), Vector3(0.066, 0.013, 0.013), dark)
	mouth_node = Node3D.new()
	mouth_node.name = "SpeakingMouth"
	mouth_node.position = Vector3(0, -0.074, -0.144)
	head_node.add_child(mouth_node)
	_detail(mouth_node, Vector3.ZERO, Vector3(0.036, 0.008, 0.010), _make_mat(Color("492925"), 0.9))
	for lower in [left_lower_arm, right_lower_arm]:
		_detail(lower, Vector3(0, -0.151, 0), Vector3(0.081, 0.025, 0.078), silk)
		_detail(lower, Vector3(-0.043, -0.151, 0), Vector3(0.012, 0.013, 0.022), gold)
	left_hand = Node3D.new()
	left_hand.name = "ExpressiveHand"
	left_hand.position = Vector3(0, -0.192, 0)
	left_lower_arm.add_child(left_hand)
	_detail(left_hand, Vector3.ZERO, Vector3(0.070, 0.080, 0.047), skin, true)
	_detail(left_hand, Vector3(0.035, 0.006, -0.005), Vector3(0.029, 0.047, 0.026), skin, true)
	_detail(left_hand, Vector3(-0.013, -0.022, -0.022), Vector3(0.015, 0.013, 0.012), gold)
	pointing_finger = Node3D.new()
	pointing_finger.name = "PointingFinger"
	pointing_finger.position = Vector3(-0.021, -0.026, 0)
	left_hand.add_child(pointing_finger)
	_detail(pointing_finger, Vector3(0, -0.026, 0), Vector3(0.019, 0.062, 0.024), skin, true)
	_detail(right_lower_arm, Vector3(0, -0.184, 0), Vector3(0.077, 0.067, 0.061), skin, true)
	for lower in [left_lower_leg, right_lower_leg]:
		_detail(lower, Vector3(0, -0.215, -0.032), Vector3(0.11, 0.066, 0.20), shoes, true)
		_detail(lower, Vector3(0, -0.23, -0.028), Vector3(0.107, 0.025, 0.17), dark)
		_detail(lower, Vector3(0, -0.195, -0.060), Vector3(0.058, 0.012, 0.024), gold)

func _batch_joint_meshes(joint: Node3D) -> void:
	var batches: Dictionary = {}
	for child in joint.get_children():
		if child is MeshInstance3D:
			var mat: Material = child.material_override
			if not batches.has(mat):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[mat] = surface
			batches[mat].append_from(child.mesh, 0, child.transform)
			joint.remove_child(child)
			child.free()
	for mat in batches:
		var merged := MeshInstance3D.new()
		merged.mesh = batches[mat].commit()
		merged.material_override = mat
		joint.add_child(merged)

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

func _make_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	return m

