extends Control
## A static race-entry screen: no live portraits or per-frame UI work.
signal closed
signal race_requested(identity: String)
signal instruments_requested
signal takeshi_requested
signal open_meet_requested
signal night_requested(identity: String)
signal return_requested(identity: String)
signal challenges_requested
signal loaner_requested
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const NIGHT_CATALOG := preload("res://activities/desert_drag/DragNightCatalog.gd")
const NAMES := ["Digo", "Lívia", "Raul", "Jessica", "Nadir", "Rauhz"]
const ATLAS_IDS := ["digo", "livia", "raul", "jessica", "nadir"]
const ROW_STEP := 72
const ROW_HEIGHT := 65
const INK := Color("f0f3f5")
const MUTED := Color("8f9ba7")
const AMBER := Color("ffbc55")
const CYAN := Color("66d5dd")
var font: Font
var bold: Font
var photos: Dictionary = {}
var wins: Array = []
var best: Dictionary = {}
var selected := "digo"
var current := "digo"
var strike: Dictionary = {}
var rows: Array[Button] = []
var race_button: Button
var instruments_button: Button
var takeshi_button: Button
var message := ""
var open_meet_button: Button
var night_button: Button
var return_button: Button
var challenges_button: Button
var loaner_button: Button

func _ready() -> void:
	font = _font("Regular")
	bold = _font("SemiBold")
	var atlas_path := "res://assets/desert_drag/portraits/roster-cinematic.png"
	var atlas: Texture2D
	if ResourceLoader.exists(atlas_path): atlas = load(atlas_path)
	elif FileAccess.file_exists(atlas_path): atlas = ImageTexture.create_from_image(Image.load_from_file(atlas_path))
	for index in PROGRESS.RIVALS.size():
		var id: String = PROGRESS.RIVALS[index]
		if atlas != null and id in ATLAS_IDS:
			var portrait := AtlasTexture.new()
			portrait.atlas = atlas
			var column_width := float(atlas.get_width()) / float(ATLAS_IDS.size())
			portrait.region = Rect2(float(ATLAS_IDS.find(id)) * column_width, 0, column_width, atlas.get_height())
			portrait.filter_clip = true
			photos[id] = portrait
		else:
			var path: String = "res://assets/desert_drag/portraits/" + id + ".png"
			photos[id] = load(path) if ResourceLoader.exists(path) else ImageTexture.create_from_image(Image.load_from_file(path))
	custom_minimum_size = Vector2(900, 640)
	size = custom_minimum_size
	resized.connect(queue_redraw)
	for i in PROGRESS.RIVALS.size():
		var row := Button.new()
		row.name = PROGRESS.RIVALS[i]
		row.position = Vector2(30, 134 + i * ROW_STEP)
		row.size = Vector2(477, ROW_HEIGHT)
		row.flat = true
		row.tooltip_text = NAMES[i]
		row.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		row.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, .045)))
		row.add_theme_stylebox_override("pressed", _style(Color(1, 1, 1, .07)))
		row.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CYAN))
		row.pressed.connect(select_rival.bind(str(PROGRESS.RIVALS[i])))
		row.focus_entered.connect(select_rival.bind(str(PROGRESS.RIVALS[i])))
		add_child(row)
		rows.append(row)
	var close := Button.new()
	close.text = "FECHAR  ×"
	close.position = Vector2(736, 30)
	close.size = Vector2(132, 40)
	_button_style(close, false)
	close.pressed.connect(func(): closed.emit())
	add_child(close)
	instruments_button = Button.new()
	instruments_button.text = "PAINÉIS"
	instruments_button.position = Vector2(582,30)
	instruments_button.size = Vector2(140,40)
	_button_style(instruments_button,false)
	instruments_button.pressed.connect(func(): instruments_requested.emit())
	add_child(instruments_button)
	takeshi_button = Button.new()
	takeshi_button.name = "TakeshiChallenge"
	takeshi_button.text = "TAKESHI"
	takeshi_button.position = Vector2(554,592)
	takeshi_button.size = Vector2(150,28)
	_button_style(takeshi_button,false)
	takeshi_button.add_theme_font_size_override("font_size",15)
	takeshi_button.pressed.connect(func(): takeshi_requested.emit())
	add_child(takeshi_button)
	open_meet_button = Button.new()
	open_meet_button.text = "BATERIAS LIVRES"
	open_meet_button.position = Vector2(30,592)
	open_meet_button.size = Vector2(220,28)
	_button_style(open_meet_button,false)
	open_meet_button.add_theme_font_size_override("font_size",15)
	open_meet_button.pressed.connect(func(): open_meet_requested.emit())
	add_child(open_meet_button)
	challenges_button = Button.new()
	challenges_button.name = "DesafiosDosRivais"
	challenges_button.text = "DESAFIOS DOS RIVAIS"
	challenges_button.position = Vector2(266,592)
	challenges_button.size = Vector2(272,28)
	_button_style(challenges_button,false)
	challenges_button.add_theme_font_size_override("font_size",15)
	challenges_button.pressed.connect(func(): challenges_requested.emit())
	add_child(challenges_button)
	race_button = Button.new()
	race_button.position = Vector2(551, 475)
	race_button.size = Vector2(317, 44)
	_button_style(race_button, true)
	race_button.pressed.connect(func(): race_requested.emit(selected))
	add_child(race_button)
	night_button = Button.new()
	night_button.name = "NoiteDeAcerto"
	night_button.text = "NOITE DE ACERTO"
	night_button.position = Vector2(551, 527)
	night_button.size = Vector2(154, 40)
	_button_style(night_button, false)
	night_button.add_theme_font_size_override("font_size",15)
	night_button.pressed.connect(func(): night_requested.emit(selected))
	add_child(night_button)
	return_button=Button.new()
	return_button.name="IdaEVolta"
	return_button.text="IDA E VOLTA"
	return_button.position=Vector2(714,527)
	return_button.size=Vector2(154,40)
	_button_style(return_button,false)
	return_button.add_theme_font_size_override("font_size",15)
	return_button.pressed.connect(func(): return_requested.emit(selected))
	add_child(return_button)
	loaner_button=Button.new()
	loaner_button.name="CarroDaOficina"
	loaner_button.text="CARRO DA OFICINA"
	loaner_button.position=Vector2(30,96)
	loaner_button.size=Vector2(300,30)
	_button_style(loaner_button,false)
	loaner_button.add_theme_font_size_override("font_size",15)
	loaner_button.pressed.connect(func(): loaner_requested.emit())
	add_child(loaner_button)
	_update_button()

func _font(weight: String) -> Font:
	var path := "res://assets/fonts/barlow/BarlowSemiCondensed-" + weight + ".ttf"
	if ResourceLoader.exists(path): return load(path)
	var file := FontFile.new()
	file.load_dynamic_font(path)
	return file

func show_progress(state: Dictionary, newly_won := "") -> void:
	wins = state.get("wins", []).duplicate()
	best = state.get("best", {}).duplicate()
	current = PROGRESS.RIVALS.back()
	for id in PROGRESS.RIVALS:
		if id not in wins:
			current = id
			break
	if newly_won in wins: selected = newly_won
	elif selected not in wins and selected != current: selected = current
	message = ""
	strike.clear()
	for id in wins: strike[id] = 1.0
	_update_button()
	rows[PROGRESS.RIVALS.find(selected)].grab_focus()
	queue_redraw()

func select_rival(id: String) -> void:
	if id not in PROGRESS.RIVALS: return
	selected = id
	message = ""
	_update_button()
	queue_redraw()

func set_message(text: String) -> void:
	message = text
	open_meet_button.visible = message.is_empty()
	takeshi_button.visible = message.is_empty()
	challenges_button.visible = message.is_empty()
	queue_redraw()

func _update_button() -> void:
	if race_button == null: return
	open_meet_button.visible = message.is_empty()
	takeshi_button.visible = message.is_empty()
	challenges_button.visible = message.is_empty()
	race_button.disabled = selected != current and selected not in wins
	night_button.disabled = race_button.disabled
	return_button.disabled = race_button.disabled
	race_button.text = "REVANCHE  →" if selected in wins else ("CORRER  →" if selected == current else "VENÇA " + NAMES[PROGRESS.RIVALS.find(current)].to_upper())

func _style(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0.0 else 0)
	box.set_corner_radius_all(3)
	return box

func _button_style(button: Button, primary: bool) -> void:
	button.add_theme_font_override("font", bold)
	button.add_theme_font_size_override("font_size", 23 if primary else 17)
	button.add_theme_color_override("font_color", Color("13171d") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("13171d") if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color("13171d") if primary else INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(AMBER if primary else Color("222b34")))
	button.add_theme_stylebox_override("hover", _style(Color("ffce7b") if primary else Color("34414e")))
	button.add_theme_stylebox_override("pressed", _style(Color("e0a145") if primary else Color("425261")))
	button.add_theme_stylebox_override("disabled", _style(Color("222b34")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CYAN))

func _label(at: Vector2, text: String, point_size: int, color := INK, strong := false, width := -1.0) -> void:
	draw_string(bold if strong else font, at, tr(text), HORIZONTAL_ALIGNMENT_LEFT, width, point_size, color)

func _portrait(id: String, destination: Rect2, tint := Color.WHITE) -> void:
	var photo: Texture2D = photos[id]
	var extent := Vector2(photo.get_size())
	# Mantém as proporções escritas do retrato. O atlas alto é recortado num
	# rosto; o render de recurso já é quadrado. Sem esticar rostos.
	var crop := Vector2(extent.x, extent.x * destination.size.y / destination.size.x)
	if crop.y > extent.y: crop = Vector2(extent.y * destination.size.x / destination.size.y, extent.y)
	var origin := Vector2((extent.x - crop.x) * .5, minf(extent.y * .06, extent.y - crop.y))
	draw_texture_rect_region(photo, destination, Rect2(origin, crop), tint)

func _draw() -> void:
	if font == null: return
	draw_style_box(_style(Color(0, 0, 0, .35)), Rect2(7, 9, 900, 640))
	draw_style_box(_style(Color("11171e"), Color("34414e")), Rect2(0, 0, 900, 640))
	draw_rect(Rect2(0, 0, 900, 4), AMBER)
	_label(Vector2(32, 32), "DESERTO / 800 M", 15, MUTED, true)
	_label(Vector2(30, 79), "ARRANCADAS", 43, INK, true)
	_label(Vector2(450, 46), "%02d / %02d" % [wins.size(),PROGRESS.RIVALS.size()], 26, AMBER, true)
	_label(Vector2(450, 69), "VITÓRIAS", 13, MUTED, true)
	draw_line(Vector2(30, 95), Vector2(868, 95), Color("34414e"), 1)
	# A entrada de empréstimo da oficina ocupa o antigo título decorativo da lista.
	_label(Vector2(400, 120), "STATUS", 14, MUTED, true)
	for i in PROGRESS.RIVALS.size():
		var id: String = PROGRESS.RIVALS[i]
		var y := 134.0 + float(i) * ROW_STEP
		var unlocked: bool = id == current or id in wins
		var chosen: bool = id == selected
		draw_style_box(_style(Color("263340") if chosen else Color("19222c")), Rect2(30, y, 477, ROW_HEIGHT))
		if chosen: draw_rect(Rect2(30, y, 3, ROW_HEIGHT), AMBER)
		_label(Vector2(45, y + 44), "%02d" % (i + 1), 23, AMBER if chosen else MUTED, true)
		_portrait(id, Rect2(85, y + 5, 55, 55), Color.WHITE if unlocked else Color(.53, .58, .63))
		_label(Vector2(160, y + 43), NAMES[i].to_upper(), 27, INK if unlocked else MUTED, true)
		var status := "REVANCHE" if id in wins else ("DISPONÍVEL" if id == current else "BLOQUEADO")
		_label(Vector2(394, y + 42), status, 14, CYAN if id in wins else (AMBER if id == current else MUTED), true)
	var index := PROGRESS.RIVALS.find(selected)
	draw_rect(Rect2(551, 110, 317, 208), Color("1b2630"))
	_portrait(selected, Rect2(626, 110, 168, 208))
	draw_rect(Rect2(551, 263, 317, 55), Color(.045, .065, .085, .93))
	_label(Vector2(568, 300), NAMES[index].to_upper(), 32, INK, true)
	var specialty := NIGHT_CATALOG.get_rival(selected)
	_label(Vector2(551, 343), str(specialty.specialty).to_upper(), 18, AMBER, true,317)
	_label(Vector2(551, 367), "PRIMEIRA VITÓRIA" if selected not in wins else "PRÊMIO CONQUISTADO", 13, MUTED, true)
	_label(Vector2(551, 398), "R$ %d" % PROGRESS.reward_amount(selected), 27, AMBER, true)
	_label(Vector2(741, 367), "RECORDE · 800 M", 13, MUTED, true)
	_label(Vector2(741, 398), "%.3f s" % float(best[selected]) if best.has(selected) else "—", 25, INK, true)
	_label(Vector2(551, 424), str(specialty.parts), 15, INK, true,317)
	if selected in wins:
		_label(Vector2(551, 454), "201 M  /  2 × 402 M  /  800 M", 15, CYAN, true)
	elif selected != current:
		_label(Vector2(551, 454), "VENÇA " + NAMES[PROGRESS.RIVALS.find(current)].to_upper() + " PARA LIBERAR", 15, MUTED, true)
	else:
		_label(Vector2(551, 454), "201 M  /  2 × 402 M  /  800 M", 15, MUTED, true)
	draw_line(Vector2(30, 581), Vector2(868, 581), Color("34414e"), 1)
	if not message.is_empty():
		draw_multiline_string(font, Vector2(32, 605), message, HORIZONTAL_ALIGNMENT_LEFT, 835, 17, 2, AMBER)
	else:
		_label(Vector2(270, 610), "TAB / ENTER  SELECIONAR", 15, MUTED)
		_label(Vector2(739, 610), "ESC  VOLTAR", 15, MUTED)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED: queue_redraw()
