class_name CustomsWorkshopMenu
extends CanvasLayer

## Oficina de Customização & Tuning Estilo GTA V (Los Santos Customs / Benny's)
## Exibe o veículo atual em tempo real no elevador hidráulico, o mecânico "Mano Otto"
## com balões de diálogo e o menu de personalização com bloqueios da Blacklist.

signal workshop_closed(applied_changes: Dictionary)

var current_vehicle: Node2D
var player_ref: Node2D

var preview_color: Color = Color("#1e272e")
var preview_neon_color: Color = Color("#00cec9")
var is_neon_enabled: bool = true

var selected_nitro_stage: int = 1
var selected_turbo_stage: int = 1
var selected_armor_stage: int = 0

var root_panel: PanelContainer
var car_preview_root: Node2D
var car_preview_sprite: Sprite2D
var neon_glow_preview: Polygon2D
var mechanic_dialog_label: Label
var price_summary_label: Label

const PAINT_COLORS := [
	{"name": "Preto Ônix", "color": Color("#1a1a1a")},
	{"name": "Vinho Carmesim", "color": Color("#741515")},
	{"name": "Azul Metálico", "color": Color("#1e3799")},
	{"name": "Amarelo Corrida", "color": Color("#f1c40f")},
	{"name": "Verde Militar", "color": Color("#27ae60")},
	{"name": "Prata Titânio", "color": Color("#bdc3c7")},
	{"name": "Laranja Sunset", "color": Color("#e67e22")},
	{"name": "Branco Pérola", "color": Color("#f5f6fa")}
]

const NEON_COLORS := [
	{"name": "Ciano Elétrico", "color": Color("#00cec9")},
	{"name": "Rosa Choque", "color": Color("#e84393")},
	{"name": "Dourado", "color": Color("#f1c40f")},
	{"name": "Verde Tóxico", "color": Color("#2ecc71")},
	{"name": "Vermelho Sangue", "color": Color("#e74c3c")},
	{"name": "Roxo Ultravioleta", "color": Color("#9b59b6")},
	{"name": "Desativado", "color": Color(0, 0, 0, 0)}
]

func setup_workshop(vehicle: Node2D, player: Node2D) -> void:
	layer = 30
	current_vehicle = vehicle
	player_ref = player
	
	if is_instance_valid(vehicle):
		var v_col = vehicle.get("vehicle_color")
		preview_color = v_col if v_col is Color else Color("#741515")
		var n_col = vehicle.get("neon_color")
		preview_neon_color = n_col if n_col is Color else Color("#00cec9")
		var h_neon = vehicle.get("has_neon")
		is_neon_enabled = (h_neon == true) if h_neon != null else true
		
	_build_ui()

func _build_ui() -> void:
	root_panel = PanelContainer.new()
	root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Fundo da oficina estilo Los Santos Customs
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	bg_style.border_color = Color("#e67e22") # Faixa laranja da oficina
	bg_style.border_width_top = 4
	bg_style.border_width_bottom = 4
	bg_style.content_margin_left = 20
	bg_style.content_margin_right = 20
	bg_style.content_margin_top = 16
	bg_style.content_margin_bottom = 16
	root_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(root_panel)

	var main_layout = HBoxContainer.new()
	main_layout.add_theme_constant_override("separation", 24)
	root_panel.add_child(main_layout)

	# ==========================================
	# 1. PAINEL ESQUERDO: MENU DE UPGRADES
	# ==========================================
	var left_scroll = ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(340, 0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_layout.add_child(left_scroll)

	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 10)
	left_scroll.add_child(left_vbox)

	var shop_title = Label.new()
	shop_title.text = "🔧 GARAGEM DO MANO OTTO - CUSTOMS & TUNING"
	shop_title.add_theme_font_size_override("font_size", 13)
	shop_title.add_theme_color_override("font_color", Color("#e67e22"))
	left_vbox.add_child(shop_title)
	left_vbox.add_child(HSeparator.new())

	# Categoria 1: Pintura & Lataria
	_build_paint_section(left_vbox)

	# Categoria 2: Neon Underglow
	_build_neon_section(left_vbox)

	# Categoria 3: Nitro NOS
	_build_nitro_section(left_vbox)

	# Categoria 4: Motor Turbo & Blow-Off
	_build_turbo_section(left_vbox)

	# Categoria 5: Blindagem & Pneus Kevlar
	_build_armor_section(left_vbox)

	# ==========================================
	# 2. PAINEL CENTRAL: ELEVADOR & PREVIEW 3D
	# ==========================================
	var center_vbox = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_layout.add_child(center_vbox)

	var preview_viewport_container = SubViewportContainer.new()
	preview_viewport_container.custom_minimum_size = Vector2(380, 260)
	preview_viewport_container.stretch = true
	center_vbox.add_child(preview_viewport_container)

	var sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(380, 260)
	sub_viewport.transparent_bg = true
	preview_viewport_container.add_child(sub_viewport)

	_build_car_stage(sub_viewport)

	# Rodapé de Ações
	var bottom_actions = HBoxContainer.new()
	bottom_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_actions.add_theme_constant_override("separation", 16)

	var apply_btn = Button.new()
	apply_btn.text = "✔ APLICAR & SAIR DIRIGINDO"
	apply_btn.custom_minimum_size = Vector2(200, 36)
	apply_btn.pressed.connect(_on_apply_and_exit)
	bottom_actions.add_child(apply_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "CANCELAR"
	cancel_btn.pressed.connect(_on_cancel)
	bottom_actions.add_child(cancel_btn)

	center_vbox.add_child(bottom_actions)

	# ==========================================
	# 3. PAINEL DIREITO: O MECÂNICO "MANO OTTO"
	# ==========================================
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(200, 0)
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.add_theme_constant_override("separation", 12)
	main_layout.add_child(right_vbox)

	_build_mechanic_npc(right_vbox)

func _build_paint_section(parent: VBoxContainer) -> void:
	var sec_title = Label.new()
	sec_title.text = "🎨 PINTURA & LATARIA"
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#f5f6fa"))
	parent.add_child(sec_title)

	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	for p in PAINT_COLORS:
		var btn = Button.new()
		btn.text = p["name"].substr(0, 5)
		btn.custom_minimum_size = Vector2(70, 26)
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(func():
			preview_color = p["color"]
			_update_car_preview()
			_otto_speak("Essa cor %s ficou absurda na lataria!" % p["name"])
		)
		grid.add_child(btn)

	parent.add_child(grid)
	parent.add_child(HSeparator.new())

func _build_neon_section(parent: VBoxContainer) -> void:
	var sec_title = Label.new()
	sec_title.text = "💡 NEON UNDERGLOW (CHASSI)"
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#00cec9"))
	parent.add_child(sec_title)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	for n in NEON_COLORS:
		var btn = Button.new()
		btn.text = n["name"]
		btn.custom_minimum_size = Vector2(95, 26)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(func():
			if n["color"].a == 0:
				is_neon_enabled = false
				_otto_speak("Neon desligado. Modo discreto ativado!")
			else:
				is_neon_enabled = true
				preview_neon_color = n["color"]
				_otto_speak("Neon %s pulsando! À noite essa nave vai chamar atenção!" % n["name"])
			_update_car_preview()
		)
		grid.add_child(btn)

	parent.add_child(grid)
	parent.add_child(HSeparator.new())

func _build_nitro_section(parent: VBoxContainer) -> void:
	var sec_title = Label.new()
	sec_title.text = "💨 SISTEMA DE NITRO (NOS)"
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#0984e3"))
	parent.add_child(sec_title)

	var opt1 = Button.new()
	opt1.text = "✔ Estágio 1: Garrafa NOS 100% [EQUIPADO]"
	opt1.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opt1.add_theme_font_size_override("font_size", 9)
	parent.add_child(opt1)

	var opt2 = Button.new()
	opt2.text = "🔒 Estágio 2: NOS Duplo 150% [BLOQUEADO]"
	opt2.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opt2.add_theme_font_size_override("font_size", 9)
	opt2.pressed.connect(func():
		_otto_speak("🔒 Esse Nitro de alta pressão tá trancado! Vença Viktor Frost (Lobos de Gelo - Distrito de Neve) para liberar!")
	)
	parent.add_child(opt2)

	var opt3 = Button.new()
	opt3.text = "🔒 Estágio 3: Injeção Quádrupla 200% [BLOQUEADO]"
	opt3.alignment = HORIZONTAL_ALIGNMENT_LEFT
	opt3.add_theme_font_size_override("font_size", 9)
	opt3.pressed.connect(func():
		_otto_speak("🔒 Tecnologia militar! Só liberada quando você derrotar o Chefão Supremo da Blacklist #1!")
	)
	parent.add_child(opt3)

	parent.add_child(HSeparator.new())

func _build_turbo_section(parent: VBoxContainer) -> void:
	var sec_title = Label.new()
	sec_title.text = "🏎️ MOTOR TURBO & ESCAPAMENTO"
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#e67e22"))
	parent.add_child(sec_title)

	var t1 = Button.new()
	t1.text = "✔ Estágio 1: Turbo Street + Válvula Blow-Off [EQUIPADO]"
	t1.alignment = HORIZONTAL_ALIGNMENT_LEFT
	t1.add_theme_font_size_override("font_size", 9)
	parent.add_child(t1)

	var t2 = Button.new()
	t2.text = "🔒 Estágio 2: Supercharger Twin-Scroll [BLOQUEADO]"
	t2.alignment = HORIZONTAL_ALIGNMENT_LEFT
	t2.add_theme_font_size_override("font_size", 9)
	t2.pressed.connect(func():
		_otto_speak("🔒 Esse compressor precisa de peças do Deserto! Vença Tex 'Poeira' Slade (Os Cascaveis) para liberar!")
	)
	parent.add_child(t2)

	parent.add_child(HSeparator.new())

func _build_armor_section(parent: VBoxContainer) -> void:
	var sec_title = Label.new()
	sec_title.text = "🛡️ BLINDAGEM DE LATARIA & KEVLAR"
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#bdc3c7"))
	parent.add_child(sec_title)

	var vum = get_tree().get_first_node_in_group("vehicle_upgrade_manager")
	var is_unlocked: bool = vum != null and vum.unlocked_upgrades.get("armor_plating", 0) > 0
	
	var a1 = Button.new()
	if is_unlocked:
		a1.text = "✔ Estágio 1: Chapa 50% + Pneus Kevlar Anti-Furo [EQUIPADO]"
		a1.pressed.connect(func():
			_otto_speak("Pneus de Kevlar e chapa blindada instalados! Pode passar por cima das fitas de pregos da polícia sem medo!")
		)
	else:
		a1.text = "🔒 Estágio 1: Chapa 50% + Pneus Anti-Furo [BLOQUEADO]"
		a1.pressed.connect(func():
			_otto_speak("🔒 Blindagem pesada e Pneus Kevlar! Vença Don Hector 'Cascavel' (#5 da Blacklist) para liberar essa proteção contra fitas de pregos!")
		)
	a1.alignment = HORIZONTAL_ALIGNMENT_LEFT
	a1.add_theme_font_size_override("font_size", 9)
	parent.add_child(a1)

func _build_car_stage(viewport: SubViewport) -> void:
	var stage_root = Node2D.new()
	stage_root.position = Vector2(190, 130)
	viewport.add_child(stage_root)

	# 1. Piso do Elevador Hidráulico da Oficina
	var lift_platform := Polygon2D.new()
	lift_platform.polygon = PackedVector2Array([
		Vector2(-90, -45), Vector2(90, -45), Vector2(90, 45), Vector2(-90, 45)
	])
	lift_platform.color = Color("#2d3436")
	stage_root.add_child(lift_platform)

	# Braços metálicos amarelos do elevador
	var lift_arm_l := Polygon2D.new()
	lift_arm_l.polygon = PackedVector2Array([Vector2(-95, -45), Vector2(-80, -45), Vector2(-80, 45), Vector2(-95, 45)])
	lift_arm_l.color = Color("#f1c40f")
	stage_root.add_child(lift_arm_l)

	var lift_arm_r := Polygon2D.new()
	lift_arm_r.polygon = PackedVector2Array([Vector2(80, -45), Vector2(95, -45), Vector2(95, 45), Vector2(80, 45)])
	lift_arm_r.color = Color("#f1c40f")
	stage_root.add_child(lift_arm_r)

	# 2. Halo de Neon no chão sob o carro
	neon_glow_preview = Polygon2D.new()
	neon_glow_preview.polygon = PackedVector2Array([
		Vector2(-75, -35), Vector2(75, -35), Vector2(75, 35), Vector2(-75, 35)
	])
	neon_glow_preview.color = Color(preview_neon_color.r, preview_neon_color.g, preview_neon_color.b, 0.45)
	stage_root.add_child(neon_glow_preview)

	# 3. Sprite do Veículo em Alta Definição
	car_preview_sprite = Sprite2D.new()
	var tex = AtlasTexture.new()
	tex.atlas = load("res://city_demo/art/vehicle-atlas.png")
	
	if is_instance_valid(current_vehicle) and current_vehicle.get("visual") is Sprite2D:
		var orig_tex = current_vehicle.visual.texture as AtlasTexture
		if orig_tex:
			tex.region = orig_tex.region
		else:
			tex.region = Rect2(58, 48, 234, 475)
	else:
		tex.region = Rect2(58, 48, 234, 475)
		
	car_preview_sprite.texture = tex
	car_preview_sprite.scale = Vector2(0.24, 0.24)
	car_preview_sprite.rotation = -PI * 0.5 # Apontado para a frente na horizontal
	car_preview_sprite.modulate = preview_color
	stage_root.add_child(car_preview_sprite)

func _build_mechanic_npc(parent: VBoxContainer) -> void:
	var mech_title = Label.new()
	mech_title.text = "👨‍🔧 MANO OTTO (MECÂNICO)"
	mech_title.add_theme_font_size_override("font_size", 11)
	mech_title.add_theme_color_override("font_color", Color("#f39c12"))
	parent.add_child(mech_title)

	# Desenho vetorial do Mano Otto
	var otto_canvas = SubViewportContainer.new()
	otto_canvas.custom_minimum_size = Vector2(160, 140)
	otto_canvas.stretch = true
	parent.add_child(otto_canvas)

	var vp = SubViewport.new()
	vp.size = Vector2i(160, 140)
	vp.transparent_bg = true
	otto_canvas.add_child(vp)

	var otto_root = Node2D.new()
	otto_root.position = Vector2(80, 70)
	vp.add_child(otto_root)

	# Corpo/Tronco com macacão jeans azul
	var torso = Polygon2D.new()
	torso.polygon = PackedVector2Array([
		Vector2(-20, -10), Vector2(20, -10), Vector2(18, 45), Vector2(-18, 45)
	])
	torso.color = Color("#225378") # Macacão azul
	otto_root.add_child(torso)

	# Pano vermelho de graxa no bolso
	var rag = Polygon2D.new()
	rag.polygon = PackedVector2Array([Vector2(6, 12), Vector2(14, 12), Vector2(16, 26), Vector2(4, 24)])
	rag.color = Color("#c0392b")
	torso.add_child(rag)

	# Cabeça e Boné virado
	var head = Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-12, -32), Vector2(12, -32), Vector2(14, -10), Vector2(-14, -10)
	])
	head.color = Color("#e0ac69") # Tom de pele
	otto_root.add_child(head)

	var cap = Polygon2D.new()
	cap.polygon = PackedVector2Array([
		Vector2(-14, -36), Vector2(14, -36), Vector2(12, -28), Vector2(-22, -28) # Aba virada para trás
	])
	cap.color = Color("#1e272e") # Boné preto
	head.add_child(cap)

	# Bigode e Olhos
	var mustache = Polygon2D.new()
	mustache.polygon = PackedVector2Array([Vector2(-8, -14), Vector2(8, -14), Vector2(0, -11)])
	mustache.color = Color("#2d3436")
	head.add_child(mustache)

	# Braço segurando Chave Inglesa
	var arm = Polygon2D.new()
	arm.polygon = PackedVector2Array([Vector2(20, -6), Vector2(34, 10), Vector2(30, 16), Vector2(18, 0)])
	arm.color = Color("#e0ac69")
	otto_root.add_child(arm)

	var wrench = Line2D.new()
	wrench.width = 4.0
	wrench.default_color = Color("#95a5a6")
	wrench.add_point(Vector2(32, 10))
	wrench.add_point(Vector2(44, 28))
	otto_root.add_child(wrench)

	# Balão de Fala do Otto
	var dialog_panel = PanelContainer.new()
	var d_style = StyleBoxFlat.new()
	d_style.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	d_style.border_color = Color("#f39c12")
	d_style.set_border_width_all(1)
	d_style.set_corner_radius_all(6)
	d_style.content_margin_left = 8
	d_style.content_margin_right = 8
	d_style.content_margin_top = 6
	d_style.content_margin_bottom = 6
	dialog_panel.add_theme_stylebox_override("panel", d_style)
	parent.add_child(dialog_panel)

	mechanic_dialog_label = Label.new()
	mechanic_dialog_label.text = "E aí Dante! O que manda hoje? Pintura nova ou quer estalar um Nitro brabo?"
	mechanic_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mechanic_dialog_label.add_theme_font_size_override("font_size", 9)
	mechanic_dialog_label.add_theme_color_override("font_color", Color("#ecf0f1"))
	dialog_panel.add_child(mechanic_dialog_label)

func _otto_speak(text: String) -> void:
	if mechanic_dialog_label:
		mechanic_dialog_label.text = text

func _update_car_preview() -> void:
	if car_preview_sprite:
		car_preview_sprite.modulate = preview_color
	if neon_glow_preview:
		if is_neon_enabled:
			neon_glow_preview.visible = true
			neon_glow_preview.color = Color(preview_neon_color.r, preview_neon_color.g, preview_neon_color.b, 0.45)
		else:
			neon_glow_preview.visible = false

func _on_apply_and_exit() -> void:
	if is_instance_valid(current_vehicle):
		current_vehicle.set("vehicle_color", preview_color)
		if current_vehicle.get("visual") is Sprite2D:
			current_vehicle.visual.modulate = preview_color
		
		current_vehicle.set("has_neon", is_neon_enabled)
		current_vehicle.set("neon_color", preview_neon_color)
		if current_vehicle.has_method("_setup_neon_underglow"):
			current_vehicle._setup_neon_underglow()
			
	var vum = get_tree().get_first_node_in_group("vehicle_upgrade_manager")
	if vum:
		vum.set_neon_color(preview_neon_color)
		if vum.unlocked_upgrades.get("armor_plating", 0) > 0 and is_instance_valid(current_vehicle):
			current_vehicle.set("has_puncture_proof_tires", true)
		
	workshop_closed.emit({
		"color": preview_color,
		"neon": preview_neon_color,
		"has_neon": is_neon_enabled
	})
	queue_free()

func _on_cancel() -> void:
	workshop_closed.emit({})
	queue_free()
