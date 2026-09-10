class_name HarborMorgueInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Reusable Morgue / IML (Instituto Médico Legal) interior template.
## Prepared for future district authoring without introducing unauthored preview lots.
## Features Dr. Silveira, refrigerated mortuary lockers, autopsy tables, and interactive registry log.

const NPC_SCRIPT := preload("res://world/harbor/interiors/HarborConversationalNPC.gd")
var pathologist_npc: CharacterBody2D
var registry_area: Area2D
var registry_badge: Label
var registry_dialog: PanelContainer
var registry_text: Label
var is_near_registry: bool = false

var frost_particles: CPUParticles2D

func _init() -> void:
	interior_id = &"morgue"
	display_name = "IML — INSTITUTO MÉDICO LEGAL"
	room_size = Vector2(740, 500)
	wall_color = Color("#0f172a")
	floor_color = Color("#1e293b")
	accent_color = Color("#94a3b8")

func _setup_interior_content() -> void:
	_build_morgue_layout()
	_build_pathologist()
	_build_ambient_frost()
	_build_registry_log()
	_create_spawn_and_exit(Vector2(0, 150), Vector2(0, 220), &"morgue_exterior_return", "SAIR DO IML")

func _build_morgue_layout() -> void:
	# Gavetões mortuários refrigerados na parede dos fundos
	var lockers := Polygon2D.new()
	lockers.color = Color("#334155")
	lockers.polygon = PackedVector2Array([
		Vector2(-180, -30), Vector2(180, -30),
		Vector2(180, 30), Vector2(-180, 30)
	])
	lockers.position = Vector2(0, -180)
	lockers.z_index = 2
	add_child(lockers)

	for col_idx in 8:
		var x := -160.0 + float(col_idx) * 45.0
		var handle := Line2D.new()
		handle.points = PackedVector2Array([Vector2(x - 10, -180), Vector2(x + 10, -180)])
		handle.width = 3.0
		handle.default_color = Color("#94a3b8")
		handle.z_index = 3
		add_child(handle)

	# Mesas de necropsia de aço inox
	for table_x in [-140, 140]:
		var table := Polygon2D.new()
		table.color = Color("#cbd5e1")
		table.polygon = PackedVector2Array([
			Vector2(-35, -55), Vector2(35, -55),
			Vector2(35, 55), Vector2(-35, 55)
		])
		table.position = Vector2(table_x, 20)
		table.z_index = 3
		add_child(table)

		var drain := Line2D.new()
		drain.points = PackedVector2Array([Vector2(0, -45), Vector2(0, 45)])
		drain.width = 2.0
		drain.default_color = Color("#64748b")
		drain.position = table.position
		drain.z_index = 4
		add_child(drain)

func _build_pathologist() -> void:
	pathologist_npc = NPC_SCRIPT.new()
	pathologist_npc.name = "DrSilveira"
	pathologist_npc.character_name = "Dr. Silveira"
	pathologist_npc.title_color = Color("#94a3b8")
	pathologist_npc.shirt_color = Color("#f1f5f9")
	pathologist_npc.pants_color = Color("#334155")
	pathologist_npc.skin_color = Color("#c7a783")
	pathologist_npc.dialogues = [
		"Instituto Médico Legal do Porto. Mantenha distância das mesas de exame, por favor.",
		"Os corpos recolhidos na baía contam histórias que os vivos preferem esquecer.",
		"A refrigeração está a -4°C constantes para preservar as evidências forenses.",
		"Se procura relatórios periciais de óbito, verifique a prancheta de registros ao lado."
	]
	pathologist_npc.position = Vector2(0, -70)
	add_child(pathologist_npc)

func _build_ambient_frost() -> void:
	# Partículas sutis de vapor refrigerado
	frost_particles = CPUParticles2D.new()
	frost_particles.position = Vector2(0, -150)
	frost_particles.amount = 16
	frost_particles.lifetime = 1.2
	frost_particles.direction = Vector2(0, 1)
	frost_particles.spread = 60.0
	frost_particles.gravity = Vector2(0, 20)
	frost_particles.initial_velocity_min = 15.0
	frost_particles.initial_velocity_max = 30.0
	frost_particles.color = Color(0.8, 0.9, 1.0, 0.25)
	frost_particles.z_index = 4
	add_child(frost_particles)

func _build_registry_log() -> void:
	var reg_pos := Vector2(0, 20)

	var desk := Polygon2D.new()
	desk.color = Color("#1e293b")
	desk.polygon = PackedVector2Array([
		Vector2(-40, -20), Vector2(40, -20),
		Vector2(40, 20), Vector2(-40, 20)
	])
	desk.position = reg_pos
	desk.z_index = 3
	add_child(desk)

	registry_area = Area2D.new()
	registry_area.collision_layer = 0
	registry_area.collision_mask = 4
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(100, 70)
	col.shape = rect
	registry_area.add_child(col)
	registry_area.position = reg_pos
	add_child(registry_area)

	registry_area.body_entered.connect(func(b):
		if b.is_in_group("player"):
			is_near_registry = true
			registry_badge.visible = true
	)
	registry_area.body_exited.connect(func(b):
		if b.is_in_group("player"):
			is_near_registry = false
			registry_badge.visible = false
			if registry_dialog.visible:
				registry_dialog.visible = false
				modal_closed.emit()
	)

	registry_badge = Label.new()
	registry_badge.text = "[ E ] PRANCHETA FORENSE & LIVRO DE ÓBITOS"
	registry_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	registry_badge.position = reg_pos + Vector2(-150, -45)
	registry_badge.size = Vector2(300, 20)
	registry_badge.add_theme_font_size_override("font_size", 10)
	registry_badge.add_theme_color_override("font_color", Color("#94a3b8"))
	registry_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	registry_badge.z_index = 10
	registry_badge.visible = false
	add_child(registry_badge)

	# Dialog
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	registry_dialog = PanelContainer.new()
	registry_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	registry_dialog.offset_left = 140.0
	registry_dialog.offset_right = -140.0
	registry_dialog.offset_bottom = -28.0
	registry_dialog.offset_top = -200.0
	registry_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(registry_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#94a3b8")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	registry_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	registry_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "📋 LIVRO DE REGISTRO FORENSE — IML"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(title)

	registry_text = Label.new()
	registry_text.text = "Registros periciais abertos. Causa mortis e laudos toxicológicos arquivados."
	registry_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	registry_text.add_theme_font_size_override("font_size", 20)
	registry_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(registry_text)

	var hint := Label.new()
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close" if is_en else "[ E / ESC ] Fechar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	registry_dialog.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_near_registry:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if not registry_dialog.visible:
				_read_registry()
			else:
				registry_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and registry_dialog.visible:
			registry_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _read_registry() -> void:
	registry_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_ui_click_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	registry_text.text = "LAUDO PERICIAL FORENSE #119:\n• Gaveta 04: Vítima de afogamento no Píer Norte (Identidade confirmada).\n• Gaveta 07: Confronto armado na zona industrial (Projéteis 9mm recolhidos).\n• Status das câmaras frias: Temperatura estável (-4.2°C)."
