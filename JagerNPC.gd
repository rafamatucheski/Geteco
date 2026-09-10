class_name JagerNPC
extends CharacterBody2D

## Jäger "Maciota" — O Rei da Noite & Dono da Garagem Central
## Malandro elegante, cafajeste refinado, postura imponente e calculada.
## Traje roxo com lapelas pretas, chapéu fedora com fita de onça, óculos escuros,
## corrente dourada e bengala de ouro com joia púrpura.

signal dialogue_opened()
signal dialogue_closed()
signal conversation_completed()

var conversation_lines: Array[String] = []
var conversation_keys: Array[String] = []
var conversation_speakers: Array[String] = []
var greeting_label: Label
var greeting_cooldown := 0.0
var greeting_remaining := 0.0
var greeting_index := 0
var active_speaker := "maciota"
var conversation_gestures: Array[String] = []
var gesture_clock: float = 0.0
var active_gesture: String = "welcome"

## Finite, authored conversation; the legacy banter remains the default.
func configure_conversation(lines: Array[String], gestures: Array[String] = [], keys: Array[String] = [], speakers: Array[String] = []) -> void:
	conversation_speakers = speakers.duplicate()
	conversation_lines = lines.duplicate()
	conversation_keys = keys.duplicate()
	for line in conversation_lines:
		preload("res://ExpressiveVoice.gd").line(line, "maciota", clampf(float(line.length()) / 22.0, 1.4, 7.0))
	conversation_gestures = gestures.duplicate()
	dialogue_index = 0

@export var character_name: String = "Jäger 'Maciota'"

# 3D SubViewport Rig
var viewport_3d: SubViewport
var sprite_3d_display: Sprite2D
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
var speech_remaining: float = 0.0
var speech_audio: AudioStreamPlayer

# Interação & Diálogo
var interact_area: Area2D
var prompt_badge: Label
var dialogue_ui: CanvasLayer
var dialogue_box: PanelContainer
var name_label: Label
var text_label: Label
var continue_hint: Label

var is_player_nearby: bool = false
var is_talking: bool = false
var dialogue_index: int = 0
var anim_clock: float = 0.0

const DIALOGUES: Array[String] = [
	"Olha só quem resolveu dar as caras na minha humilde garagem... Dante, meu consagrado. Sentiu o cheiro do dinheiro ou foi o meu perfume francês?",
	"Carro rápido é que nem respeito na noite, meu bom: se você não bancar à vista, alguém mais ligeiro toma de você.",
	"Relaxa o quadril e respira a fumaça de borracha queimada. Na mão do Jäger, até lata velha vira lenda do asfalto.",
	"Quer um conselho de quem já viu o sol nascer do lado errado da cela? Nunca economize em duas coisas: perfume bom e pneu pra fuga da polícia.",
	"Ouvi uns sussurros no cais... Os Cobras de Ferro tão mordendo a própria língua de raiva das tuas manobras. Continua assim que o chefe deles perde o sono.",
	"Se quiser deixar tuas máquinas guardadas, compra uma das vagas aqui do lado. Nada de estacionar no meu tapete persa, sacou?",
	"Quem tem pressa tropeça no próprio ego, Dante. O segredo da vida é fazer tudo com elegância e na maior maciota.",
	"Motor afinado, som no talo e cabeça fria. É assim que a gente conquista a Zona 1 e manda nessa porra de cidade."
]

func _ready() -> void:
	z_index = 8
	_build_3d_viewport()
	_setup_interaction()
	_build_dialogue_canvas()
	greeting_label = Label.new()
	greeting_label.position = Vector2(-100, -80)
	greeting_label.size = Vector2(200, 40)
	greeting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greeting_label.add_theme_font_size_override("font_size", 13)
	greeting_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	greeting_label.add_theme_constant_override("shadow_offset_y", 2)
	greeting_label.hide()
	add_child(greeting_label)
	visibility_changed.connect(_sync_model_visibility)
	_sync_model_visibility()
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_signal("language_changed"):
		settings.language_changed.connect(func(_lang: String) -> void:
			if is_talking:
				_show_current_text()
		)

func _sync_model_visibility() -> void:
	if viewport_3d != null:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _build_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(112, 112)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport_3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.72, 0.82)
	env.ambient_light_energy = 0.70
	# `own_world_3d` já cria e vincula o mundo exclusivo do SubViewport. Substituir
	# esse mundo depois de adicionar o viewport à árvore invalida o cenário ativo
	# em alguns renderers. Configure o mundo pertencente ao próprio viewport.
	var viewport_world := viewport_3d.find_world_3d()
	if viewport_world != null:
		viewport_world.environment = env

	var cam := Camera3D.new()
	# Same elevated view as Dante: a straight overhead camera hides the suit,
	# arms and face behind the fedora, making gestures unreadable.
	cam.position = Vector3(0.0, 3.2, 1.4)
	cam.fov = 30.0
	cam.current = true
	viewport_3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.position = Vector3(4.0, 10.0, 4.0)
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.10
	viewport_3d.add_child(light)

	_build_jager_model()

	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	# Higher-resolution viewport, same world-space footprint as Player's
	# 96px viewport at 0.38 scale. Do not enlarge the NPC to show more detail.
	sprite_3d_display.scale = Vector2.ONE * (96.0 * 0.38 / 112.0)
	sprite_3d_display.position = Vector2.ZERO
	add_child(sprite_3d_display)

func _build_jager_model() -> void:
	model_root = Node3D.new()
	model_root.name = "JagerRig"
	viewport_3d.add_child(model_root)
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

func _setup_interaction() -> void:
	interact_area = Area2D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = 4 # Jogador
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 80.0
	col.shape = circle
	interact_area.add_child(col)
	add_child(interact_area)

	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

	prompt_badge = Label.new()
	prompt_badge.text = "[ E ] FALAR COM JÄGER"
	prompt_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_badge.position = Vector2(-80, -50)
	prompt_badge.size = Vector2(160, 20)
	prompt_badge.add_theme_font_size_override("font_size", 11)
	prompt_badge.add_theme_color_override("font_color", Color("#f1c40f"))
	prompt_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_badge.add_theme_constant_override("shadow_offset_x", 1)
	prompt_badge.add_theme_constant_override("shadow_offset_y", 1)
	prompt_badge.visible = false
	add_child(prompt_badge)

func _build_dialogue_canvas() -> void:
	dialogue_ui = CanvasLayer.new()
	dialogue_ui.layer = 25
	add_child(dialogue_ui)

	dialogue_box = PanelContainer.new()
	dialogue_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_box.offset_left = 140.0
	dialogue_box.offset_right = -140.0
	dialogue_box.offset_bottom = -28.0
	dialogue_box.offset_top = -215.0
	dialogue_box.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_ui.add_child(dialogue_box)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#f1c40f")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	dialogue_box.add_theme_stylebox_override("panel", style)

	dialogue_box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_talking:
				_advance_dialogue()
				dialogue_box.accept_event()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	dialogue_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	name_label = Label.new()
	name_label.text = "★ JÄGER 'MACIOTA' — O REI DA NOITE"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("#f1c40f"))
	vbox.add_child(name_label)

	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 23)
	text_label.add_theme_color_override("font_color", Color("#ffffff"))
	text_label.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(text_label)

	continue_hint = Label.new()
	continue_hint.text = "[ ESPAÇO / E ] Continuar    [ ESC ] Fechar"
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 13)
	continue_hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(continue_hint)

	dialogue_box.visible = false

func _exit_tree() -> void:
	if is_talking:
		_close_dialogue()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_try_greeting(body)
		is_player_nearby = true
		prompt_badge.visible = true

func _try_greeting(body: Node2D) -> void:
	if greeting_cooldown > 0 or is_talking or not is_visible_in_tree(): return
	if body.get("is_in_dialogue") == true or body.get("is_control_disabled") == true: return
	var greetings := ["Heh, heh... E aí, meu bom.", "Heh, heh... E aí, meu peixe."]
	if TranslationServer.get_locale().begins_with("en"):
		greetings = ["Heh, heh... Hey, my man.", "Heh, heh... There you are, my friend."]
	greeting_label.text = greetings[greeting_index % greetings.size()]
	greeting_index += 1
	greeting_label.show()
	greeting_remaining = 3.0
	greeting_cooldown = 30.0
	if not is_instance_valid(speech_audio):
		speech_audio = AudioStreamPlayer.new()
		speech_audio.bus = "SFX"
		speech_audio.volume_db = -18.0
		add_child(speech_audio)
	speech_audio.stream = preload("res://ExpressiveVoice.gd").line(greeting_label.text, "maciota", 1.8)
	speech_audio.play()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		greeting_label.hide()
		is_player_nearby = false
		prompt_badge.visible = false
		if is_talking:
			_close_dialogue()

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_nearby: return
	
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("interact"):
			if not is_talking:
				_open_dialogue()
			else:
				_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept") and is_talking:
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and is_talking:
			_close_dialogue()
			get_viewport().set_input_as_handled()

func _open_dialogue() -> void:
	greeting_label.hide()
	is_talking = true
	dialogue_opened.emit()
	prompt_badge.visible = false
	dialogue_box.visible = true
	_show_current_text()

func _advance_dialogue() -> void:
	if not conversation_lines.is_empty():
		dialogue_index += 1
		if dialogue_index >= conversation_lines.size():
			_close_dialogue()
			dialogue_index = 0
			conversation_completed.emit()
			return
		_show_current_text()
		return
	dialogue_index = (dialogue_index + 1) % DIALOGUES.size()
	_show_current_text()

func _show_current_text() -> void:
	if not conversation_keys.is_empty() and dialogue_index < conversation_keys.size():
		text_label.text = tr(conversation_keys[dialogue_index])
	elif not conversation_lines.is_empty() and dialogue_index < conversation_lines.size():
		text_label.text = tr(conversation_lines[dialogue_index])
	else:
		text_label.text = DIALOGUES[dialogue_index]
	var is_en := TranslationServer.get_locale().begins_with("en")
	name_label.text = "★ JÄGER 'MACIOTA' — KING OF THE NIGHT" if is_en else "★ JÄGER 'MACIOTA' — O REI DA NOITE"
	var speaker := conversation_speakers[dialogue_index] if dialogue_index < conversation_speakers.size() else "maciota"
	active_speaker = speaker
	if speaker == "dante": name_label.text = "DANTE"
	continue_hint.text = "[ SPACE / E ] Continue    [ ESC ] Close" if is_en else "[ ESPAÇO / E ] Continuar    [ ESC ] Fechar"
	# A finite speaking envelope: no endless chewing while waiting for input.
	speech_remaining = clampf(float(text_label.text.length()) / 22.0, 1.4, 7.0)
	
	# Som procedural de fala estilizada / mumble retrô malandro
	if not is_instance_valid(speech_audio):
		speech_audio = AudioStreamPlayer.new()
		speech_audio.bus = "SFX"
		speech_audio.volume_db = -18.0
		add_child(speech_audio)
	speech_audio.stop()
	speech_audio.stream = preload("res://ExpressiveVoice.gd").line(text_label.text, speaker, speech_remaining)
	speech_audio.play()
	
	# Gesto 3D de atitude do Jäger
	_trigger_talking_gesture()

func _close_dialogue() -> void:
	if is_instance_valid(speech_audio):
		speech_audio.stop()
	is_talking = false
	speech_remaining = 0.0
	dialogue_box.visible = false
	if is_player_nearby:
		prompt_badge.visible = true
	dialogue_closed.emit()

func _trigger_talking_gesture() -> void:
	if model_root == null: return
	gesture_clock = 0.0
	active_gesture = conversation_gestures[dialogue_index] if dialogue_index < conversation_gestures.size() else ["welcome", "explain", "point", "nod"][dialogue_index % 4]

func _physics_process(delta: float) -> void:
	greeting_cooldown = maxf(0.0, greeting_cooldown - delta)
	greeting_remaining = maxf(0.0, greeting_remaining - delta)
	if greeting_remaining <= 0 and is_instance_valid(greeting_label): greeting_label.hide()
	if not is_visible_in_tree():
		return
	anim_clock += delta
	if model_root and is_talking and active_speaker == "maciota":
		gesture_clock += delta
		var blend := 1.0 - exp(-7.0 * delta)
		var beat := sin(gesture_clock * 3.8)
		# Deliberate one-shot accents, then a relaxed held pose. His cane hand
		# remains planted; the free hand carries the meaning of each line.
		var accent := sin(clampf(gesture_clock / 1.8, 0.0, 1.0) * PI)
		var arm_pose := Vector3(0.42 + beat * 0.035, -0.05, 0.32)
		var elbow_pose := Vector3(0.48 + beat * 0.06, 0.0, 0.0)
		var hand_pose := Vector3(-0.20, 0.0, -0.12)
		var head_pose := Vector3(0.025 * beat, 0.02, -0.035)
		match active_gesture:
			"welcome": # Easy, open-palm invitation; not the same wave every line.
				arm_pose = Vector3(0.35 + accent * 0.18, 0.0, 0.42 + accent * 0.26)
				elbow_pose = Vector3(0.45 + accent * 0.30, 0.0, -0.12)
				hand_pose = Vector3(-0.32, 0.12, -0.25)
				head_pose.z = -0.065
			"point": # Straight forearm and extended index toward the assignment.
				arm_pose = Vector3(0.82, -0.28, 0.70 + accent * 0.10)
				elbow_pose = Vector3(0.12, 0.0, -0.12)
				hand_pose = Vector3(-0.06, 0.0, -0.08)
				head_pose.y = -0.12
			"nod": # Chin dips twice, free hand settles on the jacket.
				arm_pose = Vector3(0.10, 0.0, 0.16)
				elbow_pose = Vector3(0.22, 0.0, -0.15)
				head_pose.x = sin(gesture_clock * 6.0) * 0.13 * maxf(0.0, 1.0 - gesture_clock / 2.2)
		left_upper_arm.rotation = left_upper_arm.rotation.lerp(arm_pose, blend)
		left_lower_arm.rotation = left_lower_arm.rotation.lerp(elbow_pose, blend)
		left_hand.rotation = left_hand.rotation.lerp(hand_pose, blend)
		pointing_finger.rotation.x = lerpf(pointing_finger.rotation.x, 0.0 if active_gesture == "point" else -1.35, blend)
		right_upper_arm.rotation = right_upper_arm.rotation.lerp(Vector3(0.72, -0.08, -0.07), blend)
		right_lower_arm.rotation = Vector3(0.20, 0.0, 0.0)
		head_node.rotation = head_node.rotation.lerp(head_pose, blend)
		torso_node.position.y = 0.78 + sin(anim_clock * 1.8) * 0.012
		torso_node.rotation.z = lerpf(torso_node.rotation.z, -0.028 + accent * 0.016, blend)
		head_node.position.y = 1.26 + sin(anim_clock * 1.8) * 0.008
		var listener := get_tree().get_first_node_in_group("player") as Node2D
		if is_instance_valid(listener):
			var direction := global_position.direction_to(listener.global_position)
			model_root.rotation.y = lerp_angle(model_root.rotation.y, -atan2(direction.y, direction.x) - PI * 0.5, blend)
	
	# Idle suave e dominante (balanço suave do corpo, postura calma e confiante)
	if model_root and (not is_talking or active_speaker != "maciota"):
		head_node.rotation = head_node.rotation.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		left_lower_arm.rotation = left_lower_arm.rotation.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		var sway := sin(anim_clock * 1.5) * 0.012
		torso_node.position.y = 0.78 + sway * 0.5
		torso_node.rotation.z = lerpf(torso_node.rotation.z, -0.028, 1.0 - exp(-6.0 * delta))
		head_node.position.y = 1.26 + sway * 0.5
		
		# Braço direito apoiado na bengala
		right_upper_arm.rotation = Vector3(0.72, -0.08, -0.07)
		right_lower_arm.rotation = Vector3(0.20, 0.0, 0.0)
		
		# Braço esquerdo descontraído com anéis à mostra
		left_upper_arm.rotation = left_upper_arm.rotation.lerp(Vector3(sin(anim_clock * 1.2) * 0.035, 0, 0.12), 1.0 - exp(-6.0 * delta))
		left_hand.rotation = left_hand.rotation.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
		pointing_finger.rotation.x = lerpf(pointing_finger.rotation.x, -1.35, 1.0 - exp(-6.0 * delta))
		
		# Rosto vira levemente para o jogador se ele estiver perto
		var player := get_tree().get_first_node_in_group("player")
		if player and is_player_nearby:
			var dir_to_p := global_position.direction_to(player.global_position)
			var angle_3d: float = -atan2(dir_to_p.y, dir_to_p.x) - PI * 0.5
			model_root.rotation.y = lerp_angle(model_root.rotation.y, angle_3d, 1.0 - exp(-6.0 * delta))
		else:
			model_root.rotation.y = lerp_angle(model_root.rotation.y, 0.0, 1.0 - exp(-3.0 * delta))
	if model_root:
		speech_remaining = maxf(0.0, speech_remaining - delta)
		var syllable := preload("res://ExpressiveVoice.gd").mouth(speech_audio)
		mouth_node.scale.y = 1.0 + syllable * 2.3 if is_talking and active_speaker == "maciota" and speech_remaining > 0.0 else 1.0
		var grip := model_root.to_local(right_lower_arm.to_global(Vector3(0, -0.184, -0.008)))
		cane_mesh.position = grip
		cane_mesh.rotation = Vector3.ZERO
		var grounded_length := maxf(0.1, grip.y - 0.025)
		cane_shaft.scale.y = grounded_length / 0.78
		cane_shaft.position.y = -grounded_length * 0.5
