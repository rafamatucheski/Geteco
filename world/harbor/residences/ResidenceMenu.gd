class_name ResidenceMenu
extends CanvasLayer

signal purchase_confirmed(property_id: String)
signal outfit_selected(outfit_id: String)
signal loadout_selected(loadout: Dictionary)
signal time_selected(period: String)
signal closed()

const STYLE := preload("res://ui/GameStyle.gd")
const LOADOUT := preload("res://world/harbor/monaliza/PersonalLoadout.gd")

var prompt: Label
var shade: ColorRect
var panel: PanelContainer
var title_label: Label
var body: VBoxContainer
var actions: HBoxContainer
var is_open := false
var _mode := ""
var _pending_loadout: Dictionary = {}


func _ready() -> void:
	layer = 64
	_build_ui()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()


func show_prompt(text: String) -> void:
	prompt.text = text
	prompt.visible = not text.is_empty() and not is_open


func hide_prompt() -> void:
	prompt.hide()


func open_purchase(quote: Dictionary) -> void:
	_open(String(quote.get("target_name", "CASA")))
	_mode = "purchase"
	var current_id := String(quote.get("current_id", ""))
	var copy := "VALOR  $ %d" % int(quote.get("price", 0))
	if not current_id.is_empty():
		copy += "\nCRÉDITO DA CASA ATUAL  $ %d\nTOTAL DA TROCA  $ %d" % [int(quote.get("refund", 0)), int(quote.get("due", 0))]
	else:
		copy += "\nTOTAL  $ %d" % int(quote.get("due", 0))
	copy += "\nSALDO APÓS A COMPRA  $ %d" % int(quote.get("money_after", 0))
	_add_copy(copy, Color("d8e0dc"))
	if not current_id.is_empty():
		_add_copy("A residência atual será substituída. Checkpoint, Monaliza e o carro guardado serão transferidos.", Color("e6b875"))
	var confirm := _button("COMPRAR" if current_id.is_empty() else "CONFIRMAR TROCA", true)
	confirm.disabled = not bool(quote.get("affordable", false))
	var property_id := String(quote.get("target_id", ""))
	confirm.pressed.connect(func(): purchase_confirmed.emit(property_id); close())
	actions.add_child(confirm)
	_add_cancel_button()
	_grab_first_action()


func open_wardrobe(player: Node) -> void:
	_open("GUARDA-ROUPA")
	_mode = "wardrobe"
	_add_copy("Escolha uma roupa que Dante já possui.", Color("aebbc0"))
	var choice := OptionButton.new()
	choice.name = "OutfitChoice"
	choice.custom_minimum_size = Vector2(420, 44)
	var owned: Dictionary = player.get("owned_outfits")
	var current := String(player.get("current_outfit_id"))
	for data in OutfitCatalog.get_all_outfits():
		var id := String(data.id)
		if not owned.get(id, false) and id != "dante_classic":
			continue
		choice.add_item(_outfit_name(id))
		choice.set_item_metadata(choice.item_count - 1, id)
		if id == current:
			choice.select(choice.item_count - 1)
	body.add_child(choice)
	var equip := _button("VESTIR", true)
	equip.pressed.connect(func():
		if choice.item_count > 0:
			outfit_selected.emit(String(choice.get_item_metadata(choice.selected)))
		close()
	)
	actions.add_child(equip)
	_add_cancel_button()
	equip.grab_focus()


func open_arsenal(player: Node) -> void:
	_open("ARSENAL")
	_mode = "arsenal"
	_pending_loadout = LOADOUT.normalize(player.get("personal_loadout"), player.get("weapon_inventory"))
	_add_copy("O arsenal pertence ao Dante e acompanha qualquer residência.", Color("aebbc0"))
	var inventory: Dictionary = player.get("weapon_inventory")
	for slot in LOADOUT.GROUPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var label := Label.new()
		label.text = {"curta": "CURTA", "longa": "LONGA", "corpo": "CORPO A CORPO", "granada": "GRANADA"}[slot]
		label.custom_minimum_size = Vector2(145, 38)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var choice := OptionButton.new()
		choice.name = "Loadout_" + slot
		choice.custom_minimum_size = Vector2(275, 38)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.add_item("Vazio")
		choice.set_item_metadata(0, "")
		for weapon_id in LOADOUT.GROUPS[slot]:
			if not inventory.get(weapon_id, false):
				continue
			var weapon := WeaponCatalog.get_weapon(weapon_id)
			choice.add_item(String(weapon.get("label", weapon_id)))
			choice.set_item_metadata(choice.item_count - 1, weapon_id)
			if String(_pending_loadout.get(slot, "")) == weapon_id:
				choice.select(choice.item_count - 1)
		var slot_id := String(slot)
		choice.item_selected.connect(func(index: int):
			_pending_loadout[slot_id] = String(choice.get_item_metadata(index))
		)
		row.add_child(choice)
	var equip := _button("EQUIPAR", true)
	equip.pressed.connect(func(): loadout_selected.emit(_pending_loadout.duplicate(true)); close())
	actions.add_child(equip)
	_add_cancel_button()
	equip.grab_focus()


func open_time_selection() -> void:
	_open("DESCANSAR")
	_mode = "time"
	_add_copy("Escolha quando Dante acordará.", Color("aebbc0"))
	var day := _button("DIA", true)
	day.pressed.connect(func(): time_selected.emit("day"); close())
	actions.add_child(day)
	var night := _button("NOITE")
	night.pressed.connect(func(): time_selected.emit("night"); close())
	actions.add_child(night)
	_add_cancel_button()
	day.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_mode = ""
	shade.hide()
	panel.hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func _open(title: String) -> void:
	_clear_dynamic_content()
	is_open = true
	title_label.text = title
	shade.show()
	panel.show()
	prompt.hide()
	_fit_panel.call_deferred()


func _clear_dynamic_content() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()


func _add_copy(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	body.add_child(label)


func _add_cancel_button() -> void:
	var cancel := _button("CANCELAR")
	cancel.pressed.connect(close)
	actions.add_child(cancel)


func _grab_first_action() -> void:
	for child in actions.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return


func _button(text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(130, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("primary_action", primary)
	return button


func _build_ui() -> void:
	prompt = Label.new()
	prompt.name = "ResidencePrompt"
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -260
	prompt.offset_right = 260
	prompt.offset_top = -86
	prompt.offset_bottom = -46
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 17)
	prompt.add_theme_color_override("font_color", Color("f2e6ce"))
	prompt.add_theme_color_override("font_outline_color", Color("101820"))
	prompt.add_theme_constant_override("outline_size", 5)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	prompt.hide()

	shade = ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.035, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.hide()

	panel = PanelContainer.new()
	panel.name = "ResidencePanel"
	panel.set_meta("preserve_panel_style", true)
	panel.add_theme_stylebox_override("panel", STYLE.panel())
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)
	title_label = Label.new()
	title_label.theme_type_variation = &"EventTitle"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("e8b77d"))
	layout.add_child(title_label)
	var separator := HSeparator.new()
	layout.add_child(separator)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	layout.add_child(body)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	layout.add_child(actions)
	panel.hide()


func _fit_panel() -> void:
	if not is_instance_valid(panel):
		return
	STYLE.apply(panel, get_node("/root/SettingsManager").text_scale)
	var screen := get_viewport().get_visible_rect().size
	var desired_width := minf(590.0, screen.x - 48.0)
	# Autowrap precisa receber a largura antes de calcular a altura; fazer tudo
	# no mesmo passe pode interpretar cada palavra como uma coluna estreita e
	# empurrar o painel para fora de telas 720p.
	panel.custom_minimum_size = Vector2(desired_width, 0.0)
	panel.size = Vector2(desired_width, 1.0)
	_finish_panel_fit.call_deferred()


func _finish_panel_fit() -> void:
	if not is_instance_valid(panel):
		return
	var screen := get_viewport().get_visible_rect().size
	var desired_width := minf(590.0, screen.x - 48.0)
	var desired_height := minf(panel.get_combined_minimum_size().y, screen.y - 48.0)
	panel.size = Vector2(desired_width, desired_height)
	panel.position = (screen - panel.size) * 0.5


func _outfit_name(id: String) -> String:
	return String({
		"dante_classic": "Dante clássico", "dante_suit": "Terno", "dante_arctic": "Parka ártica",
		"dante_ski": "Conjunto de ski", "dante_trench": "Sobretudo de lã", "dante_cowboy": "Pistoleiro",
		"dante_madmax": "Sobrevivente", "dante_lumberjack": "Lenhador", "dante_ghillie": "Camuflado",
		"dante_hawaii": "Havaiana", "dante_badboy": "Regata"
	}.get(id, OutfitCatalog.get_outfit(id).get("name", id)))
