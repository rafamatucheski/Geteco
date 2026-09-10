class_name HarborClinicInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Clinic interior for Bay Medical.
## Enters and exits from the NORTH.
## Features Nurse Clara, pulsing ECG heart rate monitor,
## and interactive medical triage station that restores Player health.

const NPC_SCRIPT := preload("res://world/harbor/interiors/HarborConversationalNPC.gd")
var nurse_npc: CharacterBody2D
var triage_area: Area2D
var triage_badge: Label
var triage_dialog: PanelContainer
var triage_text: Label
var _triage_title: Label
var _triage_hint: Label
var is_near_triage: bool = false

var ecg_screen: Polygon2D
var ecg_line: Line2D
var anim_clock: float = 0.0

func _init() -> void:
	interior_id = &"clinic"
	display_name = "BAY MEDICAL — CLÍNICA DO PORTO"
	room_size = Vector2(740, 500)
	wall_color = Color("#0f2027")
	floor_color = Color("#1e333a")
	accent_color = Color("#78c7bd")
	entrance_north = true

func _setup_interior_content() -> void:
	_build_clinical_layout()
	_build_nurse()
	_build_ambient_ecg()
	_build_triage_station()
	# Exit on the NORTH wall (north = true) so player exits northwards
	_create_spawn_and_exit(Vector2(0, -120), Vector2(0, -210), &"harbor/District/Clinic/Entrance/exit", "SAIR DA CLÍNICA", true)

func _build_clinical_layout() -> void:
	# Balcão de triagem
	var desk := Polygon2D.new()
	desk.color = Color("#203a43")
	desk.polygon = PackedVector2Array([
		Vector2(-100, -15), Vector2(100, -15),
		Vector2(100, 15), Vector2(-100, 15)
	])
	desk.position = Vector2(-120, 20)
	desk.z_index = 3
	add_child(desk)

	var desk_trim := Line2D.new()
	desk_trim.points = PackedVector2Array([
		Vector2(-100, -15), Vector2(100, -15),
		Vector2(100, 15), Vector2(-100, 15), Vector2(-100, -15)
	])
	desk_trim.width = 2.0
	desk_trim.default_color = Color("#78c7bd")
	desk_trim.position = desk.position
	desk_trim.z_index = 4
	add_child(desk_trim)

	# Macas de atendimento
	for bed_x in [160, 260]:
		var bed := Polygon2D.new()
		bed.color = Color("#f8fafc")
		bed.polygon = PackedVector2Array([
			Vector2(-25, -50), Vector2(25, -50),
			Vector2(25, 50), Vector2(-25, 50)
		])
		bed.position = Vector2(bed_x, 60)
		bed.z_index = 2
		add_child(bed)

		var pillow := Polygon2D.new()
		pillow.color = Color("#cbd5e1")
		pillow.polygon = PackedVector2Array([
			Vector2(-20, -45), Vector2(20, -45),
			Vector2(20, -25), Vector2(-20, -25)
		])
		pillow.position = bed.position
		pillow.z_index = 3
		add_child(pillow)

func _build_nurse() -> void:
	nurse_npc = NPC_SCRIPT.new()
	nurse_npc.name = "NurseClara"
	nurse_npc.character_name = "Enfermeira Clara"
	nurse_npc.title_color = Color("#78c7bd")
	nurse_npc.shirt_color = Color("#e0f2fe")
	nurse_npc.pants_color = Color("#0284c7")
	nurse_npc.dialogues = [
		"Bem-vindo à Bay Medical. Se estiver ferido, dirija-se à maca de triagem ao lado.",
		"O trabalho no porto é perigoso... recebo estivadores com fraturas e cortes todos os dias.",
		"Mantenha sua vacinação em dia e evite a água poluída das docas se tiver ferimentos abertos.",
		"Nossos suprimentos médicos são mantidos esterilizados. Fique à vontade para usar o posto de primeiros socorros."
	]
	nurse_npc.position = Vector2(-120, -40)
	add_child(nurse_npc)

func _build_ambient_ecg() -> void:
	# Monitor de sinais vitais
	var monitor_box := Polygon2D.new()
	monitor_box.color = Color("#0f172a")
	monitor_box.polygon = PackedVector2Array([
		Vector2(-30, -20), Vector2(30, -20),
		Vector2(30, 20), Vector2(-30, 20)
	])
	monitor_box.position = Vector2(210, -50)
	monitor_box.z_index = 4
	add_child(monitor_box)

	ecg_screen = Polygon2D.new()
	ecg_screen.color = Color("#052e16")
	ecg_screen.polygon = PackedVector2Array([
		Vector2(-26, -16), Vector2(26, -16),
		Vector2(26, 16), Vector2(-26, 16)
	])
	ecg_screen.position = monitor_box.position
	ecg_screen.z_index = 5
	add_child(ecg_screen)

	ecg_line = Line2D.new()
	ecg_line.points = PackedVector2Array([
		Vector2(-22, 0), Vector2(-10, 0), Vector2(-6, -10), Vector2(-2, 10),
		Vector2(2, -8), Vector2(6, 0), Vector2(22, 0)
	])
	ecg_line.width = 1.5
	ecg_line.default_color = Color("#22c55e")
	ecg_line.position = monitor_box.position
	ecg_line.z_index = 6
	add_child(ecg_line)

	var ecg_lbl := Label.new()
	ecg_lbl.text = "ECG: 72 BPM"
	ecg_lbl.add_theme_font_size_override("font_size", 8)
	ecg_lbl.add_theme_color_override("font_color", Color("#22c55e"))
	ecg_lbl.position = monitor_box.position + Vector2(-25, 6)
	ecg_lbl.z_index = 7
	add_child(ecg_lbl)

func _build_triage_station() -> void:
	var station_pos := Vector2(210, 60)

	triage_area = Area2D.new()
	triage_area.collision_layer = 0
	triage_area.collision_mask = 4
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160, 120)
	col.shape = rect
	triage_area.add_child(col)
	triage_area.position = station_pos
	add_child(triage_area)

	triage_area.body_entered.connect(func(b):
		if b.is_in_group("player"):
			is_near_triage = true
			triage_badge.visible = true
	)
	triage_area.body_exited.connect(func(b):
		if b.is_in_group("player"):
			is_near_triage = false
			triage_badge.visible = false
			if triage_dialog.visible:
				triage_dialog.visible = false
				modal_closed.emit()
	)

	triage_badge = Label.new()
	triage_badge.text = "[ E ] POSTO DE TRIAGEM & SINAIS VITAIS"
	triage_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	triage_badge.position = station_pos + Vector2(-150, -75)
	triage_badge.size = Vector2(300, 20)
	triage_badge.add_theme_font_size_override("font_size", 10)
	triage_badge.add_theme_color_override("font_color", Color("#78c7bd"))
	triage_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	triage_badge.z_index = 10
	triage_badge.visible = false
	add_child(triage_badge)

	# Dialog UI
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	triage_dialog = PanelContainer.new()
	triage_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	triage_dialog.offset_left = 140.0
	triage_dialog.offset_right = -140.0
	triage_dialog.offset_bottom = -25.0
	triage_dialog.offset_top = -235.0
	triage_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(triage_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.14, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#78c7bd")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	triage_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	triage_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	_triage_title = title
	title.text = "✚ ATENDIMENTO MÉDICO — BAY MEDICAL"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#78c7bd"))
	vbox.add_child(title)

	triage_text = Label.new()
	triage_text.text = "Paciente posicionado na maca. Sinais vitais sob monitoramento."
	triage_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	triage_text.add_theme_font_size_override("font_size", 20)
	triage_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(triage_text)

	var hint := Label.new()
	_triage_hint = hint
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close" if is_en else "[ E / ESC ] Fechar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	triage_dialog.visible = false
	_refresh_triage_language()

func _unhandled_input(event: InputEvent) -> void:
	if not is_near_triage:
		return
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("interact"):
			if not triage_dialog.visible:
				_inspect_vitals()
			else:
				triage_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and triage_dialog.visible:
			triage_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _inspect_vitals() -> void:
	triage_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_ui_click_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	_refresh_triage_language()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_triage_hint):
		_refresh_triage_language()

func _refresh_triage_language() -> void:
	var en := TranslationServer.get_locale().begins_with("en")
	_triage_title.text = "✚ MEDICAL CARE — BAY MEDICAL" if en else "✚ ATENDIMENTO MÉDICO — BAY MEDICAL"
	_triage_hint.text = "[ E / ESC ] Close" if en else "[ E / ESC ] Fechar"
	triage_badge.text = "[ E ] TRIAGE & VITAL SIGNS" if en else "[ E ] POSTO DE TRIAGEM & SINAIS VITAIS"
	triage_text.text = "TRIAGEM MÉDICA (BAY MEDICAL):\n• Sinais vitais avaliados: Pressão arterial 120/80 mmHg, Pulso 72 BPM regular.\n• Quadro clínico geral estável.\n• Para atendimento ambulatorial ou curativos, consulte a Enfermeira Clara."
	if en:
		triage_text.text = "MEDICAL TRIAGE (BAY MEDICAL):\n• Vital signs assessed: Blood pressure 120/80 mmHg, regular pulse of 72 BPM.\n• General condition stable.\n• For outpatient care or dressings, consult Nurse Clara."

func _apply_first_aid() -> void:
	_inspect_vitals()

func _physics_process(delta: float) -> void:
	anim_clock += delta
	if ecg_line:
		var offset := sin(anim_clock * 6.0) * 1.5
		ecg_line.position.y = -50 + offset
