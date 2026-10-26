extends Node
## A temporary input/time owner. Inventory remains owned by the field inventory.
const VIEW := preload("res://ui/hud/EquipmentWheelView.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const ICONS := preload("res://systems/inventory/InventoryIcons.gd")
const WORLD_SCALE := 0.2
const WEAPON_GROUPS := [
	["fists"], ["pistol", "magnum"], ["smg"], ["shotgun", "sawed_off"],
	["ak47", "m4a1"], ["hunting_rifle"], ["rpg", "flamethrower", "grenade"],
	["knuckles", "knife", "bat", "axe", "katana"],
]
const FOOD_GROUPS := [
	["first_aid"], ["water", "juice"], ["apple"], ["sandwich"],
	["bread"], ["cereal_bar"], ["yogurt"], ["cooked_fish"],
]
var session
var view: Control
var active := false
var page := 0
var selected := 0
var entries: Array[Dictionary] = []
var _groups: Array[Array] = []
var _choices: Dictionary = {}
var _previous_scale := 1.0
var _applied_scale := 1.0
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _previous_mouse_position := Vector2.ZERO
var _previous_player_lock := false
var _opened_health := 0.0
var _stick := Vector2.ZERO
var _refresh_seconds := 0.0

func configure(owner_session) -> void:
	session = owner_session
	name = "EquipmentWheel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -110
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	view = VIEW.new()
	view.name = "EquipmentWheelView"
	layer.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.hide()
	set_process(false)

func _context_valid() -> bool:
	if not is_instance_valid(session) or not session.ready_for_play: return false
	if not is_instance_valid(session.world) or not is_instance_valid(session.world.gameplay) or not is_instance_valid(session.world.player): return false
	if get_tree().paused or session.modal or session.is_transition_blocked(): return false
	if session.world.gameplay.health <= 0 or session.world.driving.occupied: return false
	if not session.world.gameplay._free_play_ok() or session.world.gameplay.police_surrendering(): return false
	if session.world.player.get_meta("developer_free_flight", false): return false
	if session.world.player.get_meta("player_air_busy", false): return false
	if session.skate != null and session.skate.controls_locked(): return false
	if session.motocross != null and session.motocross.mounted: return false
	if is_instance_valid(session.world.player.ski_controller) and session.world.player.ski_controller.skiing: return false
	if session.passenger_transport != null and session.passenger_transport.riding: return false
	if session.fishing != null and session.fishing.controls_locked(): return false
	if session.amusement_park != null and session.amusement_park.active: return false
	if session.coastal_lookout != null and session.coastal_lookout.active: return false
	if session.arcade != null and session.arcade.active: return false
	if session.upside_world != null and session.upside_world.busy(): return false
	if session.desert != null and session.desert.controls_locked(): return false
	if session.building_entrance != null and session.building_entrance.falling: return false
	if session.service_roofs != null and session.service_roofs.falling: return false
	return true

func open() -> bool:
	if active or not _context_valid() or session.world.player.input_locked: return false
	# RAGE restores its own baseline before we acquire the global clock.
	if is_instance_valid(session.world.gameplay.rage): session.world.gameplay.rage.cancel("equipment_wheel")
	if session.world.camera.mouse_orbit_active(): session.world.camera._end_mouse_orbit()
	_previous_scale = Engine.time_scale
	_applied_scale = minf(_previous_scale, WORLD_SCALE)
	_previous_player_lock = session.world.player.input_locked
	_previous_mouse_mode = Input.mouse_mode
	_previous_mouse_position = get_viewport().get_mouse_position()
	_opened_health = session.world.gameplay.health
	active = true
	page = 0
	selected = 0
	_choices.clear()
	_stick = Vector2.ZERO
	_refresh_seconds = 0.0
	session.world.player.input_locked = true
	Engine.time_scale = _applied_scale
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()
	for i in entries.size():
		if entries[i].id == session.state.equipped_weapon: selected = i
	view.select(selected)
	view.show()
	Input.warp_mouse(view.size * 0.5)
	set_process(true)
	return true

func close(confirm := false) -> void:
	if not active: return
	var valid: bool = confirm and _context_valid() and session.world.gameplay.health >= _opened_health
	var choice: Dictionary = entries[selected].duplicate() if selected >= 0 and selected < entries.size() else {}
	active = false
	set_process(false)
	if is_instance_valid(view): view.hide()
	# Do not undo a clock already acquired by another system.
	if is_equal_approx(Engine.time_scale, _applied_scale): Engine.time_scale = _previous_scale
	var ui_owns_cursor := get_tree() != null and get_tree().paused
	if is_instance_valid(session) and is_instance_valid(session.world) and is_instance_valid(session.world.player):
		ui_owns_cursor = ui_owns_cursor or session.modal or session.is_transition_blocked()
		if not session.modal and not session.is_transition_blocked() and session.world.gameplay.health > 0:
			session.world.player.input_locked = _previous_player_lock
	if not ui_owns_cursor:
		Input.mouse_mode = _previous_mouse_mode
		if _previous_mouse_mode == Input.MOUSE_MODE_VISIBLE: Input.warp_mouse(_previous_mouse_position)
	if confirm and valid and choice.get("enabled", false): _commit(str(choice.id))

func cancel() -> void:
	close(false)

func _exit_tree() -> void:
	cancel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel()

func _process(delta: float) -> void:
	if not active: return
	if not _context_valid() or session.world.gameplay.health < _opened_health:
		cancel()
		return
	# Inventory may change through a mission while the world is still running.
	_refresh_seconds += delta / maxf(Engine.time_scale, 0.001)
	if _refresh_seconds >= 0.25:
		_refresh_seconds = 0.0
		_rebuild()

func handle_input(event: InputEvent) -> bool:
	if not active:
		if event.is_action_pressed("weapon_wheel") and not event.is_echo(): return open()
		return false
	if not _context_valid():
		cancel()
		return true
	if event.is_action_released("weapon_wheel"):
		close(true)
	elif event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		cancel()
	elif event.is_action_pressed("interact") and not event.is_echo():
		toggle_page()
	elif event is InputEventMouseMotion:
		_select_at(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cycle_variant(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cycle_variant(-1)
	elif event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_RIGHT_X: _stick.x = event.axis_value
		elif event.axis == JOY_AXIS_RIGHT_Y: _stick.y = event.axis_value
		if _stick.length() > 0.35: _select_at(view.size * 0.5 + _stick.normalized() * minf(view.size.x, view.size.y) * 0.3)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		selected = posmod(selected + 1, entries.size())
		view.select(selected)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		selected = posmod(selected - 1, entries.size())
		view.select(selected)
	return true

func _select_at(point: Vector2) -> void:
	var next: int = view.selection_at(point)
	if next >= 0 and next != selected:
		selected = next
		view.select(selected)

func toggle_page() -> void:
	if not active: return
	page = 1 - page
	selected = 0
	_rebuild()
	for i in entries.size():
		if entries[i].get("enabled", false):
			selected = i
			break
	view.select(selected)

func cycle_variant(step: int) -> void:
	if selected < 0 or selected >= _groups.size() or _groups[selected].size() < 2: return
	var key := "%d:%d" % [page, selected]
	_choices[key] = posmod(int(_choices.get(key, 0)) + step, _groups[selected].size())
	_rebuild()

func _carried_source(id: String, data: Dictionary) -> Dictionary:
	for container: String in ["pockets", "storage"]:
		for i in data.get(container, []).size():
			if data[container][i].id == id: return {"source": container, "index": i}
	return {}

func _rebuild() -> void:
	var economy = session.state.economy
	var data: Dictionary = economy.grid_snapshot()
	var definitions: Array = WEAPON_GROUPS if page == 0 else FOOD_GROUPS
	entries.clear()
	_groups.clear()
	for i in definitions.size():
		var available: Array = []
		for id: String in definitions[i]:
			if page == 0:
				if session.state.owns_weapon(id) and (economy.can_carry_weapon(id) or not _carried_source("weapon:" + id, data).is_empty()): available.append(id)
			elif not _carried_source(id, data).is_empty(): available.append(id)
		_groups.append(available)
		var key := "%d:%d" % [page, i]
		if not _choices.has(key) and page == 0 and available.has(session.state.equipped_weapon): _choices[key] = available.find(session.state.equipped_weapon)
		var cursor := posmod(int(_choices.get(key, 0)), maxi(1, available.size()))
		_choices[key] = cursor
		var id: String = available[cursor] if not available.is_empty() else definitions[i][0]
		var enabled := not available.is_empty()
		var detail := ""
		var count_label := ""
		var label := ""
		var icon_id := id
		if page == 0:
			label = str(CATALOG.WEAPONS[id].label)
			enabled = enabled and session.state.weapons_allowed() and not (economy.grid_handbag() and id in GRID.LONG)
			var ammo: Dictionary = session.state.get_ammo(id)
			detail = "%d / %d" % [maxi(0, int(ammo.get("magazine", 0))), maxi(0, int(ammo.get("reserve", 0)))] if int(ammo.get("magazine", -1)) >= 0 else _text("Corpo a corpo", "Melee")
			if not session.state.weapons_allowed(): detail = _text("Armas guardadas nesta área", "Weapons restricted in this area")
			elif economy.grid_handbag() and id in GRID.LONG: detail = _text("Solte a mala para equipar", "Drop the bag to equip")
		else:
			var spec: Dictionary = GRID.spec(id)
			label = String(TranslationServer.translate(str(spec.label)))
			icon_id = str(spec.icon)
			var amount := 0
			for container: String in ["pockets", "storage"]:
				for stack: Dictionary in data.get(container, []):
					if stack.id == id: amount += int(stack.amount)
			count_label = "×%d" % amount
			detail = _text("+%d de vida", "+%d health") % int(spec.get("heal", 0))
			if session.world.gameplay.health >= 100:
				enabled = false
				detail = _text("Vida cheia", "Health full")
		if available.is_empty(): detail = _text("Não está com você", "Not carried")
		elif available.size() > 1: count_label += ("  " if not count_label.is_empty() else "") + "%d/%d" % [cursor + 1, available.size()]
		var slot_label: String = str(CATALOG.WEAPONS[id].short_label) if page == 0 else label
		entries.append({"id": id, "label": label, "slot_label": slot_label, "detail": detail, "icon": ICONS.get_icon(icon_id), "enabled": enabled, "count_label": count_label})
	var controls := get_node("/root/GameInput")
	view.configure_view(entries, selected, page, {"hold": controls.hint("weapon_wheel"), "switch": controls.hint("interact"), "cancel": controls.hint("pause_game"), "subcycle": _text("Rolagem: variar item", "Scroll: cycle item")})

func _commit(id: String) -> void:
	if not _context_valid() or session.world.player.input_locked: return
	if page == 0:
		if not session.state.weapons_allowed(): return
		if session.state.economy.can_carry_weapon(id):
			if session.world.gameplay.equip_slot(id): session.save_game()
		else:
			var source := _carried_source("weapon:" + id, session.state.economy.grid_snapshot())
			if not source.is_empty():
				session.field_inventory.equip(source.source, source.index)
				if session.state.equipped_weapon == id: session.world.gameplay.equip_slot(id)
	else:
		var source := _carried_source(id, session.state.economy.grid_snapshot())
		if not source.is_empty(): session.field_inventory.consume(source.source, source.index)

func _text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
