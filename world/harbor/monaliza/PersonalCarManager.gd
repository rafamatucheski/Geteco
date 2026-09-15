extends Node
const CAR := preload("res://world/harbor/monaliza/MonalizaCar.gd")
const RULES := preload("res://world/harbor/monaliza/PersonalLoadout.gd")
const RECOVERY_FEE := 50
const REPAIR_FEE := 50
var _car_layer := 0
var _car_mask := 0
var impounded := false
var introduction_seen := false
var introduction: CanvasLayer
var delivery_in_progress := false
var car: Node2D
var player: Node2D
var garage: Node2D
var panel: PanelContainer
var rows: GridContainer
var prompt: Label
var message: Label
var _old_disabled := false
var _tick := 0.0
var _panel_health := 0
var pending_loadout: Dictionary = {}
var live_view: Control
var save_button: Button
var weapon_stats: Label
var first_trunk_hint: TutorialHintPresenter
func _ready() -> void:
	add_to_group("personal_car_manager")
	player = get_parent().get_node("Player")
	garage = get_parent().get_node("Interiors").garage_interior
	car = CAR.new()
	car.name = "Monaliza"
	car.position = get_parent().to_local(bay_position())
	car.rotation = PI/2
	get_parent().add_child(car)
	_car_layer = car.collision_layer
	_car_mask = car.collision_mask
	_apply_state(player.personal_car_state)
	car.unlocked = get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete")
	get_parent().campaign_controller.delivery_finished.connect(_grant)
	_build_ui()
	if car.unlocked: _grant(false)
	_sync_availability()
func bay_position() -> Vector2: return garage.get_vehicle_bay_position()
func restore_from_player() -> void:
	var restored: Dictionary = player.personal_car_state.duplicate(true)
	close_panel()
	car.global_position = bay_position()
	car.rotation = PI/2
	car.repair_vehicle()
	player.personal_car_state = restored
	car.restore_factory_handling()
	_apply_state(restored)
	car.unlocked = get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete")
	_sync_availability()
func _sync_availability() -> void:
	car.visible = car.unlocked and not impounded
	car.process_mode = Node.PROCESS_MODE_INHERIT if car.visible else Node.PROCESS_MODE_DISABLED
	car.collision_layer = _car_layer if car.visible else 0
	car.collision_mask = _car_mask if car.visible else 0
func impound_if_driven() -> void:
	if not car.unlocked or not car.is_driven_by_player: return
	car.force_exit_vehicle()
	impounded = true
	_sync_availability()
	capture_state()
func is_car_in_garage() -> bool:
	return car.visible and garage.contains_point(car.global_position)
func can_recover(include_parked := false) -> bool:
	return car.unlocked and not car.is_driven_by_player and not car.has_meta("vehicle_boarding") and (impounded or car.is_broken or car.is_exploded or not preload("res://cars/VehicleMotionSafety.gd").valid_position(car.global_position) or (include_parked and not is_car_in_garage()))

func can_repair() -> bool:
	return car.unlocked and not delivery_in_progress and not impounded and is_car_in_garage() and not car.is_driven_by_player and not car.has_meta("vehicle_boarding") and (car.health < car.max_health or car.is_broken or car.is_exploded or car.is_exploding or car.has_punctured_tires)

func repair() -> bool:
	if not can_repair() or not garage.contains_point(player.global_position) or player.money < REPAIR_FEE:
		return false
	player.money -= REPAIR_FEE
	car.velocity = Vector2.ZERO
	car.repair_vehicle()
	car.restore_factory_handling()
	player._refresh_weapon_ui()
	capture_state()
	return true
func _apply_state(data: Dictionary) -> void:
	impounded = bool(data.get("impounded",false))
	introduction_seen = bool(data.get("introduction_seen",false))
	if data.is_empty(): return
	var point = data.get("position",[])
	if point is Array and point.size()==2:
		var pos := Vector2(float(point[0]),float(point[1]))
		if pos.is_finite(): car.global_position = pos
	var angle := float(data.get("rotation",PI/2))
	car.rotation = angle if is_finite(angle) else PI/2
	car.health = clampi(int(data.get("health",180)),0,180)
	car.is_broken = bool(data.get("broken",false)) or car.health <= 0
	car.repaint_vehicle(Color(String(data.get("paint","183b91"))))
func capture_state() -> void:
	if not is_instance_valid(car) or not is_instance_valid(player): return
	var point: Vector2 = car.get_meta("service_safe_position",car.global_position)
	player.personal_car_state = {"position":[point.x,point.y],"rotation":car.get_meta("service_safe_rotation",car.rotation),"health":car.health,"broken":car.is_broken,"paint":car.paint_color.to_html(),"impounded":impounded,"introduction_seen":introduction_seen}
func _grant(speak := true) -> void:
	if delivery_in_progress: return
	if speak and not garage.showroom.delivery_done:
		delivery_in_progress = true
		var disabled_before: bool = player.is_control_disabled
		get_parent().get_node("CobraCampaign")._message("Maciota", _text("Olha quem está chegando. Trouxeram tua Monaliza.", "Look who's arriving. They've brought your Monaliza."))
		player.is_control_disabled = true
		await garage.showroom.deliver_monaliza()
		if not get_parent().get_node("CobraCampaign")._locked:
			player.is_control_disabled = disabled_before
		# O diálogo segue com o jogo pausado: sem isto a Monaliza aparecia de lado.
		if car.has_method("sync_presentation_heading"): car.sync_presentation_heading()
		delivery_in_progress = false
	car.unlocked = true
	_sync_availability()
	capture_state()
	if speak:
		get_parent().get_node("CobraCampaign")._message("Maciota",_text("Agora essa é tua. Cuide da nossa Monaliza, ouviu? Ela vai te levar por aí. Dá uma olhada no porta-malas... deixei uma surpresa para você.","She's yours now. Take care of our Monaliza, alright? She'll get you around. Check the trunk... I left you a surprise."))
func show_introduction() -> void:
	if introduction_seen or is_instance_valid(introduction) or not car.unlocked: return
	introduction = preload("res://world/harbor/monaliza/MonalizaIntroduction.gd").new()
	add_child(introduction)
	introduction.finished.connect(func():
		introduction_seen = true
		capture_state())
func _text(pt: String,en: String) -> String: return en if TranslationServer.get_locale().begins_with("en") else pt
func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.15: return
	_tick = 0
	if not is_instance_valid(car): return
	if not car.unlocked:
		car.global_position = bay_position()
		car.velocity = Vector2.ZERO
	var near_rear: bool = car.visible and not car.is_broken and player.global_position.distance_to(car.global_position-car.global_transform.x*47)<58
	var near_bay := player.global_position.distance_to(bay_position())<150
	var free: bool = player.visible and not player.is_dead and not player.is_in_dialogue and not player.is_control_disabled
	prompt.visible = car.unlocked and free and not panel.visible and (near_rear or near_bay)
	if not car.unlocked: prompt.text = _text("MONALIZA / Termine a entrega para receber as chaves.","MONALIZA / Finish the delivery to receive the keys.")
	elif near_rear and car.velocity.length()<3: prompt.text = _text("[T] PORTA-MALAS · MONALIZA / %d%% de integridade","[T] TRUNK · MONALIZA / %d%% condition") % int(100*car.health/180.0)
	elif near_bay: prompt.text = _text("[T] MONALIZA / Recuperar e cuidar do seu carro","[T] MONALIZA / Recover and service your car")
	else: prompt.hide()
	if panel.visible and (player.is_dead or player.health < _panel_health or not player.visible or car.velocity.length()>3 or (not near_rear and not near_bay)): close_panel()
	# Drive straight out through the dedicated showroom gate using the existing interior return contract.
	# Passa pela cortina do gerenciador: o corte para a rua acontece com a tela
	# preta, e enquanto ela esta no ar is_transitioning() impede um segundo
	# disparo (este _process roda a cada 0.15 s e o carro continua rolando).
	# `player.has_meta("harbor_interior")` e o unico sinal de que o carro esta
	# mesmo la dentro: fora da garagem a projecao da oficina devolve metros sem
	# sentido e a faixa do portao pode dar positivo por acidente.
	if car.is_driven_by_player and player.has_meta("harbor_interior") and garage.is_vehicle_at_exit(car.global_position):
		var interiors: Node = get_parent().get_node("Interiors")
		if not interiors.is_transitioning():
			interiors.request_transition(func() -> void:
				interiors._on_exit_door_requested(garage.exit_door,car,&"",null,&"",&"harbor/District/Garage/Entrance")
				car.rotation = PI/2)
	capture_state()
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if panel.visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("trunk") and prompt.visible and car.unlocked:
		open_panel()
		get_viewport().set_input_as_handled()
func open_panel() -> void:
	if panel.visible: return
	if not car.unlocked or not player.visible or player.is_dead or player.is_in_dialogue or player.is_control_disabled or car.velocity.length()>3: return
	var near: bool = car.visible and not car.is_broken and player.global_position.distance_to(car.global_position-car.global_transform.x*47)<58
	if not near and player.global_position.distance_to(bay_position())>=150: return
	_old_disabled = player.is_control_disabled
	_panel_health = player.health
	player.is_control_disabled = true
	player.velocity = Vector2.ZERO
	panel.show()
	if near:
		car.set_trunk_open(true)
		if not player.world_pickups_collected.has("monaliza_starter_case"):
			player.world_pickups_collected.append("monaliza_starter_case")
			player.add_weapon_loot(&"pistol",72,false)
			player.personal_loadout_enabled = true
			player.personal_loadout = {"curta":"pistol","longa":"","corpo":"","granada":""}
			var ammo: Dictionary = player.weapon_ammo.pistol
			var rounds := mini(12 - int(ammo.clip), int(ammo.reserve))
			ammo.clip += rounds
			ammo.reserve -= rounds
			player.equip_weapon("pistol")
			_show_first_trunk_hint()
		else: message.text = _text("Seu arsenal fica preservado. Armas novas sem espaço entram na reserva; organize aqui antes de sair.","Your arsenal stays safe. New weapons without a free slot enter storage; organize them here before leaving.")
	else: message.text = _text("Recuperação: $50. Seu equipamento é preservado. Se ela estiver estacionada, busque-a no mapa.","Recovery: $50. Your equipment is preserved. If parked, find her on the map.")
	player.personal_loadout = RULES.normalize(player.personal_loadout, player.weapon_inventory)
	pending_loadout = player.personal_loadout.duplicate(true)
	message.visible = not near
	save_button.visible = near
	if near:
		live_view = preload("res://world/harbor/monaliza/TrunkLiveView.gd").new()
		panel.get_parent().add_child(live_view)
		panel.get_parent().move_child(live_view, panel.get_index())
		live_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		live_view.setup(car)
		live_view.weapon_inspected.connect(_inspect_weapon)
		live_view.set_loadout(pending_loadout)
	weapon_stats.hide()
	_refresh_rows(near)
	_fit_panel.call_deferred()
func close_panel() -> void:
	if not panel.visible: return
	panel.hide()
	if is_instance_valid(first_trunk_hint):
		first_trunk_hint.free()
		first_trunk_hint = null
	if is_instance_valid(live_view):
		live_view.free()
		live_view = null
	pending_loadout.clear()
	player.is_control_disabled = _old_disabled
	car.set_trunk_open(false)
	capture_state()
func _show_first_trunk_hint() -> void:
	# The trunk disables movement and covers the HUD, so its introduction lives
	# above the trunk itself instead of waiting in the ambient tutorial queue.
	first_trunk_hint = preload("res://ui/tutorial_preview/TutorialHintPresenter.gd").new()
	add_child(first_trunk_hint)
	first_trunk_hint.layer = 71
	first_trunk_hint.set_locale("en" if TranslationServer.get_locale().begins_with("en") else "pt")
	first_trunk_hint.set_hint_duration(18.0)
	var box := first_trunk_hint._box
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -290
	box.offset_right = 290
	box.offset_top = -100
	box.offset_bottom = 100
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := box.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color("111b20")
	box.add_theme_stylebox_override("panel",style)
	first_trunk_hint._title_label.add_theme_font_size_override("font_size",22)
	first_trunk_hint._body_label.add_theme_font_size_override("font_size",18)
	first_trunk_hint._body_label.add_theme_color_override("font_color",Color("d1dcdf"))
	first_trunk_hint.request_hint("first_trunk")
func set_slot(slot: String,id: String) -> bool:
	if not panel.visible or not car.trunk_open or not player.personal_loadout_enabled: return false
	if not RULES.GROUPS.has(slot) or id not in RULES.GROUPS[slot] or not player.weapon_inventory.get(id,false): return false
	pending_loadout[slot] = id
	if is_instance_valid(live_view):
		live_view.play_selection()
		live_view.set_loadout(pending_loadout)
	_inspect_weapon(id)
	_refresh_rows(true)
	return true
func _inspect_weapon(id: String) -> void:
	var data := WeaponCatalog.get_weapon(id)
	if data.is_empty(): return
	var damage := str(int(data.get("damage", 0)))
	if int(data.get("pellets", 1)) > 1: damage += " × %d" % int(data.pellets)
	weapon_stats.text = "%s   ·   %s: %s   ·   %.2f s" % [String(data.get("label", id)), _text("Dano", "Damage"), damage, float(data.get("fire_interval", 0))]
	var magazine := int(data.get("magazine_size", -1))
	if magazine > 0: weapon_stats.text += "   ·   " + _ammo_text(id)
	weapon_stats.show()
	_fit_panel.call_deferred()
func _ammo_text(id: String) -> String:
	if id.is_empty(): return "—"
	var capacity := int(WeaponCatalog.get_weapon(id).get("magazine_size", -1))
	if capacity <= 0: return _text("Sem munição", "No ammunition")
	var ammo: Dictionary = player.weapon_ammo.get(id, {})
	if id == "grenade": return _text("%d disponíveis", "%d available") % (int(ammo.get("clip", 0)) + int(ammo.get("reserve", 0)))
	return _text("%d/%d · Reserva %d", "%d/%d · Reserve %d") % [int(ammo.get("clip", 0)), capacity, int(ammo.get("reserve", 0))]
func save_loadout() -> void:
	if not panel.visible or not car.trunk_open: return
	player.personal_loadout = RULES.normalize(pending_loadout, player.weapon_inventory)
	if not player.can_carry_weapon(player.active_weapon_id):
		player.equip_weapon(String(player.personal_loadout.get("longa", "fists")))
	player._refresh_weapon_ui()
	close_panel()
func recover(include_parked := false) -> bool:
	if not can_recover(include_parked) or player.global_position.distance_to(bay_position())>150 or player.money<RECOVERY_FEE: return false
	player.money -= RECOVERY_FEE
	impounded = false
	_sync_availability()
	car.velocity = Vector2.ZERO
	car.global_position = bay_position()
	car.rotation = PI/2
	car.repair_vehicle()
	car.restore_factory_handling()
	player._refresh_weapon_ui()
	capture_state()
	close_panel()
	return true
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	prompt = Label.new()
	prompt.position = Vector2(24,320)
	prompt.add_theme_font_size_override("font_size",16)
	prompt.add_theme_color_override("font_shadow_color",Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_x",2)
	layer.add_child(prompt)
	var dim := ColorRect.new()
	dim.color = Color(0.025,0.035,0.045,1.0)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.hide()
	panel = PanelContainer.new()
	layer.add_child(panel)
	panel.visibility_changed.connect(func(): dim.visible = panel.visible)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.resized.connect(_fit_live_view)
	panel.minimum_size_changed.connect(func(): _fit_panel.call_deferred())
	get_viewport().size_changed.connect(_fit_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101820")
	style.border_color = Color("34434d")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel",style)
	panel.set_meta("preserve_panel_style",true)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = _text("ARSENAL", "ARSENAL")
	title.add_theme_font_size_override("font_size",17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	message = Label.new()
	message.custom_minimum_size.x = 330
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(message)
	rows = GridContainer.new()
	rows.columns = 4
	rows.add_theme_constant_override("h_separation",8)
	rows.add_theme_constant_override("v_separation",8)
	layout.add_child(rows)
	weapon_stats = Label.new()
	weapon_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_stats.add_theme_font_size_override("font_size", 14)
	layout.add_child(weapon_stats)
	weapon_stats.hide()
	save_button = Button.new()
	save_button.text = _text("EQUIPAR", "EQUIP")
	save_button.set_meta("primary_action",true)
	save_button.pressed.connect(save_loadout)
	heading.add_child(save_button)
	var close := Button.new()
	close.text = _text("Sair [Esc]","Exit [Esc]")
	close.pressed.connect(close_panel)
	heading.add_child(close)
	panel.hide()

func _fit_panel() -> void:
	if not is_instance_valid(panel) or not panel.visible: return
	var width := get_viewport().get_visible_rect().size.x
	var text_scale := float(get_node("/root/SettingsManager").text_scale)
	rows.columns = 2 if width < 1000 * text_scale else 4
	# Reset the old minimum after changing loadout, details, or window size.
	panel.size = Vector2(width - 32, panel.get_combined_minimum_size().y)
	_fit_live_view.call_deferred()

func _fit_live_view() -> void:
	panel.position = Vector2(16, get_viewport().get_visible_rect().size.y - panel.size.y - 16)
	if not is_instance_valid(live_view): return
	# Reserve real viewport space, so no weapon or inspection target sits under UI.
	live_view.offset_bottom = -(panel.size.y + 28)

func _compact_buttons(node: Node) -> void:
	if node is BaseButton:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var compact := node.get_theme_stylebox(state).duplicate() as StyleBox
			compact.content_margin_top = 5
			compact.content_margin_bottom = 5
			compact.content_margin_left = 10
			compact.content_margin_right = 24 if node is OptionButton else 10
			node.add_theme_stylebox_override(state, compact)
	for child in node.get_children(): _compact_buttons(child)

func _refresh_rows(near: bool) -> void:
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	if near:
		for slot in RULES.GROUPS:
			var card := PanelContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.set_meta("preserve_panel_style",true)
			var card_style := StyleBoxFlat.new()
			card_style.bg_color = Color("19242d")
			card_style.set_corner_radius_all(5)
			card_style.set_content_margin_all(8)
			card.add_theme_stylebox_override("panel",card_style)
			rows.add_child(card)
			var line := VBoxContainer.new()
			line.add_theme_constant_override("separation",3)
			card.add_child(line)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(32,18)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var selected_id := String(pending_loadout.get(slot,""))
			var icon_path := "res://assets/art/weapons/icon_"+selected_id+".png"
			if ResourceLoader.exists(icon_path): icon.texture = load(icon_path)
			# The real weapons remain visible above; avoid duplicating large icons.
			icon.hide()
			line.add_child(icon)
			var label := Label.new()
			label.text = {"curta":_text("CURTA","SIDEARM"),"longa":_text("LONGA","LONG GUN"),"corpo":_text("CORPO A CORPO","MELEE"),"granada":_text("GRANADA","GRENADE")}[slot]
			label.custom_minimum_size.x = 110
			label.add_theme_font_size_override("font_size",14)
			label.add_theme_color_override("font_color",Color("a9b4bc"))
			line.add_child(label)
			var choice := OptionButton.new()
			choice.name = "Slot_" + slot
			choice.fit_to_longest_item = false
			choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(choice)
			for id in RULES.GROUPS[slot]:
				if not player.weapon_inventory.get(id,false): continue
				choice.add_item(String(WeaponCatalog.get_weapon(id).get("label",id)))
				choice.set_item_metadata(choice.item_count-1,id)
				if pending_loadout.get(slot,"")==id: choice.select(choice.item_count-1)
			choice.item_selected.connect(func(index: int): set_slot(slot,String(choice.get_item_metadata(index))))
			if choice.item_count == 0:
				var empty_label := _text("Vazio", "Empty")
				choice.add_item(empty_label)
				choice.disabled = true
			choice.tooltip_text = choice.text
			var ammo_label := Label.new()
			ammo_label.text = _ammo_text(String(pending_loadout.get(slot, "")))
			ammo_label.add_theme_font_size_override("font_size", 13)
			ammo_label.custom_minimum_size.x = 150
			line.add_child(ammo_label)
	if not near and player.global_position.distance_to(bay_position())<150:
		var service := Button.new()
		service.text = _text("Recuperar — $50","Recover — $50")
		service.disabled = player.money<RECOVERY_FEE or not can_recover()
		service.pressed.connect(recover)
		rows.add_child(service)
	preload("res://ui/GameStyle.gd").apply(panel,get_node("/root/SettingsManager").text_scale)
	_compact_buttons(panel)
	_fit_panel.call_deferred()
	preload("res://ui/GameStyle.gd").trap_focus.call_deferred(panel)
