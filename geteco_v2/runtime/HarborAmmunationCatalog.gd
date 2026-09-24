extends Control
## Catálogo produtivo de HarborAmmunationInterior.gd (V1), adaptado somente
## na fronteira de estado: GameState/Economy/Gameplay substituem o Player 2D.

signal close_requested

const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const WORKBENCH := preload("res://runtime/HarborWeaponWorkbench.gd")

var session
var panel: PanelContainer
var preview: SubViewport
var gun: Node3D
var caption: Label
var feedback: Label
var buy: Button
var ammo_button: Button
var customize_button: Button
var workbench_button: Button
var workbench: PanelContainer
var category_buttons: Array[Button] = []
var selection := 0
var stock := ["pistol", "magnum", "shotgun", "sawed_off", "smg", "ak47", "m4a1", "hunting_rifle", "knife", "knuckles", "bat", "axe", "grenade", "rpg", "flamethrower", "armor"]
var active := false

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
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -390
	panel.offset_right = 390
	panel.offset_top = -294
	panel.offset_bottom = 294
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182323")
	style.border_color = ART.RED
	style.border_width_top = 8
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var brand := Label.new()
	brand.text = "⊕  AMMU-NATION                 ARSENAL / SUPRIMENTOS"
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", ART.CREAM)
	box.add_child(brand)
	var categories := HBoxContainer.new()
	box.add_child(categories)
	for index in 5:
		var button := Button.new()
		button.text = ["ARMAS CURTAS", "ARMAS LONGAS", "CORPO A CORPO", "EXPLOSIVOS", "PROTEÇÃO"][index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34
		var first: String = ["pistol", "shotgun", "knife", "grenade", "armor"][index]
		button.pressed.connect(func(): selection = stock.find(first); change_selection(0))
		categories.add_child(button)
		category_buttons.append(button)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 23)
	box.add_child(caption)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(720, 250)
	container.stretch = true
	box.add_child(container)
	preview = SubViewport.new()
	preview.size = Vector2i(720, 250)
	preview.own_world_3d = true
	preview.transparent_bg = true
	preview.msaa_3d = Viewport.MSAA_4X
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
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y = 56
	box.add_child(feedback)
	var row := HBoxContainer.new()
	box.add_child(row)
	for words in ["◀ ANTERIOR", "COMPRAR", "PRÓXIMA ▶", "FECHAR [ESC]"]:
		var button := Button.new()
		button.text = words
		button.custom_minimum_size.y = 38
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		match words:
			"◀ ANTERIOR": button.pressed.connect(func(): change_selection(-1))
			"PRÓXIMA ▶": button.pressed.connect(func(): change_selection(1))
			"COMPRAR":
				buy = button
				button.pressed.connect(purchase)
			_: button.pressed.connect(func(): close_requested.emit())
	ammo_button = Button.new()
	ammo_button.custom_minimum_size.y = 34
	ammo_button.pressed.connect(purchase_ammo)
	box.add_child(ammo_button)
	var customization_row := HBoxContainer.new()
	customization_row.add_theme_constant_override("separation", 10)
	box.add_child(customization_row)
	workbench_button = Button.new()
	workbench_button.text = "PERSONALIZAR ARMA"
	workbench_button.custom_minimum_size.y = 46
	workbench_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workbench_button.size_flags_stretch_ratio = 1.7
	workbench_button.add_theme_font_size_override("font_size", 17)
	var personalize_style := StyleBoxFlat.new()
	personalize_style.bg_color = ART.RED.darkened(.20)
	personalize_style.border_color = ART.CREAM
	personalize_style.set_border_width_all(2)
	personalize_style.set_corner_radius_all(5)
	workbench_button.add_theme_stylebox_override("normal", personalize_style)
	var personalize_hover := personalize_style.duplicate() as StyleBoxFlat
	personalize_hover.bg_color = ART.RED
	workbench_button.add_theme_stylebox_override("hover", personalize_hover)
	workbench_button.pressed.connect(open_workbench)
	customization_row.add_child(workbench_button)
	customize_button = Button.new()
	customize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	customize_button.custom_minimum_size.y = 46
	customize_button.add_theme_font_size_override("font_size", 14)
	customize_button.pressed.connect(customize_flashlight)
	customization_row.add_child(customize_button)
	workbench = WORKBENCH.new()
	workbench.configure(session)
	add_child(workbench)
	workbench.closed.connect(func():
		panel.show()
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		if active: change_selection(0))
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED

func open_catalog() -> void:
	active = true
	show()
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	change_selection(0)
	category_buttons[0].grab_focus()

func dismiss() -> void:
	active = false
	if is_instance_valid(workbench): workbench.close(false)
	if is_instance_valid(preview): preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if is_instance_valid(workbench) and workbench.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
			workbench.close()
			return true
		return false
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		close_requested.emit()
		return true
	if event.is_action_pressed("ui_left"):
		change_selection(-1)
		return true
	if event.is_action_pressed("ui_right"):
		change_selection(1)
		return true
	return false

func change_selection(step: int) -> void:
	selection = posmod(selection + step, stock.size())
	for child in gun.get_children(): child.free()
	var model := Node3D.new()
	gun.add_child(model)
	ART.item(model, stock[selection])
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

func refresh(notice := "") -> void:
	var id: String = stock[selection]
	var item := data()
	caption.text = "%s   /   $%d" % [item.get("label", id), item.get("price", 0)]
	var armor := id == "armor"
	var owned: bool = session.world.gameplay.armor >= 100 if armor else session.state.economy.owns_weapon(id)
	var unlocked: bool = armor or session.state.economy.is_weapon_unlocked(id)
	buy.disabled = owned or not unlocked or session.state.economy.balance < int(item.get("price", 0))
	buy.text = ("PROTEÇÃO COMPLETA" if armor else "JÁ POSSUI") if owned else ("BLOQUEADA" if not unlocked else "COMPRAR • $%d" % item.price)
	var info := "Proteção: %d / 100 • Reposição de até 100 pontos" % session.world.gameplay.armor if armor else "Dano: %d • Capacidade: %d" % [item.get("damage", 0), maxi(0, item.get("magazine_size", 0))]
	feedback.text = "Saldo: $%d  •  %s\nVance: %s" % [session.state.economy.balance, info, item.get("discovery_hint", "") if not unlocked else "Bem-vindo. Escolha uma categoria; eu te mostro o equipamento."]
	if not notice.is_empty(): feedback.text = notice + "\nSaldo: $%d" % session.state.economy.balance
	var rounds := maxi(0, int(item.get("magazine_size", 0))) * 2
	var price := ammo_price(rounds)
	ammo_button.visible = rounds > 0 and not armor
	ammo_button.text = "REPOR +%d %s • $%d" % [rounds, "GRANADAS" if id == "grenade" else "MUNIÇÕES", price]
	ammo_button.disabled = not owned or session.state.economy.balance < price
	var compatible := id in CUSTOM.COMPATIBLE
	var customization: Dictionary = session.world.gameplay.customization
	customize_button.visible = compatible
	workbench_button.visible = id in CUSTOM.CUSTOMIZABLE
	workbench_button.disabled = not owned
	customize_button.disabled = not owned or (not CUSTOM.owns(customization, id, "flashlight") and session.state.economy.balance < CUSTOM.PRICE)
	customize_button.text = "REMOVER LANTERNA" if CUSTOM.installed(customization, id) else ("INSTALAR LANTERNA" if CUSTOM.owns(customization, id, "flashlight") else "INSTALAR LANTERNA • $%d" % CUSTOM.PRICE)
	var category := 4 if armor else (3 if id in ["grenade", "rpg"] else (2 if id in ["knife", "knuckles", "bat", "axe"] else (0 if id in ["pistol", "magnum"] else 1)))
	for i in category_buttons.size(): category_buttons[i].modulate = ART.CREAM if i == category else Color("8faaa3")

func ammo_price(rounds: int) -> int:
	return maxi(40, rounds * (60 if stock[selection] in ["grenade", "rpg"] else 2))

func purchase() -> void:
	if not active or buy.disabled: return
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

func customize_flashlight() -> void:
	if not active or customize_button.disabled or not customize_button.visible: return
	var id: String = stock[selection]
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
	workbench.open(stock[selection])

func _reason(reason: String) -> String:
	return {"insufficient_funds":"DINHEIRO INSUFICIENTE", "already_owned":"VOCÊ JÁ POSSUI ESTA ARMA", "discovery_required":"ARMA BLOQUEADA", "inventory_full":"INVENTÁRIO CHEIO"}.get(reason, "COMPRA INDISPONÍVEL")

func _process(delta: float) -> void:
	if active and is_instance_valid(gun) and not (is_instance_valid(workbench) and workbench.visible): gun.rotation.y += delta * .22
