class_name JagerNPC
extends CharacterBody2D

## Jäger "Maciota" — O Rei da Noite & Dono da Garagem Central
## Malandro elegante, cafajeste refinado, postura imponente e calculada.
## Traje roxo com lapelas pretas, chapéu fedora com fita de onça, óculos escuros,
## corrente dourada e bengala de ouro com joia púrpura.

signal dialogue_opened()
signal dialogue_closed()

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
	"Nitro no tanque, som no talo e cabeça fria. É assim que a gente conquista a Zona 1 e manda nessa porra de cidade."
]

func _ready() -> void:
	z_index = 8
	_build_3d_viewport()
	_setup_interaction()
	_build_dialogue_canvas()

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
	env.ambient_light_color = Color(1.0, 0.98, 0.94)
	env.ambient_light_energy = 1.25
	# `own_world_3d` já cria e vincula o mundo exclusivo do SubViewport. Substituir
	# esse mundo depois de adicionar o viewport à árvore invalida o cenário ativo
	# em alguns renderers. Configure o mundo pertencente ao próprio viewport.
	var viewport_world := viewport_3d.find_world_3d()
	if viewport_world != null:
		viewport_world.environment = env

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.40
	cam.position = Vector3(0.0, 10.0, 0.01)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	viewport_3d.add_child(cam)

	var light := DirectionalLight3D.new()
	light.position = Vector3(4.0, 10.0, 4.0)
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.40
	viewport_3d.add_child(light)

	_build_jager_model()

	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	sprite_3d_display.position = Vector2.ZERO
	add_child(sprite_3d_display)

func _build_jager_model() -> void:
	model_root = Node3D.new()
	model_root.name = "JagerRig"
	viewport_3d.add_child(model_root)

	# Paleta de Cores Estilo "A Pimp Named Slickback" / Maciota
	var mat_purple_suit := _make_mat(Color("#6c3483"), 0.35) # Terno Roxo Vibrante
	var mat_black_lapel := _make_mat(Color("#17202a"), 0.50) # Lapela Preta Acetinada
	var mat_gold := _make_mat(Color("#f1c40f"), 0.15)        # Ouro Maciço Puro
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
	box_t.size = Vector3(0.36, 0.54, 0.20)
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
	torso_node.add_child(lapel_l)

	var lapel_r := MeshInstance3D.new()
	var box_lr := BoxMesh.new()
	box_lr.size = Vector3(0.07, 0.36, 0.03)
	lapel_r.mesh = box_lr
	lapel_r.material_override = mat_black_lapel
	lapel_r.position = Vector3(0.11, 0.06, -0.11)
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
	var box_gc := BoxMesh.new()
	box_gc.size = Vector3(0.10, 0.04, 0.025)
	gold_chain.mesh = box_gc
	gold_chain.material_override = mat_gold
	gold_chain.position = Vector3(0.0, 0.14, -0.118)
	torso_node.add_child(gold_chain)

	# 2. Cabeça (Rosto Fino, Óculos Escuros, Cavanhaque e Chapéu Fedora Roxo)
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.26, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.155
	sph_h.height = 0.31
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Cavanhaque Fino Elegante
	var beard_mesh := MeshInstance3D.new()
	var box_bd := BoxMesh.new()
	box_bd.size = Vector3(0.08, 0.08, 0.04)
	beard_mesh.mesh = box_bd
	beard_mesh.material_override = mat_black_lapel
	beard_mesh.position = Vector3(0.0, -0.11, -0.14)
	head_node.add_child(beard_mesh)

	# Óculos Escuros de Armação Dourada
	var glasses_mesh := MeshInstance3D.new()
	var box_gl := BoxMesh.new()
	box_gl.size = Vector3(0.24, 0.06, 0.06)
	glasses_mesh.mesh = box_gl
	glasses_mesh.material_override = mat_glasses
	glasses_mesh.position = Vector3(0.0, 0.02, -0.15)
	head_node.add_child(glasses_mesh)

	var frame_mesh := MeshInstance3D.new()
	var box_fr := BoxMesh.new()
	box_fr.size = Vector3(0.26, 0.02, 0.065)
	frame_mesh.mesh = box_fr
	frame_mesh.material_override = mat_gold
	frame_mesh.position = Vector3(0.0, 0.05, -0.148)
	head_node.add_child(frame_mesh)

	# Chapéu Fedora Roxo com Aba Larga e Faixa Animal Print
	var hat_brim := MeshInstance3D.new()
	var cyl_b := CylinderMesh.new()
	cyl_b.top_radius = 0.32
	cyl_b.bottom_radius = 0.32
	cyl_b.height = 0.03
	hat_brim.mesh = cyl_b
	hat_brim.material_override = mat_purple_suit
	hat_brim.position = Vector3(0.0, 0.12, 0.0)
	head_node.add_child(hat_brim)

	var hat_crown := MeshInstance3D.new()
	var box_hc := BoxMesh.new()
	box_hc.size = Vector3(0.24, 0.18, 0.24)
	hat_crown.mesh = box_hc
	hat_crown.material_override = mat_purple_suit
	hat_crown.position = Vector3(0.0, 0.22, 0.0)
	head_node.add_child(hat_crown)

	var hat_band := MeshInstance3D.new()
	var box_hb := BoxMesh.new()
	box_hb.size = Vector3(0.25, 0.04, 0.25)
	hat_band.mesh = box_hb
	hat_band.material_override = mat_leopard
	hat_band.position = Vector3(0.0, 0.15, 0.0)
	head_node.add_child(hat_band)

	# 3. Braços & Bengala Dourada
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.23, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.048, 0.22, mat_purple_suit, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.040, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.23, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.048, 0.22, mat_purple_suit, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.040, 0.18, mat_skin, Vector3(0, -0.09, 0)))

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

	var orb := MeshInstance3D.new()
	var sph_o := SphereMesh.new()
	sph_o.radius = 0.045
	sph_o.height = 0.09
	orb.mesh = sph_o
	orb.material_override = _make_mat(Color("#9b59b6"), 0.10)
	orb.position = Vector3(0.0, 0.02, 0.0)
	cane_mesh.add_child(orb)

	cane_mesh.position = Vector3(0.05, -0.16, -0.08)
	right_lower_arm.add_child(cane_mesh)

	# 4. Pernas & Sapatos Bico Fino
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.10, 0.52, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.054, 0.24, mat_purple_suit, Vector3(0, -0.12, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.24, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.046, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.10, 0.52, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.054, 0.24, mat_purple_suit, Vector3(0, -0.12, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.24, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.046, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
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
	circle.radius = 65.0
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
	dialogue_box.offset_left = 60.0
	dialogue_box.offset_right = -60.0
	dialogue_box.offset_bottom = -25.0
	dialogue_box.offset_top = -145.0
	dialogue_ui.add_child(dialogue_box)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.11, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#f1c40f")
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	dialogue_box.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	dialogue_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	name_label = Label.new()
	name_label.text = "★ JÄGER 'MACIOTA' — O REI DA NOITE"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color("#f1c40f"))
	vbox.add_child(name_label)

	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 13)
	text_label.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(text_label)

	continue_hint = Label.new()
	continue_hint.text = "[ ESPAÇO / E ] Continuar    [ ESC ] Fechar"
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 10)
	continue_hint.add_theme_color_override("font_color", Color("#95a5a6"))
	vbox.add_child(continue_hint)

	dialogue_box.visible = false

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_player_nearby = true
		prompt_badge.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_player_nearby = false
		prompt_badge.visible = false
		if is_talking:
			_close_dialogue()

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_nearby: return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if not is_talking:
				_open_dialogue()
			else:
				_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and is_talking:
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_talking:
			_close_dialogue()
			get_viewport().set_input_as_handled()

func _open_dialogue() -> void:
	is_talking = true
	dialogue_opened.emit()
	prompt_badge.visible = false
	dialogue_box.visible = true
	_show_current_text()

func _advance_dialogue() -> void:
	dialogue_index = (dialogue_index + 1) % DIALOGUES.size()
	_show_current_text()

func _show_current_text() -> void:
	text_label.text = DIALOGUES[dialogue_index]
	
	# Som procedural de fala estilizada / mumble retrô malandro
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_dialogue_blip_stream()
	p.volume_db = -8.0
	p.pitch_scale = randf_range(0.85, 1.05)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	
	# Gesto 3D de atitude do Jäger
	_trigger_talking_gesture()

func _close_dialogue() -> void:
	is_talking = false
	dialogue_box.visible = false
	if is_player_nearby:
		prompt_badge.visible = true
	dialogue_closed.emit()

func _trigger_talking_gesture() -> void:
	if model_root == null: return
	var tw := create_tween().set_parallel(true)
	# Inclina a cabeça com deboche
	tw.tween_property(head_node, "rotation:z", randf_range(-0.12, 0.12), 0.25)
	tw.tween_property(head_node, "rotation:x", -0.08, 0.25)
	# Ajusta a bengala com a mão direita
	tw.tween_property(right_upper_arm, "rotation:x", 0.95, 0.25)
	# Mão esquerda gesticula
	tw.tween_property(left_upper_arm, "rotation:x", randf_range(0.3, 0.7), 0.25)

func _physics_process(delta: float) -> void:
	anim_clock += delta
	
	# Idle suave e dominante (balanço suave do corpo, postura calma e confiante)
	if model_root and not is_talking:
		var sway := sin(anim_clock * 1.8) * 0.04
		torso_node.position.y = 0.78 + sway * 0.5
		head_node.position.y = 1.26 + sway * 0.5
		
		# Braço direito apoiado na bengala
		right_upper_arm.rotation = Vector3(0.82, -0.08, 0.0)
		right_lower_arm.rotation = Vector3(0.20, 0.0, 0.0)
		
		# Braço esquerdo descontraído com anéis à mostra
		left_upper_arm.rotation.x = sin(anim_clock * 1.2) * 0.08
		left_upper_arm.rotation.z = 0.12
		
		# Rosto vira levemente para o jogador se ele estiver perto
		var player := get_tree().get_first_node_in_group("player")
		if player and is_player_nearby:
			var dir_to_p := global_position.direction_to(player.global_position)
			var angle_3d: float = -atan2(dir_to_p.y, dir_to_p.x) - PI * 0.5
			model_root.rotation.y = lerp_angle(model_root.rotation.y, angle_3d, 6.0 * delta)
		else:
			model_root.rotation.y = lerp_angle(model_root.rotation.y, 0.0, 3.0 * delta)
