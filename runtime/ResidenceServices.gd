extends Node
## Production V1: HarborGame -> ResidenceManager._run_action -> ResidenceMenu.
## Physical furniture actions; residence owns persistence, backpack owns inventory.
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const HOMES := preload("res://data/catalogs/ResidenceCatalog.gd")
const CATS := preload("res://runtime/cats/CatAdoption.gd")
var session
var _home := ""
var _menu_health := 0.0
var _station := ""
var storage := preload("res://runtime/ResidenceStorage.gd").new()
var presentation: Node
var _rest_tween: Tween
var _rest_clock: Label
var _rest_start := 0.0
var _rest_minutes := 0
var _rest_progress := 0.0
var _refresh_clock := 0.0
var _scroll_minimum := Vector2.ZERO
var _scroll_horizontal := ScrollContainer.SCROLL_MODE_AUTO
const BACKPACK_CLAIM := "residence_backpack"
const GRID := preload("res://systems/inventory/GridInventory.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
var _custom_weapon := ""
var _custom_slot := ""
var _custom_category := "finish"
var _custom_part := "none"
var _custom_stats: Label
var _custom_apply: Button
var _custom_options: Array[Button] = []
var _custom_list: VBoxContainer
var _custom_categories: OptionButton
var _custom_back: Button
const LABELS := {"wardrobe":"Trocar de roupa","chest":"Abrir baú","food":"Abrir geladeira","save":"Salvar jogo","time":"Descansar","arsenal":"Usar bancada","backpack":"Colocar mochila"}

func configure(owner_session) -> void:
	session = owner_session
	presentation = load("res://runtime/ResidencePresentation.gd").new()
	add_child(presentation)
	presentation.configure(session)
	storage.bind_inventory(self)

func _process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	if presentation != null and presentation.is_active() and (not session.modal or not session.panel.get_meta("modal_dock_right",false) or not _menu_available()):
		_close_presentation()
	_refresh_clock += delta
	if _refresh_clock < .25: return
	_refresh_clock = 0.0
	if _accessible() and is_instance_valid(session.room.model.get("backpack_prop")):
		session.room.model.backpack_prop.visible = _backpack_available()

func _backpack_available() -> bool:
	var grid: Dictionary = session.state.economy.grid_snapshot()
	return grid.bag == "" and BACKPACK_CLAIM not in grid.claimed

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	if session == null or session.modal or get_tree().paused or not _accessible(): return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(event.position)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(event.position)*80.0,1)
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var station: String = {"Wardrobe":"wardrobe","Kitchen":"food","Bed":"time","Armory":"arsenal","StorageChest":"chest","SaveDesk":"save","BackpackStand":"backpack"}.get(str(hit.collider.name),"")
	if station.is_empty() or not _near_station(station): return
	_start_station(station)
	get_viewport().set_input_as_handled()

func _close_presentation() -> void:
	if is_instance_valid(_rest_tween): _rest_tween.kill()
	_rest_tween = null
	_rest_clock = null
	_rest_progress = 0.0
	if presentation != null: presentation.finish()
	if _scroll_minimum != Vector2.ZERO:
		session.column.get_parent().custom_minimum_size = _scroll_minimum
		session.column.get_parent().horizontal_scroll_mode = _scroll_horizontal
		_scroll_minimum = Vector2.ZERO
	_custom_options.clear()
	if is_instance_valid(session.panel) and session.panel.has_meta("modal_dock_right"): session.panel.remove_meta("modal_dock_right")

func _station_menu(title: String) -> void:
	session._menu(title)
	var scroll: ScrollContainer = session.column.get_parent()
	if _scroll_minimum == Vector2.ZERO:
		_scroll_minimum = scroll.custom_minimum_size
		_scroll_horizontal = scroll.horizontal_scroll_mode
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	session.panel.set_meta("modal_preferred_size",Vector2(330,480))
	session.panel.set_meta("modal_dock_right",true)
	session.panel.custom_minimum_size = Vector2(330,480)
	session.panel.size = Vector2(330,480)
	session.menu_closed = _close_presentation
	if not presentation.is_active(): presentation.begin(_station)

func _accessible() -> bool:
	if session == null or not session.ready_for_play or session.controller.save_invalid: return false
	if session.world.driving.occupied or session.world.gameplay.health <= 0: return false
	if session.state.region_id != "harbor" or not HOMES.PROPERTIES.has(session.state.place_id): return false
	if not session.activities.residence.can_enter(session.state.place_id) or not is_instance_valid(session.room): return false
	return not session.is_transition_blocked()

func _near_station(station: String) -> bool:
	var point: Variant = session.room.interaction_points.get(station)
	return point is Vector3 and session.world.player.position.distance_to(point) < .95

func nearest_action() -> Dictionary:
	if session == null or session.modal or not _accessible(): return {}
	var nearest := ""
	var distance := .95
	for station in LABELS:
		if station == "backpack" and not _backpack_available(): continue
		var point: Variant = session.room.interaction_points.get(station)
		if not point is Vector3: continue
		var separation: float = session.world.player.position.distance_to(point)
		if separation < distance:
			distance = separation
			nearest = station
	if nearest.is_empty(): return {}
	var label: String = LABELS[nearest]
	if nearest == "chest" and not storage.unlocked(): label = "Baú · desbloqueie a mochila"
	return {"id":"residence_services","target":"residence_services","station":nearest,"label":label}

func perform(target: String) -> bool:
	if target != "residence_services" or nearest_action().is_empty(): return false
	_start_station(nearest_action().station)
	return true

func _start_station(station: String) -> void:
	_station = station
	_home = session.state.place_id
	_menu_health = session.world.gameplay.health
	_open()

func _menu_available() -> bool:
	if not _accessible() or session.state.place_id != _home or not _near_station(_station) or session.world.gameplay.health < _menu_health:
		session.close_menu()
		return false
	return true

func _focus() -> void:
	if session.panel.get_meta("modal_dock_right",false):
		for child in session.column.get_children():
			if child is Button:
				child.clip_text = true
				child.tooltip_text = child.text
	for child in session.column.get_children():
		if child is Button and not child.disabled:
			session._focus_menu_button.call_deferred(weakref(child))
			return

func _open() -> void:
	if not _menu_available(): return
	match _station:
		"wardrobe": _wardrobe()
		"chest": _chest()
		"food": _fridge()
		"save": _save()
		"time": _rest_menu()
		"arsenal": _arsenal()
		"backpack": _take_backpack()

func _wardrobe() -> void:
	if not _menu_available(): return
	_station_menu("Guarda-roupa")
	for item in session.state.economy.storefront("outfit"):
		if not item.owned: continue
		var equipped: bool = str(item.id) == session.state.economy.outfit
		session._button(("✓ " if equipped else "")+str(item.get("name",item.get("label",item.id))),_wear.bind(str(item.id)))
	session._button("Fechar",session.close_menu)
	_focus()

func _wear(id: String) -> void:
	if _station != "wardrobe" or not _menu_available(): return
	if preload("res://runtime/OutfitDisguise.gd").equip(session, id):
		presentation.refresh_outfit()
		session.save_game()
		_wardrobe()

func _arsenal() -> void:
	if not _menu_available(): return
	_station_menu("Bancada de armas")
	var selected: Dictionary = session.state.economy.personal_loadout()
	for slot in session.state.economy.PERSONAL_SLOTS:
		var title: String = {"curta":"Curta","longa":"Longa","corpo":"Corpo a corpo","granada":"Granada"}[slot]
		var weapon: String = str(selected.get(slot,""))
		session._button(title+" · "+str(WEAPONS.WEAPONS.get(weapon,{}).get("label","Vazio")),_select_slot.bind(slot))
		var button: Button = session.column.get_child(session.column.get_child_count()-1)
		button.focus_entered.connect(presentation.preview_weapon.bind(weapon))
		button.mouse_entered.connect(presentation.preview_weapon.bind(weapon))
	var first := ""
	for weapon in selected.values():
		if not str(weapon).is_empty(): first = str(weapon); break
	presentation.preview_weapon(first)
	session._button("Fechar",session.close_menu)
	_focus()

func _select_slot(slot: String) -> void:
	if _station != "arsenal" or not session.state.economy.PERSONAL_SLOTS.has(slot) or not _menu_available(): return
	_station_menu("Bancada de armas")
	session._button("Guardar arma",_set_slot.bind(slot,""))
	for id in session.state.economy.PERSONAL_SLOTS[slot]:
		if session.state.economy.owns_weapon(id):
			session._button(str(WEAPONS.WEAPONS[id].label),_weapon_menu.bind(str(id),slot))
			var button: Button = session.column.get_child(session.column.get_child_count()-1)
			button.focus_entered.connect(presentation.preview_weapon.bind(str(id)))
			button.mouse_entered.connect(presentation.preview_weapon.bind(str(id)))
	session._button("Voltar",_arsenal)
	_focus()

func _weapon_menu(id: String, slot: String) -> void:
	if _station != "arsenal" or not _menu_available() or not session.state.economy.owns_weapon(id): return
	_station_menu(str(WEAPONS.WEAPONS[id].get("short_label",id)))
	presentation.preview_weapon(id,true)
	var selected: bool = session.state.economy.personal_loadout().get(slot,"") == id
	session._button("✓ Equipada" if selected else "Levar comigo",_set_slot.bind(slot,id))
	if id in CUSTOM.CUSTOMIZABLE: session._button("Personalizar",_customize_weapon.bind(id,slot,"finish"))
	session._button("Trocar arma",_select_slot.bind(slot))
	session._button("Fechar",session.close_menu)
	_focus()

func _customize_weapon(id: String, slot: String, category: String) -> void:
	if _station != "arsenal" or not _menu_available() or not session.state.economy.owns_weapon(id): return
	_custom_weapon = id
	_custom_slot = slot
	_custom_category = category
	_station_menu(str(WEAPONS.WEAPONS[id].get("short_label",id)))
	session.panel.set_meta("modal_preferred_size",Vector2(360,660))
	var wallet := Label.new()
	wallet.text = "R$ %d"%session.state.economy.balance
	session.column.add_child(wallet)
	var categories := OptionButton.new()
	_custom_categories = categories
	var available: Array[String] = []
	for key in CUSTOM.SLOTS:
		if not CUSTOM.PARTS.keys().any(func(part): return CUSTOM.PARTS[part].slot == key and CUSTOM.supports(id,part)): continue
		available.append(key)
		categories.add_item(CUSTOM.slot_label(id,key).capitalize())
	if category not in available: category = available[0]; _custom_category = category
	categories.selected = available.find(category)
	categories.item_selected.connect(func(index): _customize_weapon(id,slot,available[index]))
	session.column.add_child(categories)
	var choices := ScrollContainer.new()
	choices.custom_minimum_size.y = 180
	choices.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices.follow_focus = true
	session.column.add_child(choices)
	_custom_list = VBoxContainer.new()
	_custom_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_list.add_theme_constant_override("separation",6)
	choices.add_child(_custom_list)
	_custom_options.clear()
	_custom_option("none","Original")
	for part in CUSTOM.PARTS:
		if CUSTOM.PARTS[part].slot != category or not CUSTOM.supports(id,part): continue
		var owned := CUSTOM.owns(session.world.gameplay.customization,id,part)
		_custom_option(part,str(CUSTOM.PARTS[part].label)+("" if owned else " · R$ %d"%CUSTOM.PARTS[part].price))
	_custom_stats = Label.new()
	_custom_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_custom_stats.add_theme_font_size_override("font_size",15)
	session.column.add_child(_custom_stats)
	session._button("Instalar",_apply_custom_part)
	_custom_apply = session.column.get_child(session.column.get_child_count()-1)
	session._button("Voltar",_weapon_menu.bind(id,slot))
	_custom_back = session.column.get_child(session.column.get_child_count()-1)
	_preview_custom_part(CUSTOM.selected(session.world.gameplay.customization,id,category))
	_focus()

func _custom_option(part: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36
	button.pressed.connect(_preview_custom_part.bind(part))
	button.clip_text = true
	button.tooltip_text = label
	_custom_list.add_child(button)
	button.toggle_mode = true
	button.set_meta("part",part)
	_custom_options.append(button)

func _preview_custom_part(part: String) -> void:
	if _station != "arsenal" or not _menu_available(): return
	if part != "none" and (not CUSTOM.supports(_custom_weapon,part) or CUSTOM.PARTS[part].slot != _custom_category): return
	_custom_part = part
	var actual: Dictionary = session.world.gameplay.customization
	var preview: Dictionary = actual.duplicate(true)
	var entry: Dictionary = preview.get(_custom_weapon,{}).duplicate(true)
	if _custom_category == "flashlight":
		entry.owned = true
		entry.installed = part != "none"
	else:
		var parts: Dictionary = entry.get("parts",{}).duplicate(true)
		if part == "none": parts.erase(_custom_category)
		else: parts[_custom_category] = part
		entry.parts = parts
	preview[_custom_weapon] = entry
	presentation.preview_weapon(_custom_weapon,true,preview)
	for button in _custom_options:
		if is_instance_valid(button): button.set_pressed_no_signal(button.get_meta("part") == part)
	var current := CUSTOM.selected(actual,_custom_weapon,_custom_category)
	var owned := CUSTOM.owns(actual,_custom_weapon,part)
	var price := 0 if owned else int(CUSTOM.PARTS[part].price)
	var before := CUSTOM.stats(_custom_weapon,actual)
	var after := CUSTOM.stats(_custom_weapon,preview)
	var stats: Array[String] = []
	for i in after.size():
		if after[i][0] not in ["Dano","Alcance","Capacidade","Recarga","Golpes/s"]: continue
		stats.append("%s  %s"%[after[i][0],after[i][2]] if is_equal_approx(before[i][1],after[i][1]) else "%s  %s → %s"%[after[i][0],before[i][2],after[i][2]])
	_custom_stats.text = "\n".join(stats)
	_custom_apply.text = "✓ Instalado" if current == part else "Remover" if part == "none" else "Instalar" if owned else "Comprar e instalar · R$ %d"%price
	_custom_apply.disabled = current == part or session.state.economy.balance < price
	if session.state.economy.balance < price: _custom_apply.text = "Faltam R$ %d"%(price-session.state.economy.balance)
	_wire_custom_focus()

func _wire_custom_focus() -> void:
	var controls: Array[Control] = [_custom_categories]
	for button in _custom_options: controls.append(button)
	if not _custom_apply.disabled: controls.append(_custom_apply)
	controls.append(_custom_back)
	for i in controls.size():
		var previous: Control = controls[posmod(i-1,controls.size())]
		var next: Control = controls[(i+1)%controls.size()]
		controls[i].focus_neighbor_top = controls[i].get_path_to(previous)
		controls[i].focus_previous = controls[i].focus_neighbor_top
		controls[i].focus_neighbor_bottom = controls[i].get_path_to(next)
		controls[i].focus_next = controls[i].focus_neighbor_bottom

func _apply_custom_part() -> void:
	if _station != "arsenal" or not _menu_available() or not session.state.economy.owns_weapon(_custom_weapon): return
	var current := CUSTOM.selected(session.world.gameplay.customization,_custom_weapon,_custom_category)
	if current == _custom_part: return
	var ok: bool
	if _custom_part == "none": ok = session.world.gameplay.install_attachment(_custom_weapon,current,false)
	else: ok = session.world.gameplay.buy_attachment(_custom_weapon,_custom_part)
	if ok: session.save_game()
	else: session.show_message("Personalização indisponível.")
	_customize_weapon(_custom_weapon,_custom_slot,_custom_category)

func _set_slot(slot: String, id: String) -> void:
	if _station != "arsenal" or not _menu_available(): return
	# Activating residential storage must never award Monaliza's starter case.
	session.state.economy.enable_personal_loadout()
	if session.state.economy.set_personal_slot(slot,id):
		if not session.state.weapons_allowed(): session.state.equip_weapon("fists")
		session.save_game()
	else: session.show_message("Sem espaço para guardar a arma atual.")
	_select_slot(slot)
	presentation.preview_weapon(id)

func _rest_menu() -> void:
	if not _menu_available(): return
	_station_menu("Descansar")
	for minutes in [15,60,240,480]:
		session._button("15 minutos" if minutes == 15 else "%d hora%s"%[minutes/60,"" if minutes == 60 else "s"],_rest_for.bind(minutes))
	session._button("Até amanhecer",_rest.bind(.36))
	session._button("Até anoitecer",_rest.bind(.84))
	session._button("Fechar",session.close_menu)
	_focus()

func _rest(target: float) -> void:
	if target not in [.36,.84]: return
	_rest_for(maxi(1,roundi(fposmod(target-float(session.weather.time_of_day),1.0)*1440.0)))

func _rest_for(minutes: int) -> void:
	if _station != "time" or is_instance_valid(_rest_tween) or not _menu_available() or minutes < 1 or minutes > 1440: return
	if not session.can_rest_at_residence():
		session.show_message("Termine o trabalho e despiste a polícia para descansar.")
		return
	_rest_start = session.weather.time_of_day
	_rest_minutes = minutes
	_station_menu("Descansando")
	_rest_clock = Label.new()
	_rest_clock.add_theme_font_size_override("font_size",30)
	session.column.add_child(_rest_clock)
	session._button("Levantar",session.close_menu)
	_rest_progress = 0.0
	_rest_tick(0.0)
	_rest_tween = create_tween()
	_rest_tween.tween_method(presentation.rest_pose,0.0,1.0,.85).set_trans(Tween.TRANS_SINE)
	_rest_tween.tween_method(_rest_tick,0.0,1.0,3.0)
	_rest_tween.tween_callback(_complete_rest)

func _rest_tick(amount: float) -> void:
	_rest_progress = amount
	var minute := int(fposmod(_rest_start*1440.0+amount*_rest_minutes,1440.0))
	if is_instance_valid(_rest_clock): _rest_clock.text = "%02d:%02d\n+%d min"%[floori(float(minute)/60.0),minute%60,int(amount*_rest_minutes)]

func _complete_rest() -> void:
	if not _menu_available() or not session.can_rest_at_residence():
		session.close_menu()
		return
	if session.advance_residence_minutes(_rest_minutes): session.save_game()
	# Animate getting up, then restore the exact approach and original camera.
	_rest_tween = create_tween()
	_rest_tween.tween_method(presentation.rest_pose,1.0,0.0,.7).set_trans(Tween.TRANS_SINE)
	_rest_tween.tween_callback(session.close_menu)

func _fridge() -> void:
	if not _menu_available(): return
	_station_menu("Geladeira")
	session._button("Comer uma refeição · +35 vida",_consume.bind("meal"))
	session._button("Beber suco · +15 vida",_consume.bind("drink"))
	session._button("Fechar",session.close_menu)
	_focus()

func _consume(kind: String) -> void:
	if kind not in ["meal","drink"] or _station != "food" or not _menu_available(): return
	var recovered: bool = session.world.gameplay.heal(35 if kind == "meal" else 15)
	session.close_menu()
	if recovered and not session.save_game(): return
	session.show_message("Refeição concluída." if recovered and kind == "meal" else "Bebida consumida." if recovered else "Vida já está completa.")

func _take_backpack() -> void:
	if _station != "backpack" or not _menu_available() or not _backpack_available(): return
	var economy = session.state.economy
	if not economy.grid_equip_bag("backpack"): return
	economy.grid_claim(BACKPACK_CLAIM)
	if is_instance_valid(session.room.model.get("backpack_prop")): session.room.model.backpack_prop.hide()
	if session.field_inventory != null: session.field_inventory._update_carried()
	session.save_game()

func is_backpack_unlocked() -> bool:
	return session != null and session.state.economy.grid_snapshot().bag != ""

func storage_items() -> Dictionary:
	var result := {}
	for id in session.state.economy.inventory:
		result[id] = {"label":GRID.spec(id).get("label",id),"count":session.state.economy.inventory[id]}
	return result

func remove_storage_item(id: String,count: int) -> bool:
	return session.state.economy.consume_item(id,count)

func add_storage_item(id: String,count: int) -> bool:
	return session.state.economy.grant_item(id,count)

func _save() -> void:
	if _station != "save" or not _menu_available(): return
	session.close_menu()
	if session.save_game(true): session.show_message("Jogo salvo.")
	_home_menu()

func _home_menu() -> void:
	if _station != "save" or not _menu_available(): return
	_station_menu("Casa")
	session._button("Salvar jogo", _save)
	session._button("Caminhas e brinquedos", _cat_shop)
	session._button("Fechar", session.close_menu)
	_focus()

func _cat_shop() -> void:
	if _station != "save" or not _menu_available(): return
	_station_menu("Caminhas e brinquedos")
	var residence = session.activities.residence
	var status := Label.new()
	status.text = "%d/10 gatos adotados · R$ %d" % [residence.cat_count(), session.state.economy.balance]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session.column.add_child(status)
	var furniture: Dictionary = residence.cat_furniture()
	for id in CATS.FURNITURE:
		var item: Dictionary = CATS.FURNITURE[id]
		var amount := int(furniture[id])
		var full := amount >= int(item.limit)
		var label := "%s · %d/%d" % [str(item.label), amount, int(item.limit)]
		if not full: label += " · R$ %d" % int(item.price)
		session._button(label, _buy_cat_furniture.bind(str(id)))
		var button: Button = session.column.get_child(session.column.get_child_count() - 1)
		button.disabled = full or session.state.economy.balance < int(item.price)
	session._button("Voltar", _home_menu)
	_focus()

func _buy_cat_furniture(id: String) -> void:
	if _station != "save" or not _menu_available(): return
	if session.activities.residence.buy_cat_furniture(id):
		session.save_game()
	else:
		session.show_message("Compra indisponível.")
	_cat_shop()

func _chest() -> void:
	if not _menu_available(): return
	if not storage.unlocked():
		session.close_menu()
		session.show_message("Desbloqueie a mochila para usar o baú.")
		return
	session._menu("Baú")
	var chest: Dictionary = session.activities.residence.data.chest
	var items := storage.items()
	for id in items:
		if not items[id] is Dictionary or int(items[id].get("count",0)) < 1: continue
		session._button("Guardar · "+str(items[id].get("label",id)),_transfer.bind(str(id),true))
	for id in chest:
		var label: String = str(items.get(id,{}).get("label",id))
		session._button("Retirar · %s ×%d"%[label,int(chest[id])],_transfer.bind(str(id),false))
	session._button("Fechar",session.close_menu)
	_focus()

func _transfer(id: String, deposit: bool) -> void:
	if _station != "chest" or not _menu_available() or not storage.unlocked(): return
	var chest: Dictionary = session.activities.residence.data.chest
	var changed := storage.deposit(chest,id) if deposit else storage.withdraw(chest,id)
	if changed: session.save_game()
	else: session.show_message("Sem espaço para transferir este item.")
	_chest()
