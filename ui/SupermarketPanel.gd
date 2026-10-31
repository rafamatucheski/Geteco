extends Control
## A focused checkout: direct purchase, persistent selection and inline feedback.
const STYLE := preload("res://ui/GameStyle.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const ICONS := preload("res://systems/inventory/InventoryIcons.gd")
const GREEN := Color("9bc7a5")
const CATEGORIES := {"Alimentos":["apple","water","juice","yogurt","bread","cereal_bar","sandwich"],"Cuidados":["first_aid"],"Colete":["armor"]}
var session
var shell: PanelContainer
var wallet: Label
var condition: Label
var status: Label
var grid: GridContainer
var categories: Array[Button] = []
var cards: Dictionary = {}
var selected_category := "Alimentos"
var close_button: Button
var heartbeat := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = STYLE.create_theme(16)
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.04,0.035,.20)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shell = PanelContainer.new()
	var skin := STYLE.panel()
	skin.bg_color = STYLE.INK
	skin.border_color = Color("5e8168")
	skin.border_width_top = 3
	skin.content_margin_left = 22
	skin.content_margin_right = 22
	shell.add_theme_stylebox_override("panel",skin)
	add_child(shell)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	shell.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := STYLE.label("Boa Praça",26,Color("f3ead4"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	wallet = STYLE.label("",23,STYLE.MONEY)
	wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(wallet)
	condition = STYLE.label("",14,STYLE.MUTED)
	column.add_child(condition)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",8)
	column.add_child(tabs)
	for category in CATEGORIES:
		var tab := Button.new()
		tab.text = category
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 34
		_style_button(tab)
		tab.pressed.connect(_select.bind(category))
		tabs.add_child(tab)
		categories.append(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",10)
	scroll.add_child(grid)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation",10)
	column.add_child(footer)
	status = STYLE.label("Escolha um item para comprar.",15,GREEN)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 38
	footer.add_child(status)
	var bottom := HBoxContainer.new()
	footer.add_child(bottom)
	var hint := STYLE.label("",14,STYLE.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	close_button = Button.new()
	close_button.text = "Voltar"
	close_button.custom_minimum_size = Vector2(100,34)
	_style_button(close_button)
	close_button.pressed.connect(session.close_menu)
	bottom.add_child(close_button)
	resized.connect(_layout)
	shell.minimum_size_changed.connect(_layout.call_deferred)
	_layout()
	_select("Alimentos")
	_layout.call_deferred()
	# O mouse começa sem cartão destacado arbitrário; o controle tem foco real.
	categories[0].grab_focus.call_deferred()

func _layout() -> void:
	if not is_instance_valid(shell): return
	var view := get_viewport_rect().size
	var width := minf(556,view.x-32)
	var height := minf(620,view.y-48)
	shell.position = Vector2(view.x-width-24 if view.x>700 else (view.x-width)*.5,(view.y-height)*.5)
	shell.size = Vector2(width,height)
	var columns := 2 if width>=450 else 1
	if grid.columns != columns:
		grid.columns = columns
		if not cards.is_empty(): _wire_focus()

func _select(category: String) -> void:
	selected_category = category
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	cards.clear()
	for tab in categories: tab.set_pressed_no_signal(tab.text==category)
	for id in CATEGORIES[category]: _card(id)
	refresh()
	_wire_focus()
	status.text = "Colete equipado ao comprar." if category=="Colete" else ""
	status.add_theme_color_override("font_color",STYLE.MUTED)

func _card(id: String) -> void:
	var spec := GRID.spec(id) if id!="armor" else {"label":"Colete balístico","heal":100,"icon":"armor"}
	var button := Button.new()
	button.name = "Buy_"+id
	button.tooltip_text = "Comprar "+str(spec.label)
	button.custom_minimum_size = Vector2(0,84)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	_style_button(button)
	grid.add_child(button)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation",10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	var icon := TextureRect.new()
	icon.texture = ICONS.get_icon(str(spec.icon))
	icon.custom_minimum_size = Vector2(44,56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation",2)
	content.add_child(text)
	var label := STYLE.label(str(spec.label),15)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font",STYLE.FONT)
	text.add_child(label)
	var benefit := STYLE.label("100 proteção" if id=="armor" else String(TranslationServer.translate("+%d vida"))%spec.heal,14,STYLE.ARMOR if id=="armor" else GREEN)
	benefit.add_theme_font_override("font",STYLE.FONT)
	text.add_child(benefit)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(row)
	var price := STYLE.label("R$ %d"%_price(id),16,STYLE.MONEY)
	row.add_child(price)
	var action := STYLE.label("Comprar",14,STYLE.ACCENT)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(action)
	var count := STYLE.label("",12,STYLE.MUTED)
	row.add_child(count)
	cards[id] = {"button":button,"count":count,"content":content,"action":action}
	button.pressed.connect(_buy.bind(id))
	button.mouse_entered.connect(_describe.bind(id))
	button.focus_entered.connect(_describe.bind(id))

func _style_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_ALL
	for state in ["normal","hover","pressed","disabled"]:
		var skin := STYLE.compact(false,3,Vector2(10,5))
		skin.bg_color = Color("26372d") if state in ["hover","pressed"] else Color("202e27")
		skin.border_color = GREEN if state in ["hover","pressed"] else Color("3a4b3f")
		skin.shadow_size = 0
		button.add_theme_stylebox_override(state,skin)
	var focus := STYLE.compact(false,3)
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = GREEN
	focus.set_border_width_all(1)
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_color_override("font_pressed_color",GREEN)

func _price(id: String) -> int:
	return 500 if id=="armor" else int(ECONOMY.SUPPLIES[id].price)

func _reason(id: String) -> String:
	if id=="armor" and session.world.gameplay.armor>=100: return "Proteção completa"
	if session.state.economy.balance<_price(id): return "Dinheiro insuficiente"
	if id!="armor":
		var candidate: Dictionary = session.state.economy.grid_snapshot()
		if GRID.add_carried(candidate,id,1)!=0: return "Inventário cheio"
	return ""

func refresh() -> void:
	wallet.text = "R$ "+STYLE.amount(session.state.economy.balance)
	condition.text = String(TranslationServer.translate("Vida  %d / 100     ·     Proteção  %d / 100"))%[session.world.gameplay.health,session.world.gameplay.armor]
	for id in cards:
		var row: Dictionary = cards[id]
		var reason := _reason(id)
		# Mantém cartões bloqueados focáveis para quem usa teclado/controle ouvir/ler o porquê.
		row.content.modulate.a = 1.0 if reason.is_empty() else .78
		row.action.text = ("Equipar" if id == "armor" else "Comprar 1") if reason.is_empty() else reason
		row.action.add_theme_color_override("font_color",STYLE.ACCENT if reason.is_empty() else STYLE.MUTED)
		row.count.text = "Equipado" if id=="armor" and session.world.gameplay.armor>=100 else String(TranslationServer.translate("%d un."))%int(session.state.economy.inventory.get(id,0)) if id!="armor" else ""
		row.button.tooltip_text = reason if not reason.is_empty() else "Comprar "+str(GRID.spec(id).label if id!="armor" else "colete")

func _describe(id: String) -> void:
	var reason := _reason(id)
	status.text = reason if not reason.is_empty() else "Equipar colete · R$ 500" if id=="armor" else "Comprar 1 · guardar no inventário"
	status.add_theme_color_override("font_color",STYLE.MUTED if reason.is_empty() else STYLE.MONEY)

func _buy(id: String) -> void:
	var reason := _reason(id)
	if not reason.is_empty(): feedback(reason,false); return
	load("res://runtime/SupermarketShop.gd").buy(session,id)

func feedback(message: String, ok: bool) -> void:
	refresh()
	status.text = "✓ "+message if ok else message
	status.add_theme_color_override("font_color",GREEN if ok else STYLE.MONEY)

func _wire_focus() -> void:
	var buttons: Array[Control] = []
	for row in cards.values(): buttons.append(row.button)
	for i in categories.size():
		categories[i].focus_neighbor_left = categories[i].get_path_to(categories[(i+categories.size()-1)%categories.size()])
		categories[i].focus_neighbor_right = categories[i].get_path_to(categories[(i+1)%categories.size()])
		categories[i].focus_neighbor_bottom = categories[i].get_path_to(buttons[0])
	for i in buttons.size():
		var button: Control = buttons[i]
		button.focus_neighbor_top = button.get_path_to(buttons[i-grid.columns] if i>=grid.columns else categories[0])
		button.focus_neighbor_bottom = button.get_path_to(buttons[i+grid.columns] if i+grid.columns<buttons.size() else close_button)
		button.focus_neighbor_left = button.get_path_to(buttons[i-1] if i%grid.columns>0 else button)
		button.focus_neighbor_right = button.get_path_to(buttons[i+1] if i%grid.columns==0 and i+1<buttons.size() else button)
		button.focus_next = button.get_path_to(buttons[i+1] if i+1<buttons.size() else close_button)
	close_button.focus_neighbor_top = close_button.get_path_to(buttons[-1])
	close_button.focus_next = close_button.get_path_to(categories[0])

func _process(delta: float) -> void:
	heartbeat += delta
	if heartbeat<.15: return
	heartbeat = 0
	if not session.modal or session.panel.visible or session.state.place_id!="harbor_supermarket" or not is_instance_valid(session.room): queue_free(); return
	if session.room.threatened(): session.close_menu()
