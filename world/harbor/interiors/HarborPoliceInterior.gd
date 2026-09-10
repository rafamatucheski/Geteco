class_name HarborPoliceInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Police station reception for Harbor Patrol.
## Features Desk Sergeant Morales, pulsing police radio scanner,
## CCTV security monitor, and interactive police incident blotter terminal.

const NPC_SCRIPT := preload("res://world/harbor/interiors/HarborConversationalNPC.gd")
var sergeant_npc: CharacterBody2D
var terminal_area: Area2D
var terminal_badge: Label
var terminal_dialog: PanelContainer
var terminal_text: Label
var is_near_terminal: bool = false

var radio_light: PointLight2D
var ctv_screen: Polygon2D
var anim_clock: float = 0.0

func _init() -> void:
	interior_id = &"police"
	display_name = "HARBOR PATROL — DELEGACIA DO PORTO"
	room_size = Vector2(720, 500)
	wall_color = Color("#151b22")
	floor_color = Color("#1e293b")
	accent_color = Color("#68a8d3")

func _setup_interior_content() -> void:
	_build_reception_counter()
	_build_sergeant()
	_build_ambient_effects()
	_build_incident_terminal()
	_create_spawn_and_exit(Vector2(0, 150), Vector2(0, 220), &"harbor/District/Police/Entrance/exit", "SAIR DA DELEGACIA")

func _build_reception_counter() -> void:
	var counter := Polygon2D.new()
	counter.color = Color("#334155")
	counter.polygon = PackedVector2Array([
		Vector2(-120, -16), Vector2(120, -16),
		Vector2(120, 16), Vector2(-120, 16)
	])
	counter.position = Vector2(0, -60)
	counter.z_index = 3
	add_child(counter)

	var counter_trim := Line2D.new()
	counter_trim.points = PackedVector2Array([
		Vector2(-120, -16), Vector2(120, -16),
		Vector2(120, 16), Vector2(-120, 16), Vector2(-120, -16)
	])
	counter_trim.width = 2.0
	counter_trim.default_color = Color("#68a8d3")
	counter_trim.position = counter.position
	counter_trim.z_index = 4
	add_child(counter_trim)

	# Vidro de atendimento blindado
	var glass := Polygon2D.new()
	glass.color = Color(0.4, 0.7, 0.9, 0.25)
	glass.polygon = PackedVector2Array([
		Vector2(-110, -35), Vector2(110, -35),
		Vector2(110, -16), Vector2(-110, -16)
	])
	glass.position = counter.position
	glass.z_index = 5
	add_child(glass)

	# Celas no fundo com grades
	var cell_pos := Vector2(240, -160)
	var cell_back := Polygon2D.new()
	cell_back.color = Color("#0f172a")
	cell_back.polygon = PackedVector2Array([
		Vector2(-70, -50), Vector2(70, -50),
		Vector2(70, 50), Vector2(-70, 50)
	])
	cell_back.position = cell_pos
	cell_back.z_index = 1
	add_child(cell_back)

	for bar_x in range(-60, 70, 15):
		var bar := Line2D.new()
		bar.points = PackedVector2Array([Vector2(bar_x, -50), Vector2(bar_x, 50)])
		bar.width = 3.0
		bar.default_color = Color("#64748b")
		bar.position = cell_pos
		bar.z_index = 2
		add_child(bar)

func _build_sergeant() -> void:
	sergeant_npc = NPC_SCRIPT.new()
	sergeant_npc.name = "SergeantMorales"
	sergeant_npc.character_name = "Sargento Morales"
	sergeant_npc.title_color = Color("#68a8d3")
	sergeant_npc.shirt_color = Color("#1e3a8a")
	sergeant_npc.pants_color = Color("#0f172a")
	sergeant_npc.has_hat = true
	sergeant_npc.hat_color = Color("#1e3a8a")
	sergeant_npc.dialogues = [
		"Harbor Patrol, 1º Distrito. Mantenha as mãos onde eu possa vê-las, cidadão.",
		"O cais de Breakwater tá tenso ultimamente. Carga sumindo dos contêineres e os Cobras de Ferro rondando.",
		"Se você vir algo suspeito nos becos da Foundry Avenue, venha direto ao balcão.",
		"Não toleramos rachas nem tiroteios no perímetro do porto. Considere isso um aviso amigável."
	]
	sergeant_npc.interact_radius = 80.0
	sergeant_npc.position = Vector2(0, -95)
	add_child(sergeant_npc)

func _build_ambient_effects() -> void:
	# Rádio de despacho com luz piscante
	var radio_box := Polygon2D.new()
	radio_box.color = Color("#1e293b")
	radio_box.polygon = PackedVector2Array([Vector2(-10, -6), Vector2(10, -6), Vector2(10, 6), Vector2(-10, 6)])
	radio_box.position = Vector2(80, -60)
	radio_box.z_index = 4
	add_child(radio_box)

	radio_light = PointLight2D.new()
	radio_light.color = Color(0.2, 0.6, 1.0)
	radio_light.energy = 0.8
	radio_light.position = radio_box.position
	radio_light.z_index = 5
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	radio_light.texture = tex
	add_child(radio_light)

	# Monitor de CFTV na parede
	ctv_screen = Polygon2D.new()
	ctv_screen.color = Color(0.1, 0.3, 0.25)
	ctv_screen.polygon = PackedVector2Array([
		Vector2(-25, -16), Vector2(25, -16),
		Vector2(25, 16), Vector2(-25, 16)
	])
	ctv_screen.position = Vector2(-180, -180)
	ctv_screen.z_index = 4
	add_child(ctv_screen)

	var ctv_label := Label.new()
	ctv_label.text = "CAM 01 · CAIS"
	ctv_label.add_theme_font_size_override("font_size", 8)
	ctv_label.add_theme_color_override("font_color", Color("#2ecc71"))
	ctv_label.position = Vector2(-180 - 24, -180 - 10)
	ctv_label.z_index = 5
	add_child(ctv_label)

func _build_incident_terminal() -> void:
	var terminal_pos := Vector2(-220, -40)

	var desk := Polygon2D.new()
	desk.color = Color("#334155")
	desk.polygon = PackedVector2Array([
		Vector2(-40, -25), Vector2(40, -25),
		Vector2(40, 25), Vector2(-40, 25)
	])
	desk.position = terminal_pos
	desk.z_index = 3
	add_child(desk)

	terminal_area = Area2D.new()
	terminal_area.collision_layer = 0
	terminal_area.collision_mask = 4
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(100, 80)
	col.shape = rect
	terminal_area.add_child(col)
	terminal_area.position = terminal_pos
	add_child(terminal_area)

	terminal_area.body_entered.connect(func(b):
		if b.is_in_group("player"):
			is_near_terminal = true
			terminal_badge.visible = true
	)
	terminal_area.body_exited.connect(func(b):
		if b.is_in_group("player"):
			is_near_terminal = false
			terminal_badge.visible = false
			if terminal_dialog.visible:
				terminal_dialog.visible = false
				modal_closed.emit()
	)

	terminal_badge = Label.new()
	terminal_badge.text = "[ E ] TERMINAL DE OCORRÊNCIAS POLICIAIS"
	terminal_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terminal_badge.position = terminal_pos + Vector2(-140, -50)
	terminal_badge.size = Vector2(280, 20)
	terminal_badge.add_theme_font_size_override("font_size", 10)
	terminal_badge.add_theme_color_override("font_color", Color("#68a8d3"))
	terminal_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	terminal_badge.z_index = 10
	terminal_badge.visible = false
	add_child(terminal_badge)

	# UI do Terminal
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	terminal_dialog = PanelContainer.new()
	terminal_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	terminal_dialog.offset_left = 140.0
	terminal_dialog.offset_right = -140.0
	terminal_dialog.offset_bottom = -28.0
	terminal_dialog.offset_top = -225.0
	terminal_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(terminal_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.14, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#68a8d3")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	terminal_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	terminal_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "POLÍCIA DO PORTO — BOLETIM DE OCORRÊNCIAS & MANDADOS"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#68a8d3"))
	vbox.add_child(title)

	terminal_text = Label.new()
	terminal_text.text = "OCORRÊNCIA #304: Suspeita de desvio de contêiner no Píer Leste.\nALERTA GERAL: Cobras de Ferro monitorados nas imediações da Foundry Avenue.\nSTATUS DO DISTRITO: Patrulha ativa • 0 incidentes graves nas últimas 24h."
	terminal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terminal_text.add_theme_font_size_override("font_size", 18)
	terminal_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(terminal_text)

	var hint := Label.new()
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close terminal" if is_en else "[ E / ESC ] Fechar terminal"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	terminal_dialog.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_near_terminal:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if not terminal_dialog.visible:
				_open_terminal()
			else:
				terminal_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and terminal_dialog.visible:
			terminal_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _open_terminal() -> void:
	terminal_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_ui_click_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _physics_process(delta: float) -> void:
	anim_clock += delta
	if radio_light:
		radio_light.energy = 0.5 + sin(anim_clock * 8.0) * 0.4
	if ctv_screen:
		var scanline := sin(anim_clock * 4.0) * 0.05
		ctv_screen.color = Color(0.1 + scanline, 0.3 + scanline, 0.25)
