extends CanvasLayer
## The panel emits intent only; session commits money + parts atomically, then
## calls show_vehicle with the authoritative state. No second wallet lives here.
signal purchase_requested(part_id: String)
signal remove_requested(slot: String)
signal closed
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
var _root: PanelContainer
var _title: Label
var _balance: Label
var _stats: Label
var _message: Label
var _rows: VBoxContainer
var _car_id := "desert_faisca"
var _parts: Dictionary = {}
var _owned: Array = []
var _wins := 0
var _money := 0

func _ready() -> void:
	layer = 36
	_root = PanelContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_root.offset_left = -400
	_root.offset_right = 400
	_root.offset_top = -295
	_root.offset_bottom = 295
	var style := StyleBoxFlat.new()
	style.bg_color = Color("181d21")
	style.border_color = Color("bba064")
	style.set_border_width_all(2)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_root.add_theme_stylebox_override("panel",style)
	add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	_root.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size",23)
	header.add_child(_title)
	var close := Button.new()
	close.text = "Voltar [Esc]"
	close.pressed.connect(close_panel)
	header.add_child(close)
	_balance = Label.new()
	column.add_child(_balance)
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stats)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 395
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation",7)
	scroll.add_child(_rows)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	hide()

func show_vehicle(car_id: String, parts: Dictionary, owned: Array, wins: int, money: int) -> void:
	_car_id = car_id
	_parts = TUNING.clean_parts(parts)
	_owned = owned.duplicate()
	_wins = maxi(0,wins)
	_money = maxi(0,money)
	_title.text = "Digo · %s" % CARS.spec(car_id).get("label",car_id)
	_balance.text = "R$ %d     ·     %d vitórias diferentes" % [_money,_wins]
	var s := TUNING.tuned_spec(_car_id,_parts)
	_stats.text = "%d Nm  |  %d kg  |  %d marchas  |  Nitro %.1f s" % [roundi(float(s.torque_nm)),roundi(float(s.mass)*1000.0),s.gears.size(),float(s.nitro_seconds)]
	for old in _rows.get_children():
		_rows.remove_child(old)
		old.queue_free()
	for id in TUNING.PARTS: _add_part(str(id))
	_message.text = ""
	show()

func set_message(message: String) -> void:
	_message.text = message

func close_panel() -> void:
	if not visible: return
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()

func _add_part(id: String) -> void:
	var p: Dictionary = TUNING.PARTS[id]
	var row := HBoxContainer.new()
	_rows.add_child(row)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	var label := Label.new()
	label.text = str(p.label)
	label.add_theme_font_size_override("font_size",18)
	description.add_child(label)
	var effect := Label.new()
	effect.text = str(p.effect)
	effect.add_theme_font_size_override("font_size",14)
	effect.modulate = Color("b9c0c6")
	description.add_child(effect)
	var button := Button.new()
	button.custom_minimum_size.x = 156
	row.add_child(button)
	var installed := str(_parts.get(str(p.slot),"")) == id
	if installed:
		button.text = "Remover"
		button.pressed.connect(func(): remove_requested.emit(str(p.slot)))
	elif _wins < int(p.wins):
		button.text = "%d vitórias" % int(p.wins)
		button.disabled = true
	else:
		var cost := 0 if id in _owned else int(p.cost)
		button.text = "Instalar" if cost == 0 else "R$ %d" % cost
		button.disabled = _money < cost
		button.pressed.connect(func(): purchase_requested.emit(id))
