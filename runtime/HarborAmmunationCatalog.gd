extends Control
## Catálogo produtivo de HarborAmmunationInterior.gd (V1), adaptado somente
## na fronteira de estado: GameState/Economy/Gameplay substituem o Player 2D.

signal close_requested

const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const WORKBENCH := preload("res://runtime/HarborWeaponWorkbench.gd")
const FLASHLIGHT_ICON := preload("res://ui/icons/lucide/flashlight.svg")
const UTILITY_GRID := preload("res://systems/inventory/GridInventory.gd")
const BELT_PRICE := preload("res://gameplay/BeltFlashlight.gd").PRICE

var session
var panel: PanelContainer
var preview: SubViewport
var gun: Node3D
var caption: Label
var feedback: Label
var buy: Button
var ammo_button: Button
var belt_flashlight_button: Button
var lockpick_button: Button
var customize_button: Button
var workbench_button: Button
var workbench: PanelContainer
var saber_panel: PanelContainer
var category_buttons: Array[Button] = []
var selection := 0
var stock := ["pistol", "magnum", "pistol_suppressed", "shotgun", "sawed_off", "shotgun_auto", "smg", "smg_compact", "smg_tactical", "ak47", "m4a1", "hunting_rifle", "knife", "knuckles", "bat", "axe", "grenade", "rpg", "flamethrower", "armor"]
var active := false
const SHOP_FOCUS := preload("res://ui/ShopFocus.gd")
const MENU_AUDIO := preload("res://ui/MenuAudio.gd")
var control_hint: Label
var wallet: Label
var item_list: VBoxContainer
var comparison: VBoxContainer
var list_category := -1
var weapon_body: HBoxContainer
var utilities_body: VBoxContainer
var utilities_active := false
var utility_weapon_id := "pistol"
var utility_weapon_selector: OptionButton
var lockpick_status: Label
var belt_flashlight_status: Label
var tactical_flashlight_status: Label
const ICONS := preload("res://systems/inventory/InventoryIcons.gd")

func configure(owner_session) -> void:
	session = owner_session
	name = "HarborAmmunationCatalog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_build_catalog()

func _build_catalog() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, .65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28
	panel.offset_right = -28
	panel.offset_top = 22
	panel.offset_bottom = -22
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171a1f")
	style.border_color = ART.RED
	style.border_width_top = 5
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_font_override("font", preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf"))
	panel.add_theme_font_size_override("font_size", 16)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var brand := Label.new()
	brand.text = "⊕  AMMU-NATION"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_font_size_override("font_size", 28)
	brand.add_theme_font_override("font", preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"))
	brand.add_theme_color_override("font_color", Color("f1eee7"))
	header.add_child(brand)
	wallet = Label.new()
	wallet.add_theme_font_size_override("font_size", 20)
	wallet.add_theme_color_override("font_color", Color("e2ddd3"))
	header.add_child(wallet)
	var close_button := Button.new()
	close_button.text = "Voltar · Esc"
	close_button.custom_minimum_size.y = 34
	close_button.pressed.connect(func(): close_requested.emit())
	style_button(close_button)
	header.add_child(close_button)
	var categories := HBoxContainer.new()
	box.add_child(categories)
	for index in 6:
		var button := Button.new()
		button.text = ["Armas curtas", "Armas longas", "Corpo a corpo", "Explosivos", "Proteção", "Utilitários"][index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34
		button.pressed.connect(_select_category.bind(index))
		button.toggle_mode = true
		style_button(button)
		categories.add_child(button)
		category_buttons.append(button)
	var body := HBoxContainer.new()
	weapon_body = body
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 290
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 2)
	scroll.add_child(item_list)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 10)
	body.add_child(center)
	caption = Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_font_override("font", preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"))
	caption.add_theme_color_override("font_color", Color("f1eee7"))
	center.add_child(caption)
	# Preserva o modelo 3D iluminado existente; sem viewports extras para ícones de lista.
	var stage := PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", stage_style())
	center.add_child(stage)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(320, 170)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	stage.add_child(container)
	preview = SubViewport.new()
	preview.size = Vector2i(720, 140)
	preview.own_world_3d = true
	preview.transparent_bg = true
	# Segue o MSAA do jogo: 4x fixo recompilava os materiais da vitrine no primeiro desenho.
	preview.msaa_3d = preload("res://runtime/RenderPolicy.gd").subviewport_msaa(Viewport.MSAA_4X)
	container.add_child(preview)
	gun = Node3D.new()
	preview.add_child(gun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.25
	camera.look_at_from_position(Vector3(1, .55, .7), Vector3.ZERO)
	preview.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d6e0dc")
	environment.environment.ambient_light_energy = .9
	preview.add_child(environment)
	for direction in [Vector3(-40, -40, 0), Vector3(25, 140, 0)]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = direction
		lamp.light_energy = 1.5
		preview.add_child(lamp)
	comparison = VBoxContainer.new()
	comparison.custom_minimum_size.x = 230
	comparison.add_theme_constant_override("separation", 10)
	body.add_child(comparison)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y = 26
	feedback.add_theme_color_override("font_color", Color("e4ece8"))
	box.add_child(feedback)
	buy = Button.new()
	buy.custom_minimum_size = Vector2(230, 36)
	buy.add_theme_font_size_override("font_size", 19)
	buy.pressed.connect(purchase)
	style_button(buy)
	WORKBENCH.primary_button(buy)
	buy.add_theme_font_size_override("font_size", 19)
	var weapon_actions := HBoxContainer.new()
	weapon_actions.add_theme_constant_override("separation", 8)
	center.add_child(weapon_actions)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	weapon_actions.add_child(buy)
	workbench_button = Button.new()
	workbench_button.custom_minimum_size = Vector2(130, 36)
	workbench_button.text = "EDITAR ARMA"
	workbench_button.pressed.connect(open_workbench)
	style_button(workbench_button)
	weapon_actions.add_child(workbench_button)
	var supplies := HBoxContainer.new()
	supplies.add_theme_constant_override("separation", 8)
	box.add_child(supplies)
	ammo_button = Button.new()
	ammo_button.pressed.connect(purchase_ammo)
	lockpick_button = Button.new()
	lockpick_button.pressed.connect(purchase_lockpick)
	belt_flashlight_button = Button.new()
	belt_flashlight_button.pressed.connect(purchase_belt_flashlight)
	for button in [ammo_button, lockpick_button, belt_flashlight_button]:
		button.custom_minimum_size.y = 34
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		style_button(button)
		supplies.add_child(button)
	customize_button = Button.new()
	customize_button.custom_minimum_size.y = 34
	customize_button.pressed.connect(customize_flashlight)
	style_button(customize_button)
	box.add_child(customize_button)
	control_hint = Label.new()
	control_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control_hint.add_theme_font_size_override("font_size", 14)
	control_hint.add_theme_color_override("font_color", ART.CREAM)
	box.add_child(control_hint)
	_build_utilities(box)
	MENU_AUDIO.hook_buttons(panel, self)
	workbench = WORKBENCH.new()
	workbench.configure(session)
	add_child(workbench)
	workbench.closed.connect(func():
		panel.show()
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		if active:
			change_selection(0)
			workbench_button.grab_focus())
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _build_utilities(box: VBoxContainer) -> void:
	utilities_body = VBoxContainer.new()
	utilities_body.name = "Utilities"
	utilities_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	utilities_body.add_theme_constant_override("separation",12)
	box.add_child(utilities_body)
	box.move_child(utilities_body,3)
	var flashlight := FLASHLIGHT_ICON.get_image()
	if flashlight.is_compressed(): flashlight.decompress()
	for y in flashlight.get_height():
		for x in flashlight.get_width():
			flashlight.set_pixel(x,y,Color(Color("d9ddd7"),flashlight.get_pixel(x,y).a))
	var flashlight_texture := ImageTexture.create_from_image(flashlight)
	var lockpick_text := _utility_card("Gazua",ICONS.get_icon("lockpick"),lockpick_button)
	lockpick_status = _utility_label("")
	lockpick_text.add_child(lockpick_status)
	var belt_text := _utility_card("Lanterna de cinto",flashlight_texture,belt_flashlight_button)
	belt_flashlight_status = _utility_label("")
	belt_text.add_child(belt_flashlight_status)
	var tactical_text := _utility_card("Lanterna tática",flashlight_texture,customize_button)
	utility_weapon_selector = OptionButton.new()
	utility_weapon_selector.name = "UtilityWeapon"
	utility_weapon_selector.custom_minimum_size = Vector2(240,34)
	utility_weapon_selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	style_button(utility_weapon_selector)
	utility_weapon_selector.item_selected.connect(_utility_weapon_changed)
	tactical_text.add_child(utility_weapon_selector)
	tactical_flashlight_status = _utility_label("")
	tactical_text.add_child(tactical_flashlight_status)
	utilities_body.hide()

func _utility_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font",preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf"))
	label.add_theme_font_size_override("font_size",15)
	label.add_theme_color_override("font_color",Color("b8bec4"))
	return label

func _utility_card(title: String, icon: Texture2D, action: Button) -> VBoxContainer:
	var card := PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("20242a")
	skin.border_color = Color("343a42")
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(2)
	skin.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel",skin)
	utilities_body.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	card.add_child(row)
	var image := TextureRect.new()
	image.texture = icon
	image.custom_minimum_size = Vector2(42,42)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(image)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation",5)
	row.add_child(text)
	var label := _utility_label(title)
	label.add_theme_font_size_override("font_size",18)
	label.add_theme_color_override("font_color",Color("f1eee7"))
	text.add_child(label)
	action.reparent(row)
	action.custom_minimum_size = Vector2(230,34)
	action.size_flags_horizontal = Control.SIZE_SHRINK_END
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return text

func _select_category(index: int) -> void:
	utilities_active = index == 5
	if utilities_active:
		if stock[selection] in CUSTOM.COMPATIBLE: utility_weapon_id = stock[selection]
		refresh()
	else:
		selection = stock.find(["pistol", "shotgun", "knife", "grenade", "armor"][index])
		change_selection(0)

func _refresh_utility_weapons() -> void:
	var selected := -1
	utility_weapon_selector.clear()
	for id in stock:
		if id not in CUSTOM.COMPATIBLE: continue
		var item: Dictionary = session.world.gameplay.weapon_data(id)
		var index := utility_weapon_selector.item_count
		utility_weapon_selector.add_item(str(item.get("short_label",item.get("label",id))))
		utility_weapon_selector.set_item_metadata(index,id)
		if id == utility_weapon_id: selected = index
	if selected >= 0: utility_weapon_selector.select(selected)

func _utility_weapon_changed(index: int) -> void:
	utility_weapon_id = str(utility_weapon_selector.get_item_metadata(index))
	refresh()

func open_catalog() -> void:
	if session.state.economy.is_weapon_unlocked("katana") and "katana" not in stock: stock.insert(stock.find("axe")+1,"katana")
	active = true
	utilities_active = false
	show()
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	change_selection(0)
	SHOP_FOCUS.rebuild(panel)
	MENU_AUDIO.play_click(self)

func dismiss() -> void:
	active = false
	if is_instance_valid(saber_panel): saber_panel.queue_free()
	panel.show()
	if is_instance_valid(workbench): workbench.close(false)
	if is_instance_valid(preview): preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if is_instance_valid(saber_panel):
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
			saber_panel.closed.emit()
			saber_panel.queue_free()
		return true
	if is_instance_valid(workbench) and workbench.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
			workbench.close()
			return true
		return false
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		MENU_AUDIO.play_click(self)
		close_requested.emit()
		return true
	if event.is_action_pressed("weapon_previous"):
		change_selection(-1)
		MENU_AUDIO.play_hover(self)
		return true
	if event.is_action_pressed("weapon_next"):
		change_selection(1)
		MENU_AUDIO.play_hover(self)
		return true
	return false

func change_selection(step: int) -> void:
	if utilities_active:
		if step != 0 and utility_weapon_selector.item_count > 0:
			_utility_weapon_changed(posmod(utility_weapon_selector.selected + step, utility_weapon_selector.item_count))
		else: refresh()
		return
	selection = posmod(selection + step, stock.size())
	for child in gun.get_children(): child.free()
	var model := Node3D.new()
	gun.add_child(model)
	if stock[selection] == "katana":
		var honor: Dictionary = preload("res://runtime/TakeshiHonor.gd").data(session.state.world_state)
		model.add_child(preload("res://gameplay/KatanaModel.gd").create(honor.saber_unlocked,Color.html(honor.saber_color)))
	else: ART.item(model, stock[selection])
	if stock[selection] in CUSTOM.CUSTOMIZABLE:
		CUSTOM.fit(model, stock[selection], session.world.gameplay.customization, model.get_meta("weapon_muzzle", Vector3.ZERO))
	var bounds := _bounds(model, Transform3D.IDENTITY)
	model.position = -bounds.get_center()
	gun.rotation = Vector3(0, -.45, 0)
	var target_size := .95 if stock[selection] in ["armor", "grenade"] else 1.65
	gun.scale = Vector3.ONE * (target_size / maxf(bounds.size.length(), .1))
	refresh()

func _bounds(node: Node3D, transform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	if node is MeshInstance3D:
		result = transform * node.get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child, transform * child.transform)
			if child_bounds.size == Vector3.ZERO: continue
			result = child_bounds if first else result.merge(child_bounds)
			first = false
	return result

func data() -> Dictionary:
	if stock[selection] == "armor": return {"label":"COLETE BALÍSTICO", "price":500}
	return session.world.gameplay.weapon_data(stock[selection])

## Linha de preço/posse do título. Vídeo 24/09 (item 33): a pistola possuída
## mostrava "R$0" e a MP5 possuída "R$1200", misturando tabela com posse. Arma já
## possuída diz isso; preço zero é o item inicial do catálogo, não promoção.
func price_status(item: Dictionary, owned: bool, armor: bool) -> String:
	var price := int(item.get("price", 0))
	if owned: return "PROTEÇÃO COMPLETA" if armor else "JÁ POSSUI"
	return "ITEM INICIAL • R$0" if price == 0 else "R$%d" % price

func refresh(notice := "") -> void:
	var count := int(session.state.economy.inventory.get("lockpick",0))
	var lockpick_price := int(session.state.economy.SUPPLIES.lockpick.price)
	lockpick_button.text = String(TranslationServer.translate("Comprar · R$ %d")) % lockpick_price
	lockpick_status.text = String(TranslationServer.translate("No inventário: %d")) % count
	var full := count >= 999
	if session.state.economy.grid_enabled():
		var candidate: Dictionary = session.state.economy.grid_snapshot()
		full = full or UTILITY_GRID.add_carried(candidate,"lockpick",1) != 0
	lockpick_button.disabled = full or session.state.economy.balance < lockpick_price
	if full: lockpick_status.text = "Inventário cheio"
	var id: String = stock[selection]
	var item := data()
	var armor := id == "armor"
	var owned: bool = session.world.gameplay.armor >= 100 if armor else session.state.economy.owns_weapon(id)
	var unlocked: bool = armor or session.state.economy.is_weapon_unlocked(id)
	var price := int(item.get("price", 0))
	var short: bool = session.state.economy.balance < price
	caption.text = "%s   /   %s" % [item.get("label", id), price_status(item, owned, armor)]
	buy.disabled = owned or not unlocked or short
	if owned: buy.text = "PROTEÇÃO COMPLETA" if armor else "JÁ POSSUI"
	elif not unlocked: buy.text = "BLOQUEADA"
	elif short: buy.text = String(TranslationServer.translate("SALDO INSUFICIENTE • R$%d")) % price
	else: buy.text = String(TranslationServer.translate("COMPRAR • R$%d")) % price
	var hint: String = item.get("discovery_hint", "") if not unlocked else ""
	if unlocked and not owned and short: hint = String(TranslationServer.translate("Faltam R$%d para esta compra.")) % (price - session.state.economy.balance)
	feedback.text = "" if utilities_active else hint
	wallet.text = String(TranslationServer.translate("SALDO  R$%d")) % session.state.economy.balance
	if not notice.is_empty(): feedback.text = notice + String(TranslationServer.translate("\nSaldo: R$%d")) % session.state.economy.balance
	var rounds := maxi(0, int(item.get("magazine_size", 0))) * 2
	var ammo_cost := ammo_price(rounds)
	ammo_button.visible = rounds > 0 and not armor
	ammo_button.text = String(TranslationServer.translate("REPOR +%d %s • R$%d")) % [rounds, "GRANADAS" if id == "grenade" else "MUNIÇÕES", ammo_cost]
	ammo_button.disabled = not owned or session.state.economy.balance < ammo_cost
	var belt = session.world.gameplay.belt_flashlight
	belt_flashlight_button.text = "Já possui" if belt.owned else String(TranslationServer.translate("Comprar e equipar · R$ %d")) % BELT_PRICE
	belt_flashlight_status.text = "Equipada" if belt.owned else "Não adquirida"
	belt_flashlight_button.disabled = belt.owned or session.state.economy.balance < BELT_PRICE
	var attachment_id := utility_weapon_id if utilities_active else id
	var compatible := attachment_id in CUSTOM.COMPATIBLE
	var attachment_owned: bool = session.state.economy.owns_weapon(attachment_id)
	var customization: Dictionary = session.world.gameplay.customization
	customize_button.visible = utilities_active and compatible
	workbench_button.visible = not utilities_active and (id in CUSTOM.CUSTOMIZABLE or id == "katana")
	workbench_button.text = "SABRE DE LUZ · COR" if id == "katana" else "EDITAR ARMA"
	workbench_button.disabled = not owned
	customize_button.disabled = not attachment_owned or (not CUSTOM.owns(customization, attachment_id, "flashlight") and session.state.economy.balance < CUSTOM.PRICE)
	customize_button.text = "Remover" if CUSTOM.installed(customization, attachment_id) else ("Instalar" if CUSTOM.owns(customization, attachment_id, "flashlight") else String(TranslationServer.translate("Comprar e instalar · R$ %d")) % CUSTOM.PRICE)
	tactical_flashlight_status.text = "Arma não adquirida" if not attachment_owned else ("Instalada" if CUSTOM.installed(customization, attachment_id) else ("Comprada" if CUSTOM.owns(customization, attachment_id, "flashlight") else "Não instalada"))
	var category := _category(id)
	if utilities_active: category = 5
	weapon_body.visible = not utilities_active
	utilities_body.visible = utilities_active
	buy.visible = not utilities_active
	ammo_button.visible = ammo_button.visible and not utilities_active
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and not utilities_active and panel.visible else SubViewport.UPDATE_DISABLED
	_refresh_utility_weapons()
	# Aba ativa por estado pressionado, não por modulate: o modulate cinza
	# escurecia texto e fundo das abas inativas até ficarem ilegíveis.
	for i in category_buttons.size(): category_buttons[i].set_pressed_no_signal(i == category)
	if not utilities_active:
		_refresh_list(category)
		_refresh_comparison(id)
	var controls = get_node_or_null("/root/GameInput")
	if controls != null:
		control_hint.text = "%s / %s  Item    ·    ↑ ↓ ← →  Navegar    ·    %s  Confirmar    ·    %s  Voltar" % [controls.prompt("weapon_previous"), controls.prompt("weapon_next"), controls.prompt("ui_accept"), controls.prompt("ui_cancel")]
	if active and panel.visible: SHOP_FOCUS.rebuild.call_deferred(panel)

func _category(id: String) -> int:
	if id == "armor": return 4
	if id in ["grenade", "rpg"]: return 3
	if id in ["knife", "knuckles", "bat", "axe", "katana"]: return 2
	return 0 if id in ["pistol", "magnum", "pistol_suppressed"] else 1

func _select_item(index: int) -> void:
	utilities_active = false
	selection = index
	change_selection(0)

func _refresh_list(category: int) -> void:
	# Reconstrói só quando a categoria/catálogo muda. Seleção e compras mantêm o foco.
	if category != list_category or int(item_list.get_meta("stock_count", -1)) != stock.size():
		for child in item_list.get_children(): child.free()
		list_category = category
		item_list.set_meta("stock_count", stock.size())
		for index in stock.size():
			var id: String = stock[index]
			if _category(id) != category: continue
			var button := Button.new()
			button.custom_minimum_size = Vector2(270, 54)
			button.toggle_mode = true
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.icon = ICONS.get_icon(id)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 54)
			button.add_theme_constant_override("h_separation", 12)
			button.add_theme_font_size_override("font_size", 17)
			button.set_meta("stock_index", index)
			style_button(button)
			button.pressed.connect(_select_item.bind(index))
			item_list.add_child(button)
	for button in item_list.get_children():
		var index: int = button.get_meta("stock_index")
		var id: String = stock[index]
		var item: Dictionary = {"label":"COLETE BALÍSTICO", "price":500} if id == "armor" else session.world.gameplay.weapon_data(id)
		var owned: bool = session.world.gameplay.armor >= 100 if id == "armor" else session.state.economy.owns_weapon(id)
		var unlocked: bool = id == "armor" or session.state.economy.is_weapon_unlocked(id)
		var state_text := "JÁ POSSUI" if owned else ("R$%d" % int(item.get("price", 0)) if unlocked else "BLOQUEADA")
		button.text = "%s\n%s" % [item.get("short_label", item.get("label", id)), state_text]
		button.set_pressed_no_signal(index == selection)

func _refresh_comparison(id: String) -> void:
	for child in comparison.get_children(): child.free()
	var heading := Label.new()
	heading.text = "PROTEÇÃO" if id == "armor" else "COMPARAR COM EQUIPADA"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_font_override("font", preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"))
	heading.add_theme_color_override("font_color", Color("f1eee7"))
	comparison.add_child(heading)
	if id == "armor":
		var armor_label := Label.new()
		armor_label.text = "%d / 100 → 100 / 100" % session.world.gameplay.armor
		comparison.add_child(armor_label)
		return
	var selected_data: Dictionary = session.world.gameplay.weapon_data(id)
	if not str(selected_data.get("role", "")).is_empty():
		var role := Label.new()
		role.text = str(selected_data.role)
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role.add_theme_color_override("font_color", Color("b8bec4"))
		comparison.add_child(role)
	var equipped_id: String = session.state.equipped_weapon
	var equipped: Dictionary = session.world.gameplay.weapon_data(equipped_id)
	var equipped_label := Label.new()
	equipped_label.text = String(TranslationServer.translate("%s · EQUIPADA")) % str(equipped.get("short_label", equipped.get("label", equipped_id)))
	equipped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipped_label.add_theme_color_override("font_color", Color("b8bec4"))
	comparison.add_child(equipped_label)
	var columns := Label.new()
	columns.text = "PRÉVIA  ←  EQUIPADA"
	columns.add_theme_font_size_override("font_size", 14)
	comparison.add_child(columns)
	# Valores vêm dos dados de combate com os acessórios instalados aplicados.
	var current_rows := CUSTOM.stats(equipped_id, session.world.gameplay.customization)
	var selected_rows := CUSTOM.stats(id, session.world.gameplay.customization)
	for row in selected_rows:
		if row[0] not in ["Dano", "Capacidade", "Tiros/s", "Golpes/s", "Alcance"]: continue
		var old_text := "—"
		for previous in current_rows:
			if previous[0] == row[0]: old_text = str(previous[2]); break
		var stat := Label.new()
		stat.text = "%s\n%s  ←  %s" % [row[0], row[2], old_text]
		stat.add_theme_font_size_override("font_size", 16)
		stat.add_theme_color_override("font_color", Color("dddcd7"))
		comparison.add_child(stat)

func style_button(button: Button) -> void:
	WORKBENCH.style_button(button)

func stage_style() -> StyleBoxFlat:
	return WORKBENCH.stage_style()

func ammo_price(rounds: int) -> int:
	return maxi(40, rounds * (60 if stock[selection] in ["grenade", "rpg"] else 2))

func purchase() -> void:
	if not active or utilities_active or buy.disabled: return
	var id: String = stock[selection]
	var message := ""
	if id == "armor":
		if not session.state.economy.spend(500, "body_armor:" + session._transaction()): message = "DINHEIRO INSUFICIENTE"
		else:
			session.world.gameplay.armor = 100
			message = "COLETE EQUIPADO"
	else:
		var result: Dictionary = session.state.economy.purchase("weapon", id, session._transaction())
		if result.ok:
			message = "COMPRA REALIZADA" if session.state.equip_weapon(id) else "COMPRA REALIZADA · ARMA GUARDADA NO PORTA-MALAS"
		else: message = _reason(result.reason)
	if message.begins_with("COMPRA REALIZADA") or message == "COLETE EQUIPADO": session.save_game()
	refresh(message)

func purchase_ammo() -> void:
	if not active or ammo_button.disabled or not ammo_button.visible: return
	var id: String = stock[selection]
	var rounds := int(data().get("magazine_size", 0)) * 2
	var price := ammo_price(rounds)
	var economy = session.state.economy
	var ammo: Dictionary = economy.get_ammo(id)
	if int(ammo.reserve) > economy.MAX_AMMO - rounds:
		refresh("RESERVA DE MUNIÇÃO CHEIA")
		return
	var before: Dictionary = economy.snapshot()
	if not economy.spend(price, "ammunition:" + session._transaction()):
		refresh("DINHEIRO INSUFICIENTE")
		return
	if not economy.add_ammo(id, rounds):
		economy.restore_snapshot(before)
		refresh("COMPRA CANCELADA")
		return
	session.save_game()
	refresh("MUNIÇÃO COMPRADA")

func purchase_lockpick() -> void:
	if not active: return
	var result: Dictionary = session.state.economy.purchase("supply","lockpick",session._transaction())
	if result.ok: session.save_game()
	refresh("LOCKPICK COMPRADO" if result.ok else _reason(result.reason))

func customize_flashlight() -> void:
	if not active or customize_button.disabled or not customize_button.visible: return
	var id: String = utility_weapon_id if utilities_active else stock[selection]
	var customization: Dictionary = session.world.gameplay.customization
	var ok := false
	if CUSTOM.installed(customization, id): ok = session.world.gameplay.install_attachment(id, "flashlight", false)
	elif CUSTOM.owns(customization, id, "flashlight"): ok = session.world.gameplay.install_attachment(id, "flashlight")
	else: ok = session.world.gameplay.buy_attachment(id, "flashlight")
	if ok: session.save_game()
	refresh("PERSONALIZAÇÃO APLICADA" if ok else "PERSONALIZAÇÃO INDISPONÍVEL")

func open_workbench() -> void:
	if not active or workbench_button.disabled or not workbench_button.visible: return
	panel.hide()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if stock[selection] == "katana":
		saber_panel = preload("res://runtime/TakeshiSaberPanel.gd").new()
		saber_panel.configure(session)
		add_child(saber_panel)
		saber_panel.closed.connect(func():
			panel.show()
			preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
			if active: change_selection(0))
		return
	workbench.open(stock[selection])

func _reason(reason: String) -> String:
	return {"insufficient_funds":"DINHEIRO INSUFICIENTE", "already_owned":"VOCÊ JÁ POSSUI ESTA ARMA", "discovery_required":"ARMA BLOQUEADA", "inventory_full":"INVENTÁRIO CHEIO"}.get(reason, "COMPRA INDISPONÍVEL")

func _process(delta: float) -> void:
	if active and not utilities_active and is_instance_valid(gun) and not (is_instance_valid(workbench) and workbench.visible): gun.rotation.y += delta * .22

func purchase_belt_flashlight() -> void:
	if not active: return
	if session.world.gameplay.belt_flashlight.purchase():
		session.save_game()
		refresh("LANTERNA EQUIPADA · G / ↑ DO CONTROLE: LIGAR OU DESLIGAR")
	else: refresh("COMPRA INDISPONÍVEL")
