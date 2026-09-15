class_name HarborWorkshopInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Workshop interior for Northgate Auto.
## Features Master Mechanic Arnaldo, overhead engine hoist,
## rotating shop fan, and interactive engine tuning & parts bench.

const NPC_SCRIPT := preload("res://world/harbor/interiors/HarborConversationalNPC.gd")
var mechanic_npc: CharacterBody2D
var bench_area: Area2D
var bench_badge: Label
var bench_dialog: PanelContainer
var bench_text: Label
var is_near_bench: bool = false

var hoist_cable: Line2D
var fan_blade: Polygon2D
var anim_clock: float = 0.0

func _init() -> void:
	interior_id = &"motor_workshop"
	display_name = "NORTHGATE AUTO — OFICINA MECÂNICA"
	room_size = Vector2(720, 500)
	wall_color = Color("#1c1917")
	floor_color = Color("#292524")
	accent_color = Color("#d7ae68")

func _setup_interior_content() -> void:
	_build_workshop_elements()
	_build_mechanic()
	_build_ambient_animations()
	_build_tuning_bench()
	_create_spawn_and_exit(Vector2(0, 150), Vector2(0, 220), &"harbor/NorthDistrict/MotorWorkshop/Entrance/exit", "SAIR DA OFICINA")

func _build_workshop_elements() -> void:
	# Armários de ferramentas e peças
	var shelves := Polygon2D.new()
	shelves.color = Color("#44403c")
	shelves.polygon = PackedVector2Array([
		Vector2(-100, -20), Vector2(100, -20),
		Vector2(100, 20), Vector2(-100, 20)
	])
	shelves.position = Vector2(-180, -180)
	shelves.z_index = 2
	add_child(shelves)

	# Tambores de óleo
	for drum_x in [160, 200]:
		var drum := Polygon2D.new()
		drum.color = Color("#b91c1c")
		drum.polygon = PackedVector2Array([
			Vector2(-12, -15), Vector2(12, -15),
			Vector2(12, 15), Vector2(-12, 15)
		])
		drum.position = Vector2(drum_x, -180)
		drum.z_index = 2
		add_child(drum)

func _build_mechanic() -> void:
	mechanic_npc = NPC_SCRIPT.new()
	mechanic_npc.name = "MasterArnaldo"
	mechanic_npc.character_name = "Mestre Arnaldo"
	mechanic_npc.title_color = Color("#d7ae68")
	mechanic_npc.shirt_color = Color("#78350f")
	mechanic_npc.pants_color = Color("#451a03")
	mechanic_npc.dialogues = [
		"Opa! Bem-vindo à Northgate Auto. Aqui a gente faz milagre até em carburador afogado.",
		"Os caminhões que chegam da rodovia acabam com a suspensão nas ruas de paralelepípedo.",
		"Se precisar checar a pressão do turbo ou a taxa de compressão, use minha bancada de testes ali.",
		"Motor bem calibrado e óleo novo: é tudo que um carro precisa pra durar vinte anos."
	]
	mechanic_npc.position = Vector2(80, -80)
	add_child(mechanic_npc)

func _build_ambient_animations() -> void:
	# Bloco de motor suspenso por guincho
	hoist_cable = Line2D.new()
	hoist_cable.points = PackedVector2Array([Vector2(0, -240), Vector2(0, -100)])
	hoist_cable.width = 2.0
	hoist_cable.default_color = Color("#a8a29e")
	hoist_cable.z_index = 4
	add_child(hoist_cable)

	var engine_block := Polygon2D.new()
	engine_block.color = Color("#57534e")
	engine_block.polygon = PackedVector2Array([
		Vector2(-20, -16), Vector2(20, -16),
		Vector2(20, 16), Vector2(-20, 16)
	])
	engine_block.position = Vector2(0, -100)
	engine_block.z_index = 5
	hoist_cable.add_child(engine_block)

	# Ventilador de oficina
	fan_blade = Polygon2D.new()
	fan_blade.color = Color("#d6d3d1")
	fan_blade.polygon = PackedVector2Array([
		Vector2(-14, -4), Vector2(14, -4), Vector2(14, 4), Vector2(-14, 4)
	])
	fan_blade.position = Vector2(240, -100)
	fan_blade.z_index = 4
	add_child(fan_blade)

func _build_tuning_bench() -> void:
	var bench_pos := Vector2(-200, 30)

	var bench := Polygon2D.new()
	bench.color = Color("#7f1d1d")
	bench.polygon = PackedVector2Array([
		Vector2(-50, -25), Vector2(50, -25),
		Vector2(50, 25), Vector2(-50, 25)
	])
	bench.position = bench_pos
	bench.z_index = 3
	add_child(bench)

	bench_area = Area2D.new()
	bench_area.collision_layer = 0
	bench_area.collision_mask = 4
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 90)
	col.shape = rect
	bench_area.add_child(col)
	bench_area.position = bench_pos
	add_child(bench_area)

	bench_area.body_entered.connect(func(b):
		if b.is_in_group("player"):
			is_near_bench = true
			bench_badge.visible = true
	)
	bench_area.body_exited.connect(func(b):
		if b.is_in_group("player"):
			is_near_bench = false
			bench_badge.visible = false
			if bench_dialog.visible:
				bench_dialog.visible = false
				modal_closed.emit()
	)

	bench_badge = Label.new()
	bench_badge.text = "E"
	bench_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bench_badge.position = bench_pos + Vector2(-140, -55)
	bench_badge.size = Vector2(280, 20)
	bench_badge.add_theme_font_size_override("font_size", 10)
	bench_badge.add_theme_color_override("font_color", Color("#d7ae68"))
	bench_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	bench_badge.z_index = 10
	bench_badge.visible = false
	add_child(bench_badge)

	# UI do Dialog
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	bench_dialog = PanelContainer.new()
	bench_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bench_dialog.offset_left = 140.0
	bench_dialog.offset_right = -140.0
	bench_dialog.offset_bottom = -28.0
	bench_dialog.offset_top = -200.0
	bench_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(bench_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.06, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#d7ae68")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	bench_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	bench_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "🔧 BANCADA MECÂNICA — NORTHGATE AUTO"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d7ae68"))
	vbox.add_child(title)

	bench_text = Label.new()
	bench_text.text = "Relatório de oficina: Equipamento de retífica calibrado. Peças de reposição disponíveis."
	bench_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bench_text.add_theme_font_size_override("font_size", 20)
	bench_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(bench_text)

	var hint := Label.new()
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close bench" if is_en else "[ E / ESC ] Fechar bancada"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	bench_dialog.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_near_bench:
		return
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("interact"):
			if not bench_dialog.visible:
				_run_tuning()
			else:
				bench_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and bench_dialog.visible:
			bench_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _run_tuning() -> void:
	bench_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_cash_register_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	bench_text.text = "INSPEÇÃO DE MOTOR REALIZADA:\n• Taxa de compressão: 10.5:1 (Excelente).\n• Velas de ignição limpas e eletrodos ajustados.\n• Aditivo de refrigeração e fluido de freio DOT 4 verificados."

func _physics_process(delta: float) -> void:
	anim_clock += delta
	if fan_blade:
		fan_blade.rotation += 12.0 * delta
	if hoist_cable:
		var sway := sin(anim_clock * 2.0) * 0.05
		hoist_cable.rotation = sway
