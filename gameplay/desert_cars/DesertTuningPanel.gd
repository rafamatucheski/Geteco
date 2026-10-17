extends CanvasLayer
## The panel emits intent only; session commits money + parts atomically, then
## calls show_vehicle with the authoritative state. No second wallet lives here.
## Passar o mouse (ou o foco) numa peça mostra nas barras como o carro ficaria.
signal purchase_requested(part_id: String)
signal remove_requested(slot: String)
signal closed
const STYLE := preload("res://ui/GameStyle.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const PERF := preload("res://data/catalogs/VehiclePerformance.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const RACE_WINS := preload("res://systems/campaign/RaceWins.gd")
const SHOWROOM := preload("res://gameplay/desert_cars/TuningShowroom.gd")
const GOLD := Color("d8b45f")
const MUTED := Color("8b949c")
const GOOD := Color("5fcf86")
const BAD := Color("e0614f")
const CLASS_COLORS := {"S":Color("e3b341"),"A":Color("e0573b"),"B":Color("a068e0"),"C":Color("4a90d9"),"D":Color("7d858c")}
const STATS := [["rate_accel","Aceleração"],["rate_speed","Velocidade final"],["rate_handling","Curva"],["rate_braking","Frenagem"]]
var _root: PanelContainer
var _dim: ColorRect
var _showroom: SubViewportContainer
var _title: Label
var _subtitle: Label
var _badge: PanelContainer
var _badge_letter: Label
var _wallet: Label
var _numbers: Label
var _message: Label
var _tabs: HFlowContainer
var _cards: VBoxContainer
var _scroll: ScrollContainer
var _bars: Array = []
var _root_control: Control
var _car_id := "desert_faisca"
var _parts: Dictionary = {}
var _owned: Array = []
var _wins := 0
var _money := 0
var _slot := ""
var _pending := ""
var _base: Dictionary = {}
var _stats_panel: Control
var _view_controls: HBoxContainer
var _rotation_button: Button
## Quem prepara o carro: o Digo no deserto, o mecânico na Maciota.
var mechanic_name := "Digo"

func _ready() -> void:
	layer = 36
	_root_control = Control.new()
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.theme = STYLE.create_theme(15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var button_style := STYLE.button(false)
		button_style.set_corner_radius_all(3)
		button_style.content_margin_top = 6
		button_style.content_margin_bottom = 6
		button_style.border_color = GOLD if state in ["hover", "focus", "pressed"] else STYLE.LINE
		_root_control.theme.set_stylebox(state, "Button", button_style)
	add_child(_root_control)
	_dim = ColorRect.new()
	_dim.color = Color("101719")
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_control.add_child(_dim)
	# Carro à direita, lista à esquerda e desempenho embaixo, como nas oficinas de GTA.
	_showroom = SHOWROOM.new()
	_showroom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showroom.offset_left = 432.0
	_root_control.add_child(_showroom)
	_root = PanelContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_root.offset_left = 20.0
	_root.offset_right = 432.0
	_root.offset_top = 20.0
	_root.offset_bottom = -20.0
	_root.add_theme_stylebox_override("panel",_box(STYLE.INK,STYLE.LINE,1,8,16))
	_root_control.add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	_root.add_child(column)
	column.add_child(_build_header())
	var parts := _build_parts()
	parts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(parts)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color",GOLD)
	column.add_child(_message)
	_stats_panel = _build_stats()
	_stats_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_stats_panel.offset_left = 452.0
	_stats_panel.offset_right = -20.0
	_stats_panel.offset_top = -164.0
	_stats_panel.offset_bottom = -20.0
	_root_control.add_child(_stats_panel)
	_view_controls = _build_view_controls()
	_view_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_view_controls.offset_left = -355.0
	_view_controls.offset_right = -20.0
	_view_controls.offset_top = 20.0
	_view_controls.offset_bottom = 56.0
	_root_control.add_child(_view_controls)
	visibility_changed.connect(func(): if not visible: _showroom.hide_showroom())
	hide()

func _box(fill: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(mini(radius,3))
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin*.8
	style.content_margin_bottom = margin*.8
	return style

func _build_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",6)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	box.add_child(header)
	_badge = PanelContainer.new()
	_badge.custom_minimum_size = Vector2(42,48)
	_badge_letter = Label.new()
	_badge_letter.add_theme_font_size_override("font_size",32)
	_badge_letter.add_theme_color_override("font_color",Color("101215"))
	_badge_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_letter)
	header.add_child(_badge)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.add_theme_font_size_override("font_size",24)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color",MUTED)
	names.add_child(_subtitle)
	header.add_child(names)
	var close := Button.new()
	close.text = "Esc"
	close.tooltip_text = "Voltar à oficina"
	close.pressed.connect(close_panel)
	header.add_child(close)
	_wallet = Label.new()
	_wallet.add_theme_font_size_override("font_size",17)
	_wallet.add_theme_color_override("font_color",GOLD)
	box.add_child(_wallet)
	return box

func _build_stats() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_box(Color("14181cee"),Color("2c343c"),1,10,16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	panel.add_child(row)
	var bars := VBoxContainer.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_theme_constant_override("separation",9)
	row.add_child(bars)
	for stat in STATS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation",12)
		var name_label := Label.new()
		name_label.text = str(stat[1])
		name_label.custom_minimum_size = Vector2(138,0)
		line.add_child(name_label)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0,14)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var under := _bar(Color("2e353c"))
		var over := _bar(Color(0,0,0,0))
		holder.add_child(under)
		holder.add_child(over)
		line.add_child(holder)
		var value := Label.new()
		value.custom_minimum_size = Vector2(84,0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		bars.add_child(line)
		_bars.append({"key":str(stat[0]),"value":value,"under":under,"over":over})
	_numbers = Label.new()
	_numbers.custom_minimum_size = Vector2(168,0)
	_numbers.add_theme_color_override("font_color",MUTED)
	_numbers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_numbers)
	return panel

func _build_view_controls() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	for entry in [["−",-.1],["+",.1]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(36,36)
		button.pressed.connect(_showroom.zoom_by.bind(float(entry[1])))
		row.add_child(button)
	_rotation_button = Button.new()
	_rotation_button.text = "Girar"
	_rotation_button.toggle_mode = true
	_rotation_button.button_pressed = true
	_rotation_button.toggled.connect(_showroom.set_auto_rotate)
	row.add_child(_rotation_button)
	var reset := Button.new()
	reset.text = "Recentrar"
	reset.pressed.connect(func(): _showroom.reset_view(); _rotation_button.set_pressed_no_signal(true))
	row.add_child(reset)
	return row

func _bar(background: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.add_theme_stylebox_override("background",_box(background,Color(0,0,0,0),0,4,0))
	bar.add_theme_stylebox_override("fill",_box(GOLD,Color(0,0,0,0),0,4,0))
	return bar

func _build_parts() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",10)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation",6)
	_tabs.add_theme_constant_override("v_separation",6)
	box.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation",8)
	_scroll.add_child(_cards)
	box.add_child(_scroll)
	return box

func show_vehicle(car_id: String, parts: Dictionary, owned: Array, wins: int, money: int, appearance: Dictionary = {}) -> void:
	if car_id != _car_id or _slot.is_empty(): _slot = TUNING.SLOTS[0]
	_car_id = car_id
	_parts = TUNING.clean_parts(parts)
	_owned = owned.duplicate()
	_wins = maxi(0,wins)
	_money = maxi(0,money)
	_pending = ""
	_base = PERF.measure(_car_id,_parts)
	var label := str(FLEET.spec(car_id).get("label",car_id))
	_title.text = label
	_wallet.text = String(TranslationServer.translate("R$ %s   ·   %d de %d vitórias")) % [_money_text(_money),_wins,RACE_WINS.maximum()]
	_message.text = ""
	_rebuild_tabs()
	_rebuild_cards()
	_preview({})
	show()
	var shown_model := str(appearance.get("archetype",car_id))
	_showroom.show_car(shown_model,appearance.get("paint",FLEET.default_paint(shown_model,Color.WHITE)),_parts)
	_rotation_button.set_pressed_no_signal(_showroom._auto_rotate)
	_focus_first()

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

func _money_text(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length()-i) % 3 == 0: out += "."
		out += digits[i]
	return out

func _rebuild_tabs() -> void:
	for old in _tabs.get_children():
		_tabs.remove_child(old)
		old.queue_free()
	for slot in TUNING.SLOTS:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_pressed = str(slot) == _slot
		tab.text = str(TUNING.SLOT_LABELS[slot])+(" ●" if _parts.has(slot) else "")
		tab.custom_minimum_size = Vector2(60,32)
		var selected := _box(Color("3a3320"),GOLD,2,6,8)
		tab.add_theme_stylebox_override("pressed",selected)
		tab.add_theme_stylebox_override("hover_pressed",selected)
		tab.add_theme_color_override("font_pressed_color",GOLD)
		tab.pressed.connect(_select_slot.bind(str(slot)))
		_tabs.add_child(tab)

func _select_slot(slot: String) -> void:
	_slot = slot
	_pending = ""
	_message.text = ""
	_rebuild_tabs()
	_rebuild_cards()
	_preview({})

func _rebuild_cards() -> void:
	for old in _cards.get_children():
		_cards.remove_child(old)
		old.queue_free()
	var ids: Array = []
	for id in TUNING.PARTS:
		if str(TUNING.PARTS[id].slot) == _slot: ids.append(str(id))
	ids.sort_custom(func(a,b): return int(TUNING.PARTS[a].wins) < int(TUNING.PARTS[b].wins) or (int(TUNING.PARTS[a].wins) == int(TUNING.PARTS[b].wins) and int(TUNING.PARTS[a].cost) < int(TUNING.PARTS[b].cost)))
	for id in ids: _cards.add_child(_card(str(id)))

## Acesso estável para testes e atalhos: abre o espaço da peça e devolve o botão do cartão.
func button_for_part(id: String) -> Button:
	if not TUNING.PARTS.has(id): return null
	if str(TUNING.PARTS[id].slot) != _slot: _select_slot(str(TUNING.PARTS[id].slot))
	for card in _cards.get_children():
		if str(card.get_meta("part_id","")) == id: return card.get_meta("action_button") as Button
	return null

func _card(id: String) -> Control:
	var part: Dictionary = TUNING.PARTS[id]
	var installed: bool = str(_parts.get(_slot,"")) == id
	var locked := _wins < int(part.wins)
	var cost := 0 if id in _owned else int(part.cost)
	var panel := PanelContainer.new()
	panel.set_meta("part_id",id)
	var border := GOOD if installed else (Color("2c343c") if not locked else Color("22282e"))
	panel.add_theme_stylebox_override("panel",_box(Color("1b2026") if not locked else Color("171b20"),border,2 if installed else 1,8,14))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = str(part.label)+("   ✓ INSTALADA" if installed else "")
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size",16)
	name_label.add_theme_color_override("font_color",GOOD if installed else (MUTED if locked else Color.WHITE))
	if part.has("neon") or part.has("body_color") or part.has("wheel_color"):
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation",10)
		var swatch := PanelContainer.new()
		swatch.custom_minimum_size = Vector2(20,20)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_theme_stylebox_override("panel",_box(Color(str(part.get("neon",part.get("body_color",part.get("wheel_color","ffffff"))))),Color(1,1,1,.35),1,10,0))
		title_row.add_child(swatch)
		title_row.add_child(name_label)
		info.add_child(title_row)
	else:
		info.add_child(name_label)
	var effect := Label.new()
	effect.text = str(part.effect)
	effect.visible = part.has("wheel_color") or not (part.has("body_color") or part.has("body_roughness"))
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_color_override("font_color",MUTED)
	info.add_child(effect)
	row.add_child(info)
	var side := HBoxContainer.new()
	side.add_theme_constant_override("separation",10)
	var price := Label.new()
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if locked: price.text = String(TranslationServer.translate("Vença %d provas (você: %d)")) % [int(part.wins),_wins]
	elif id in _owned: price.text = "Comprada"
	else: price.text = "R$ %s" % _money_text(cost)
	price.add_theme_color_override("font_color",MUTED if locked or id in _owned else GOLD)
	side.add_child(price)
	var button := Button.new()
	button.custom_minimum_size = Vector2(112,36)
	var action_style := STYLE.button(not installed and not locked and cost <= _money)
	action_style.set_corner_radius_all(3)
	action_style.content_margin_top = 6
	action_style.content_margin_bottom = 6
	button.add_theme_stylebox_override("normal",action_style)
	panel.set_meta("action_button",button)
	if installed:
		button.text = "Remover"
		button.pressed.connect(func(): remove_requested.emit(_slot))
	elif locked:
		button.text = "Bloqueada"
		button.disabled = true
	elif cost > _money:
		button.text = String(TranslationServer.translate("Falta R$ %s")) % _money_text(cost-_money)
		button.disabled = true
	elif cost == 0:
		button.text = "Instalar"
		button.pressed.connect(func(): purchase_requested.emit(id))
	else:
		button.text = "Comprar e instalar" if _pending != id else String(TranslationServer.translate("Confirmar R$ %s")) % _money_text(cost)
		button.pressed.connect(_buy_pressed.bind(id))
	side.add_child(button)
	row.add_child(side)
	var preview := {} if installed else {"slot":_slot,"id":id}
	if installed: preview = {"slot":_slot,"id":""}
	panel.mouse_entered.connect(_preview.bind(preview))
	button.mouse_entered.connect(_preview.bind(preview))
	button.focus_entered.connect(_preview.bind(preview))
	button.focus_exited.connect(_preview.bind({}))
	panel.mouse_exited.connect(_preview.bind({}))
	return panel

func _buy_pressed(id: String) -> void:
	if _pending == id:
		_pending = ""
		purchase_requested.emit(id)
		return
	_pending = id
	_rebuild_cards()
	_message.text = "Confirme para comprar e instalar a peça."
	# Os cartões foram refeitos: devolve o foco ao mesmo botão para confirmar pelo teclado.
	var again := button_for_part(id)
	_focus_later(again)

## `change` é {slot,id}: como o carro ficaria com essa peça (id vazio = sem a peça).
func _preview(change: Dictionary) -> void:
	var shown: Dictionary = _base
	var candidate := _parts.duplicate()
	if not change.is_empty():
		if str(change.id).is_empty(): candidate.erase(change.slot)
		else: candidate[change.slot] = change.id
		shown = PERF.measure(_car_id,candidate)
	var changed := not change.is_empty()
	# Cosmetic slots keep the vehicle visible without irrelevant mechanical bars.
	_stats_panel.visible = _slot not in ["paint", "finish", "wheels", "neon"]
	if is_instance_valid(_showroom): _showroom.apply_parts(candidate if changed else _parts)
	for bar in _bars:
		var current := float(_base[bar.key])
		var next := float(shown[bar.key])
		bar.under.value = maxf(current,next)
		bar.over.value = minf(current,next)
		var tint := GOLD if not changed or is_equal_approx(current,next) else (GOOD if next > current else BAD)
		bar.under.add_theme_stylebox_override("fill",_box(tint,Color(0,0,0,0),0,4,0))
		bar.over.add_theme_stylebox_override("fill",_box(GOLD,Color(0,0,0,0),0,4,0))
		bar.value.text = "%d" % roundi(current) if not changed or is_equal_approx(current,next) else "%d → %d" % [roundi(current),roundi(next)]
		bar.value.add_theme_color_override("font_color",Color.WHITE if not changed or is_equal_approx(current,next) else tint)
	var letter := str(shown["class"])
	_badge_letter.text = letter
	_badge.add_theme_stylebox_override("panel",_box(CLASS_COLORS[letter],Color(0,0,0,0),0,10,4))
	_subtitle.text = "%s · %s / %d%s" % [mechanic_name,letter,roundi(float(shown.score)),"" if not changed else " · prévia"]
	_numbers.text = "0–100 km/h: %s\n400 m: %s\nFinal: %d km/h" % [_seconds(shown.zero_to_100),_seconds(shown.quarter),roundi(float(shown.top_kmh))]

func _seconds(value: Variant) -> String:
	return "—" if float(value) == INF else "%.2f s" % float(value)

## Os cartões são refeitos a cada mudança; o foco só vale se o botão ainda estiver na tela.
func _focus_later(button: Button) -> void:
	if button == null: return
	# A weak reference survives replacing cards before the deferred callback.
	var reference: WeakRef = weakref(button)
	var grab := func():
		var target: Button = reference.get_ref()
		if target != null and target.is_inside_tree() and target.is_visible_in_tree(): target.grab_focus()
	grab.call_deferred()

func _focus_first() -> void:
	for card in _cards.get_children():
		var button := card.get_meta("action_button") as Button
		if button != null and not button.disabled:
			_focus_later(button)
			return
