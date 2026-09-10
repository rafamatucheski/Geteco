extends Node
const CAR := preload("res://world/harbor/monaliza/MonalizaCar.gd")
const RULES := preload("res://world/harbor/monaliza/PersonalLoadout.gd")
var car: Node2D
var player: Node2D
var garage: Node2D
var panel: PanelContainer
var rows: VBoxContainer
var prompt: Label
var message: Label
var _old_disabled := false
var _tick := 0.0
var _panel_health := 0
var pending_loadout: Dictionary = {}
var live_view: Control
var save_button: Button
var weapon_stats: Label
func _ready() -> void:
	add_to_group("personal_car_manager")
	player = get_parent().get_node("Player")
	garage = get_parent().get_node("Interiors").garage_interior
	car = CAR.new()
	car.name = "Monaliza"
	car.position = get_parent().to_local(bay_position())
	car.rotation = PI/2
	get_parent().add_child(car)
	_apply_state(player.personal_car_state)
	car.unlocked = get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete")
	get_parent().campaign_controller.delivery_finished.connect(_grant)
	_build_ui()
	if car.unlocked: _grant(false)
func bay_position() -> Vector2: return garage.get_vehicle_bay_position()
func restore_from_player() -> void:
	var restored: Dictionary = player.personal_car_state.duplicate(true)
	close_panel()
	car.global_position = bay_position()
	car.rotation = PI/2
	car.repair_vehicle()
	player.personal_car_state = restored
	_apply_state(restored)
	car.unlocked = get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete")
func _apply_state(data: Dictionary) -> void:
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
	player.personal_car_state = {"position":[point.x,point.y],"rotation":car.get_meta("service_safe_rotation",car.rotation),"health":car.health,"broken":car.is_broken,"paint":car.paint_color.to_html()}
func _grant(speak := true) -> void:
	car.unlocked = true
	capture_state()
	if speak:
		get_parent().get_node("CobraCampaign")._message("Maciota",_text("Agora essa é tua. Cuide da nossa Monaliza, ouviu? Ela vai te levar por aí. Dá uma olhada no porta-malas... deixei uma surpresa para você.","She's yours now. Take care of our Monaliza, alright? She'll get you around. Check the trunk... I left you a surprise."))
func _text(pt: String,en: String) -> String: return en if TranslationServer.get_locale().begins_with("en") else pt
func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.15: return
	_tick = 0
	if not is_instance_valid(car): return
	if not car.unlocked:
		car.global_position = bay_position()
		car.velocity = Vector2.ZERO
	var near_rear := player.global_position.distance_to(car.global_position-car.global_transform.x*47)<58
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
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if panel.visible and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_T and prompt.visible and car.unlocked:
		open_panel()
		get_viewport().set_input_as_handled()
func open_panel() -> void:
	if panel.visible: return
	if not car.unlocked or not player.visible or player.is_dead or player.is_in_dialogue or player.is_control_disabled or car.velocity.length()>3: return
	var near := player.global_position.distance_to(car.global_position-car.global_transform.x*47)<58
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
			player.add_weapon_loot(&"shotgun",16)
			player.add_weapon_loot(&"knife",0)
			player.personal_loadout_enabled = true
			player.personal_loadout = {"curta":"pistol","longa":"shotgun","corpo":"knife"}
			player.equip_weapon("shotgun")
			var tutorials := get_tree().get_first_node_in_group("gameplay_tutorials")
			if tutorials != null:
				tutorials.request_context("first_trunk")
				tutorials.request_context("loadout_capacity")
			message.text = _text("SURPRESA DO MACIOTA — Escopeta, 16 cartuchos e faca. Escolha três armas; as demais ficam guardadas.","MACIOTA'S SURPRISE — Shotgun, 16 shells and a knife. Choose three weapons; the rest stays stored.")
		else: message.text = _text("Seu arsenal fica preservado. Armas novas sem espaço entram na reserva; organize aqui antes de sair.","Your arsenal stays safe. New weapons without a free slot enter storage; organize them here before leaving.")
	else: message.text = _text("Recuperar a Monaliza e reparar seus danos custa $250. Seu equipamento é preservado.","Recovering Monaliza and repairing damage costs $250. Your equipment is preserved.")
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
func close_panel() -> void:
	if not panel.visible: return
	panel.hide()
	if is_instance_valid(live_view):
		live_view.free()
		live_view = null
	pending_loadout.clear()
	player.is_control_disabled = _old_disabled
	car.set_trunk_open(false)
	capture_state()
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
	weapon_stats.text = "%s\n%s: %s   ·   %.2f s" % [String(data.get("label", id)), _text("Dano", "Damage"), damage, float(data.get("fire_interval", 0))]
	var magazine := int(data.get("magazine_size", -1))
	if magazine > 0: weapon_stats.text += "\n" + _ammo_text(id)
	weapon_stats.show()
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
func recover() -> bool:
	if not car.unlocked or player.global_position.distance_to(bay_position())>150 or player.money<250 or car.is_driven_by_player: return false
	player.money -= 250
	car.global_position = bay_position()
	car.rotation = PI/2
	car.repair_vehicle()
	car.max_speed = 560
	car.acceleration = 460
	car.turn_speed = 3.1
	car.drift_factor = 0.88
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
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = 18
	panel.offset_bottom = 18
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color("132333")
	style.border_color = Color("ec8b38")
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel",style)
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
	rows = VBoxContainer.new()
	layout.add_child(rows)
	weapon_stats = Label.new()
	weapon_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_stats.add_theme_font_size_override("font_size", 14)
	layout.add_child(weapon_stats)
	weapon_stats.hide()
	save_button = Button.new()
	save_button.text = _text("Salvar", "Save")
	save_button.pressed.connect(save_loadout)
	heading.add_child(save_button)
	var close := Button.new()
	close.text = _text("Sair [Esc]","Exit [Esc]")
	close.pressed.connect(close_panel)
	heading.add_child(close)
	panel.hide()
func _refresh_rows(near: bool) -> void:
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	if near:
		for slot in RULES.GROUPS:
			var line := HBoxContainer.new()
			rows.add_child(line)
			var label := Label.new()
			label.text = {"curta":_text("CURTA","SIDEARM"),"longa":_text("LONGA","LONG GUN"),"corpo":_text("CORPO A CORPO","MELEE"),"granada":_text("GRANADA","GRENADE")}[slot]
			label.custom_minimum_size.x = 110
			line.add_child(label)
			var choice := OptionButton.new()
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(choice)
			for id in RULES.GROUPS[slot]:
				if not player.weapon_inventory.get(id,false): continue
				choice.add_item(String(WeaponCatalog.get_weapon(id).get("label",id)))
				choice.set_item_metadata(choice.item_count-1,id)
				if pending_loadout.get(slot,"")==id: choice.select(choice.item_count-1)
			choice.item_selected.connect(func(index: int): set_slot(slot,String(choice.get_item_metadata(index))))
			if choice.item_count == 0:
				choice.add_item(_text("Não possui", "Not owned"))
				choice.disabled = true
			var ammo_label := Label.new()
			ammo_label.text = _ammo_text(String(pending_loadout.get(slot, "")))
			ammo_label.add_theme_font_size_override("font_size", 13)
			ammo_label.custom_minimum_size.x = 150
			line.add_child(ammo_label)
	if not near and player.global_position.distance_to(bay_position())<150:
		var service := Button.new()
		service.text = _text("Recuperar / reparar — $250","Recover / repair — $250")
		service.disabled = player.money<250 or car.is_driven_by_player
		service.pressed.connect(recover)
		rows.add_child(service)
