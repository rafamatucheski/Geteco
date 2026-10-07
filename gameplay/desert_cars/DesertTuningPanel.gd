extends CanvasLayer
## The panel emits intent only; session commits money + parts atomically, then
## calls show_vehicle with the authoritative state. No second wallet lives here.
## Passar o mouse (ou o foco) numa peça mostra nas barras como o carro ficaria.
signal purchase_requested(part_id: String)
signal remove_requested(slot: String)
signal closed
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
var _car_id := "desert_faisca"
var _parts: Dictionary = {}
var _owned: Array = []
var _wins := 0
var _money := 0
var _slot := ""
var _pending := ""
var _base: Dictionary = {}

func _ready() -> void:
	layer = 36
	_dim = ColorRect.new()
	_dim.color = Color(.02,.03,.04,.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	# Carro à direita, lista à esquerda e desempenho embaixo, como nas oficinas de GTA.
	_showroom = SHOWROOM.new()
	_showroom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showroom.offset_left = 500.0
	_showroom.offset_bottom = -214.0
	add_child(_showroom)
	_root = PanelContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_root.offset_left = 24.0
	_root.offset_right = 494.0
	_root.offset_top = 24.0
	_root.offset_bottom = -24.0
	_root.add_theme_stylebox_override("panel",_box(Color("14181c"),GOLD,2,10,18))
	add_child(_root)
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
	var stats := _build_stats()
	stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stats.offset_left = 518.0
	stats.offset_right = -24.0
	stats.offset_top = -198.0
	stats.offset_bottom = -24.0
	add_child(stats)
	visibility_changed.connect(func(): if not visible: _showroom.hide_showroom())
	hide()

func _box(fill: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
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
	_badge.custom_minimum_size = Vector2(54,54)
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
	_title.add_theme_font_size_override("font_size",22)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color",MUTED)
	names.add_child(_subtitle)
	header.add_child(names)
	var close := Button.new()
	close.text = "Voltar [Esc]"
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
	row.add_theme_constant_override("separation",26)
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
	_numbers.custom_minimum_size = Vector2(210,0)
	_numbers.add_theme_color_override("font_color",MUTED)
	_numbers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_numbers)
	return panel

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
	_title.text = "Digo · %s" % label
	_wallet.text = "R$ %s   ·   %d de %d vitórias" % [_money_text(_money),_wins,RACE_WINS.maximum()]
	_message.text = ""
	_rebuild_tabs()
	_rebuild_cards()
	_preview({})
	show()
	var shown_model := str(appearance.get("archetype",car_id))
	_showroom.show_car(shown_model,appearance.get("paint",FLEET.default_paint(shown_model,Color.WHITE)),_parts)
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
		if str(card.get_meta("part_id","")) == id: return card.get_child(0).get_child(1).get_child(1) as Button
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = str(part.label)+("   ✓ INSTALADA" if installed else "")
	name_label.add_theme_font_size_override("font_size",17)
	name_label.add_theme_color_override("font_color",GOOD if installed else (MUTED if locked else Color.WHITE))
	if part.has("neon"):
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation",10)
		var swatch := PanelContainer.new()
		swatch.custom_minimum_size = Vector2(20,20)
		swatch.add_theme_stylebox_override("panel",_box(Color(str(part.neon)),Color(1,1,1,.35),1,10,0))
		title_row.add_child(swatch)
		title_row.add_child(name_label)
		info.add_child(title_row)
	else:
		info.add_child(name_label)
	var effect := Label.new()
	effect.text = str(part.effect)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_color_override("font_color",MUTED)
	info.add_child(effect)
	row.add_child(info)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(150,0)
	var price := Label.new()
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if locked: price.text = "Vença %d provas (você: %d)" % [int(part.wins),_wins]
	elif id in _owned: price.text = "Já é sua"
	else: price.text = "R$ %s" % _money_text(cost)
	price.add_theme_color_override("font_color",MUTED if locked or id in _owned else GOLD)
	side.add_child(price)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0,34)
	if installed:
		button.text = "Remover"
		button.pressed.connect(func(): remove_requested.emit(_slot))
	elif locked:
		button.text = "Bloqueada"
		button.disabled = true
	elif cost > _money:
		button.text = "Falta R$ %s" % _money_text(cost-_money)
		button.disabled = true
	elif cost == 0:
		button.text = "Instalar"
		button.pressed.connect(func(): purchase_requested.emit(id))
	else:
		button.text = "Comprar" if _pending != id else "Confirmar R$ %s" % _money_text(cost)
		button.pressed.connect(_buy_pressed.bind(id))
	side.add_child(button)
	row.add_child(side)
	var preview := {} if installed else {"slot":_slot,"id":id}
	if installed: preview = {"slot":_slot,"id":""}
	panel.mouse_entered.connect(_preview.bind(preview))
	button.mouse_entered.connect(_preview.bind(preview))
	button.focus_entered.connect(_preview.bind(preview))
	panel.mouse_exited.connect(_preview.bind({}))
	return panel

func _buy_pressed(id: String) -> void:
	if _pending == id:
		_pending = ""
		purchase_requested.emit(id)
		return
	_pending = id
	_rebuild_cards()
	_message.text = "Clique de novo para confirmar a compra."
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
	_subtitle.text = "Classe %s · %d pontos%s" % [letter,roundi(float(shown.score)),"" if not changed else "  (prévia)"]
	_numbers.text = "0–100 km/h: %s\n400 m: %s\nVelocidade de rua: %d km/h" % [_seconds(shown.zero_to_100),_seconds(shown.quarter),roundi(float(shown.top_kmh))]

func _seconds(value: Variant) -> String:
	return "—" if float(value) == INF else "%.2f s" % float(value)

## Os cartões são refeitos a cada mudança; o foco só vale se o botão ainda estiver na tela.
func _focus_later(button: Button) -> void:
	if button == null: return
	var grab := func():
		if is_instance_valid(button) and button.is_inside_tree() and button.is_visible_in_tree(): button.grab_focus()
	grab.call_deferred()

func _focus_first() -> void:
	for card in _cards.get_children():
		var button := card.get_child(0).get_child(1).get_child(1) as Button
		if button != null and not button.disabled:
			_focus_later(button)
			return
