extends Node3D
## Optional Casa 1 annex and cellar controller.
##
## The house remains owned by TruckersVillageHomes. This node only attaches a
## narrow rear annex, the cellar below it and the movable access mechanisms.
## NativeRegion and the house shell consume physical_cut_spec() so the player
## walks continuously through the authored stairs. The transfer actions remain
## as a safe fallback for isolated scene previews that do not install the cuts.

signal state_changed
signal physical_cut_requested(spec: Dictionary)
signal camera_transfer_started(to_tunnel: bool)

const TUNNEL := preload("res://gameplay/urban_v1/SecretTunnel3D.gd")
const SKI_EXIT := preload("res://gameplay/urban_v1/fort/MountainFortExit3D.gd")
const FORT_PLACE := preload("res://gameplay/urban_v1/MountainFortPlace.gd")
const UNDERGROUND_ENVIRONMENT := preload("res://gameplay/urban_v1/SecretUndergroundEnvironment.gd")
const HOME_INDEX := 0
const DEFAULT_KEYPAD_CODE := "1951"
# Cofre do setor lacrado: um dígito por indício (crachá, relatório, foto, fita),
# na ordem em que aparecem no código.
const VAULT_CODE := "3194"
const VAULT_DIGITS := [
	{"id":"lab_access_badge","kind":"lab","digit":0,"local":Vector3(-2.9,.04,-6.3),"label":"Examinar crachá",
		"text":"No verso do crachá, riscado a caneta: 3."},
	{"id":"lab_power_report","kind":"lab","digit":1,"local":Vector3(-3.45,.04,-6.3),"label":"Ler relatório de energia",
		"text":"Relatório de energia do setor lacrado. Na margem, circulado: 1."},
	{"id":"lab_incident_photo","kind":"lab","digit":2,"local":Vector3(-4.0,.04,-6.3),"label":"Examinar foto do incidente",
		"text":"Foto do incidente. No canto, à mão: 9."},
	{"id":"audio_sealed_sector","kind":"audio","digit":3,"local":Vector3(3.4,.04,-4.1),"label":"Ouvir fita rotulada",
		"text":"A fita chia: \"...a última porta... o quarto número é 4. Depois disso, não volte.\""},
]
const ACTION_PREFIX := "truckers_village_secret_"
const INTERACTION_REACH := 1.65
const UNDERGROUND_LAYER := 1 << 18

# Casa 1 local coordinates. The annex occupies the existing central opening in
# the rear fence and does not add or clone any furniture in the main room.
const SURFACE_DOOR_LOCAL := Vector3(0.65,1.14,-4.28)
const SURFACE_ACTION_LOCAL := Vector3(0.65,.04,-3.15)
const SURFACE_RETURN_LOCAL := Vector3(0.65,.04,-2.75)
const ANNEX_CENTER_LOCAL := Vector3(0,0,-7.05)
const ANNEX_SIZE := Vector3(3.15,2.75,5.25)
const STAIR_TOP_LOCAL := Vector3(0,.02,-4.75)
const STAIR_BOTTOM_LOCAL := Vector3(0,-4.28,-9.65)

const CELLAR_ORIGIN_LOCAL := Vector3(0,-4.35,-6.55)
const CELLAR_INSIDE := Rect2(-4.35,-4.15,8.7,8.3)
const CELLAR_SPAWN := Vector3(0,.04,2.85)
const CELLAR_STAIR_POINT := Vector3(0,.04,-3.02)
const CELLAR_SHELF_POINT := Vector3(-3.05,.04,.15)
const SHELF_CENTER := Vector3(-4.06,1.18,.15)
const KEYPAD_CENTER := Vector3(-4.25,1.30,.15)
const TUNNEL_RETURN := Vector3(-2.72,.04,.15)

var session
var village: Node3D
var homes: Node3D
var home: Node3D
var progression
var tunnel: Node3D
var ski_exit: Node3D
var cellar_root: Node3D
var cellar_camera: Camera3D
var cellar_ceiling: Node3D
var surface_door: Node3D
var surface_door_body: StaticBody3D
var shelf_pivot: Node3D
var shelf_body: StaticBody3D
var tunnel_door: Node3D
var tunnel_door_body: StaticBody3D
var solids: Array[StaticBody3D] = []

var _region_active := true
var _physical_cut_ready := false
var _surface_open := false
var _shelf_revealed := false
var _keypad_buffer := ""
var _keypad_code := DEFAULT_KEYPAD_CODE
var _keypad_vault := false
var _curtain_layer: CanvasLayer
var _cellar_occupied := false
var _surface_camera: Camera3D
var _transfer_busy := false
var _materials: Dictionary = {}
var _batches: Dictionary = {}


func configure(owner_session, village_visuals: Node3D, network_progression, tunnel_stage: Node3D = null) -> bool:
	session = owner_session
	village = village_visuals
	progression = network_progression
	if session == null or not is_instance_valid(village) or village.get("homes") == null:
		push_error("SecretPassage requires the production village and session.")
		return false
	homes = village.homes
	if homes.get("homes") == null or homes.homes.size() <= HOME_INDEX:
		push_error("SecretPassage could not resolve Casa 1.")
		return false
	home = homes.homes[HOME_INDEX].root
	if not is_instance_valid(home):
		push_error("SecretPassage Casa 1 root is invalid.")
		return false
	name = "TruckersVillageSecretPassage"
	_build_annex()
	_build_cellar()
	_flush_batches()
	_apply_underground_layer(cellar_root)
	_build_camera()
	if is_instance_valid(tunnel_stage):
		tunnel = tunnel_stage
	else:
		tunnel = TUNNEL.new()
		# UrbanOperations is a Node, so the passage normally has an identity world
		# transform. Top-level also protects the remote underground stage if the
		# manager is later mounted below a transformed visual owner.
		tunnel.top_level = true
		add_child(tunnel)
		tunnel.configure(session)
	# A saída do forte vive no mundo, não sob a passagem: esta some da tela quando a
	# região de Harbor é suspensa, e a laje precisa aparecer na serra.
	ski_exit = SKI_EXIT.new()
	session.world.add_child(ski_exit)
	ski_exit.configure(session)
	_apply_saved_state(true)
	set_process(true)
	physical_cut_requested.emit(physical_cut_spec())
	return true


func set_keypad_code(value: String) -> bool:
	if value.length() < 3 or value.length() > 8 or not value.is_valid_int():
		return false
	_keypad_code = value
	return true


func set_physical_cut_ready(value: bool) -> void:
	_physical_cut_ready = value


func refresh_state() -> void:
	_apply_saved_state(true)
	_sync_house_authorization()


func physical_cut_spec() -> Dictionary:
	if not is_instance_valid(home):
		return {}
	var stair_middle := (STAIR_TOP_LOCAL+STAIR_BOTTOM_LOCAL)*.5
	return {
		"house_index":HOME_INDEX,
		"home_root":home,
		"rear_wall_opening_local":AABB(Vector3(-.18,.02,-4.55),Vector3(1.66,2.38,.42)),
		"floor_opening_local":Rect2(Vector2(-1.42,-9.95),Vector2(2.84,5.55)),
		"stair_center_global":home.to_global(stair_middle),
		"stair_top_global":home.to_global(STAIR_TOP_LOCAL),
		"stair_bottom_global":home.to_global(STAIR_BOTTOM_LOCAL),
		"cellar_bounds_local":CELLAR_INSIDE,
	}


func set_region_active(value: bool) -> void:
	_region_active = value
	visible = value
	for body in solids:
		body.collision_layer = 1 if value else 0
	if not value:
		_set_cellar_occupied(false)
		# Keep the destination floor alive while visiting a connected sewer so
		# FullSession can validate the underground return point on exit.
		if is_instance_valid(tunnel): tunnel.set_enabled((_route_active("route_harbor_sewer") and session.state.place_id == "harbor_sewer") or (_vault_unlocked() and session.state.place_id == "mountain_fort"))
	set_process(value)


func nearest_action() -> Dictionary:
	# Dentro do forte a única ação é o terminal do posto de guarda.
	if session != null and session.state.place_id == "mountain_fort":
		var fort = session.room
		if _transfer_busy: return {}
		if is_instance_valid(fort) and fort.get("operation") != null and is_instance_valid(fort.operation):
			return fort.operation.nearest_action()
		return {}
	var ski_action := _ski_exit_action()
	if not ski_action.is_empty(): return ski_action
	var story_action := _maciota_story_action()
	if not story_action.is_empty():
		return story_action
	if not _walking() or _transfer_busy:
		return {}
	var player: Node3D = session.world.player
	var point := player.global_position
	if is_instance_valid(tunnel) and tunnel.contains(point):
		if not _physical_cut_ready and point.distance_to(tunnel.exit_global()) <= INTERACTION_REACH:
			return _action("return_cellar","Voltar ao porão")
		if _headquarters_discovered() and point.distance_to(tunnel.network_console_global()) <= 2.0:
			if not _power_active("power_main"): return _action("power_main","Restaurar quadro principal")
			if not _power_active("power_drainage"): return _action("power_drainage","Energizar rede de drenagem")
			if not _route_active("route_village_house"): return _action("route_village","Registrar acesso da Vila")
			if not _route_active("route_harbor_sewer"): return _action("route_sewer","Liberar rota do esgoto")
			if _sealed_sector_discovered() and not _power_active("power_sealed_sector"): return _action("power_sealed","Energizar setor lacrado")
		if _route_active("route_harbor_sewer") and point.distance_to(tunnel.route_console_global()) <= 2.0:
			return _action("travel_sewer","Viajar pelo esgoto")
		var digit_action := _vault_digit_action(point)
		if not digit_action.is_empty(): return digit_action
		if _sealed_sector_discovered() and point.distance_to(tunnel.vault_console_global()) <= 1.8:
			if _vault_unlocked(): return _action("travel_fort","Atravessar o cofre")
			return _action("vault_keypad","Usar teclado do cofre")
		return {}
	if _in_cellar(point):
		if point.distance_to(_cellar_global(CELLAR_STAIR_POINT)) <= INTERACTION_REACH:
			if _physical_cut_ready:
				return {}
			return _action("return_house","Subir")
		if point.distance_to(_cellar_global(CELLAR_SHELF_POINT)) <= INTERACTION_REACH:
			if not _shelf_revealed and not _keypad_unlocked():
				return _action("reveal_shelf","Abrir estante")
			if not _keypad_unlocked():
				return _action("keypad","Usar teclado")
			if _physical_cut_ready:
				return {}
			return _action("enter_tunnel","Entrar no túnel")
		if not _has_keypad_clue("keypad_radio_frequency") and point.distance_to(_cellar_global(Vector3(-1.2,.04,3.05))) <= INTERACTION_REACH:
			return _action("inspect_radio","Examinar rádio")
		if not _has_keypad_clue("keypad_service_stamp") and point.distance_to(_cellar_global(Vector3(2.7,.04,2.2))) <= INTERACTION_REACH:
			return _action("inspect_crate","Examinar caixa")
		return {}
	if not _dossier_received():
		return {}
	if point.distance_to(home.to_global(SURFACE_ACTION_LOCAL)) <= INTERACTION_REACH:
		if not _house_discovered():
			return _action("discover_cellar","Abrir acesso ao porão")
		if _physical_cut_ready:
			return {}
		return _action("enter_cellar","Descer ao porão")
	return {}


func perform(target: String) -> bool:
	if not target.begins_with(ACTION_PREFIX):
		return false
	var expected := nearest_action()
	if expected.is_empty() or str(expected.get("target","")) != target:
		return false
	if target.ends_with("fort_open_door"): return session.room.operation.perform(target)
	if target.ends_with("fort_ascend"):
		_ascend_to_ski()
		return true
	if target.ends_with("ski_enter"):
		_enter_fort_from_ski()
		return true
	match target.trim_prefix(ACTION_PREFIX):
		"receive_dossier":
			if progression == null or not progression.receive_dossier():
				return false
			progression.collect_fragment("map_village_fold")
			progression.discover_keypad_clue("keypad_invoice")
			_sync_house_authorization()
			_emit_state_changed()
			session.show_dialogue([
				{"speaker":"Maciota","message":"Você ficou quando seria mais fácil ir embora. Vicente deixou uma pasta comigo antes de sumir. Pediu que eu guardasse até você estar pronto."},
				{"speaker":"Dante","message":"Por que só agora?"},
				{"speaker":"Maciota","message":"Porque essa pista leva à Vila e tem coisa ali que alguém quis esconder. Daqui pra frente, a escolha é tua."},
			])
			return true
		"discover_cellar":
			if progression == null or not progression.discover_house():
				return false
			_surface_open = true
			progression.discover_keypad_clue("keypad_house_plaque")
			progression.collect_fragment("map_drainage_grid")
			_emit_state_changed()
			_show_message("Acesso ao porão liberado.")
			return true
		"enter_cellar":
			_surface_open = true
			if not _physical_cut_ready:
				_transfer_to_cellar()
			return true
		"return_house":
			if not _physical_cut_ready:
				_transfer_to_house()
			return true
		"reveal_shelf":
			_shelf_revealed = true
			return true
		"inspect_radio":
			if progression.discover_keypad_clue("keypad_radio_frequency"):
				progression.collect_fragment("map_service_tunnel")
				_emit_state_changed()
				_show_message("Uma frequência anotada foi guardada na pasta.")
			return true
		"inspect_crate":
			if progression.discover_keypad_clue("keypad_service_stamp"):
				progression.collect_fragment("map_pump_station")
				_emit_state_changed()
				_show_message("O carimbo de manutenção completa o código.")
			return true
		"keypad":
			if progression == null or not progression.can_unlock_keypad():
				_show_message("Faltam pistas para confirmar o código.")
				return true
			_open_keypad()
			return true
		"enter_tunnel":
			_transfer_to_tunnel()
			return true
		"return_cellar":
			_transfer_from_tunnel()
			return true
		"power_main":
			if progression.activate_power_node("power_main"):
				progression.collect_fragment("map_power_branch")
				_emit_state_changed()
				_show_message("O quadro principal voltou a responder.")
			return true
		"power_drainage":
			if progression.activate_power_node("power_drainage"):
				_emit_state_changed()
				_show_message("A rede de drenagem recebeu energia.")
			return true
		"route_village":
			if progression.activate_route("route_village_house"):
				_emit_state_changed()
				_show_message("Acesso da Vila registrado na pasta.")
			return true
		"route_sewer":
			if progression.activate_route("route_harbor_sewer"):
				_emit_state_changed()
				_show_message("Uma passagem para o esgoto foi liberada.")
			return true
		"travel_sewer":
			_travel_to_sewer()
			return true
		"power_sealed":
			if progression.activate_power_node("power_sealed_sector"):
				tunnel.set_sealed_access(true,true)
				_emit_state_changed()
				_show_message("O quadro sobe. O portão do setor lacrado destrava.")
			return true
		"vault_keypad":
			_open_vault_keypad()
			return true
		"travel_fort":
			_travel_to_fort()
			return true
	var suffix := target.trim_prefix(ACTION_PREFIX)
	if suffix.begins_with("digit_"): return _collect_vault_digit(int(suffix.trim_prefix("digit_")))
	return false


func _process(delta: float) -> void:
	if not _region_active or session == null or not is_instance_valid(home):
		return
	_animate_access(delta)
	if not is_instance_valid(session.world.player):
		return
	var player: Node3D = session.world.player
	var in_tunnel: bool = is_instance_valid(tunnel) and bool(tunnel.contains(player.global_position))
	if _keypad_unlocked() and in_tunnel and not tunnel.visible:
		tunnel.set_enabled(true)
	# The tunnel is our child and processes after this controller. Preserve the
	# cellar camera for this one handoff frame so SecretTunnel3D records it as
	# its return camera instead of accidentally recording the exterior camera.
	_set_cellar_occupied(_in_cellar(player.global_position) and not in_tunnel,not in_tunnel)
	if _cellar_occupied:
		_update_cellar_camera(player.global_position)
	if not _headquarters_discovered() and _keypad_unlocked() and in_tunnel \
		and player.global_position.distance_to(tunnel.headquarters_global()) < 8.0:
		if progression.discover_headquarters():
			_emit_state_changed()
			_show_message("Quartel descoberto.")
	if _headquarters_discovered() and not _sealed_sector_discovered() and in_tunnel \
		and player.global_position.distance_to(tunnel.sealed_sector_global()) < 3.0:
		if progression.discover_sealed_sector():
			progression.collect_fragment("map_sealed_annex")
			_emit_state_changed()
			_show_message("O setor lacrado foi marcado na pasta.")


func _walking() -> bool:
	return session != null and session.ready_for_play \
		and session.state.region_id == "harbor" and session.state.place_id.is_empty() \
		and session.world.gameplay.health > 0 and not session.world.driving.occupied \
		and is_instance_valid(session.world.player)


func _maciota_story_action() -> Dictionary:
	if session == null or progression == null or _dossier_received() or not session.ready_for_play:
		return {}
	if session.state.region_id != "harbor" or session.state.place_id != "maciota":
		return {}
	if not session.state.campaign.snapshot().get("completed",[]).has("cobra_finale"):
		return {}
	if session.world.gameplay.health <= 0 or session.world.driving.occupied:
		return {}
	if not session.state.campaign.active_id.is_empty():
		return {}
	var room = session.room
	if not is_instance_valid(room) or room.get("interaction_points") == null or not room.interaction_points.has("maciota"):
		return {}
	if session.world.player.global_position.distance_to(room.interaction_points.maciota) > 2.0:
		return {}
	return _action("receive_dossier","Conversar")


func _action(suffix: String,label: String) -> Dictionary:
	# FullSession dispatches this through the remappable `interact` action. The
	# keypad itself uses normal focused UI buttons and ui_cancel/ui_accept.
	return {"id":"urban_v1","target":ACTION_PREFIX+suffix,"label":label}


func _open_keypad() -> void:
	_keypad_vault = false
	_show_keypad()


func _open_vault_keypad() -> void:
	if not _power_active("power_sealed_sector"):
		_show_message("O teclado está sem energia.")
		return
	var missing := 4-_vault_digits_found()
	if missing > 0:
		_show_message("Faltam %d dígitos do código. Procure no quartel: %s"%[missing,_vault_hint()])
		return
	_keypad_vault = true
	_show_keypad()


func _show_keypad() -> void:
	if session == null or not session.has_method("_menu") or session.get("column") == null:
		return
	_keypad_buffer = ""
	session._menu("Teclado")
	var display := Label.new()
	display.name = "KeypadEntry"
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display.add_theme_font_size_override("font_size",28)
	display.text = _keypad_mask()
	session.column.add_child(display)
	var grid := GridContainer.new()
	grid.name = "NumericKeypad"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	session.column.add_child(grid)
	var first: Button
	for value in ["1","2","3","4","5","6","7","8","9","⌫","0","OK"]:
		var button := Button.new()
		button.text = value
		button.custom_minimum_size = Vector2(86,42)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_keypad_press.bind(value,display))
		grid.add_child(button)
		if first == null: first = button
	if first != null: first.grab_focus.call_deferred()
	if session.has_method("_button"):
		session._button("Cancelar",session.close_menu)


func _keypad_press(value: String,display: Label) -> void:
	if value == "⌫":
		_keypad_buffer = _keypad_buffer.left(maxi(0,_keypad_buffer.length()-1))
	elif value == "OK":
		_submit_keypad()
		return
	elif _keypad_buffer.length() < _active_code().length():
		_keypad_buffer += value
	if is_instance_valid(display):
		display.text = _keypad_mask()


func _keypad_mask() -> String:
	var marks := PackedStringArray()
	for index in _active_code().length():
		marks.append("●" if index < _keypad_buffer.length() else "•")
	return " ".join(marks)


func _active_code() -> String:
	return VAULT_CODE if _keypad_vault else _keypad_code


func _submit_keypad() -> void:
	if _keypad_vault:
		_submit_vault_keypad()
		return
	if _keypad_buffer != _keypad_code:
		_keypad_buffer = ""
		_show_message("Código incorreto.")
		var display = session.column.get_node_or_null("KeypadEntry") if session != null else null
		if display is Label: display.text = _keypad_mask()
		return
	if progression == null or not progression.unlock_keypad():
		_show_message("Teclado bloqueado.")
		return
	_shelf_revealed = true
	if session.has_method("close_menu"): session.close_menu()
	if is_instance_valid(tunnel): tunnel.set_enabled(true)
	_emit_state_changed()
	_show_message("Passagem liberada.")


func _submit_vault_keypad() -> void:
	if _keypad_buffer != VAULT_CODE:
		_keypad_buffer = ""
		_show_message("Código incorreto.")
		var display = session.column.get_node_or_null("KeypadEntry") if session != null else null
		if display is Label: display.text = _keypad_mask()
		return
	if progression == null or not progression.unlock_final_door():
		_show_message("O cofre continua trancado.")
		return
	if session.has_method("close_menu"): session.close_menu()
	tunnel.set_vault_open(true,true)
	_emit_state_changed()
	_show_message("A porta do cofre se abre.")


func _transfer_to_cellar() -> void:
	if _transfer_busy: return
	_transfer_busy = true
	_surface_camera = get_viewport().get_camera_3d()
	var player: Node3D = session.world.player
	_lock_player(true)
	_set_player_position(_cellar_global(CELLAR_SPAWN))
	_set_cellar_occupied(true)
	_lock_player(false)
	_transfer_busy = false


func _transfer_to_house() -> void:
	if _transfer_busy: return
	_transfer_busy = true
	_lock_player(true)
	_set_player_position(home.to_global(SURFACE_RETURN_LOCAL))
	_set_cellar_occupied(false)
	_lock_player(false)
	_transfer_busy = false


func _transfer_to_tunnel() -> void:
	if _transfer_busy or not _keypad_unlocked() or not is_instance_valid(tunnel): return
	_transfer_busy = true
	camera_transfer_started.emit(true)
	_lock_player(true)
	tunnel.set_enabled(true)
	_set_player_position(tunnel.entry_global())
	# SecretTunnel3D claims the current cellar camera as its return camera on
	# the following process tick. Keeping this deferred avoids two camera owners.
	_finish_tunnel_transfer.call_deferred()


func _finish_tunnel_transfer() -> void:
	_lock_player(false)
	_transfer_busy = false


func _transfer_from_tunnel() -> void:
	if _transfer_busy or not is_instance_valid(tunnel): return
	_transfer_busy = true
	camera_transfer_started.emit(false)
	_lock_player(true)
	_set_player_position(_cellar_global(TUNNEL_RETURN))
	_finish_tunnel_transfer.call_deferred()


func _set_player_position(point: Vector3) -> void:
	var player: Node3D = session.world.player
	if player.has_method("teleport"): player.teleport(point)
	else: player.global_position = point
	if player is CharacterBody3D: player.velocity = Vector3.ZERO


func _lock_player(value: bool) -> void:
	if session != null and is_instance_valid(session.world.player):
		session.world.player.input_locked = value


func _in_cellar(point: Vector3) -> bool:
	if not is_instance_valid(cellar_root): return false
	var local := cellar_root.to_local(point)
	return CELLAR_INSIDE.has_point(Vector2(local.x,local.z)) and local.y > -.8 and local.y < 3.2


func _set_cellar_occupied(value: bool,restore_surface_camera := true) -> void:
	if _cellar_occupied == value: return
	_cellar_occupied = value
	if is_instance_valid(cellar_ceiling): cellar_ceiling.visible = not value
	if homes != null and homes.homes.size() > HOME_INDEX:
		homes.homes[HOME_INDEX].roof.visible = not value
		homes.homes[HOME_INDEX].upper.visible = not value
	if value:
		_enable_player_underground_layer()
		if not is_instance_valid(_surface_camera): _surface_camera = get_viewport().get_camera_3d()
		cellar_camera.make_current()
		if session.world.player.get("camera") != null: session.world.player.camera = cellar_camera
	elif restore_surface_camera and is_instance_valid(_surface_camera):
		_surface_camera.make_current()
		if session != null and is_instance_valid(session.world.player) and session.world.player.get("camera") != null:
			session.world.player.camera = _surface_camera


func _update_cellar_camera(point: Vector3) -> void:
	var local := cellar_root.to_local(point)
	var focus := Vector3(clampf(local.x,-.85,.85),.58,clampf(local.z,-.65,.65))
	cellar_camera.global_position = cellar_root.to_global(focus+Vector3(0,10.8,8.6))
	cellar_camera.look_at(cellar_root.to_global(focus),Vector3.UP)


func _animate_access(delta: float) -> void:
	if is_instance_valid(surface_door):
		surface_door.rotation.y = move_toward(surface_door.rotation.y,-PI*.5 if _surface_open else 0.0,delta*2.8)
	if is_instance_valid(shelf_pivot):
		shelf_pivot.rotation.y = move_toward(shelf_pivot.rotation.y,-PI*.5 if (_shelf_revealed or _keypad_unlocked()) else 0.0,delta*2.4)
	if is_instance_valid(tunnel_door):
		tunnel_door.rotation.y = move_toward(tunnel_door.rotation.y,-PI*.5 if _keypad_unlocked() else 0.0,delta*2.6)


func _apply_saved_state(immediate: bool) -> void:
	_surface_open = _house_discovered()
	_shelf_revealed = _keypad_unlocked()
	if immediate:
		surface_door.rotation.y = -PI*.5 if _surface_open else 0.0
		shelf_pivot.rotation.y = -PI*.5 if _shelf_revealed else 0.0
		tunnel_door.rotation.y = -PI*.5 if _keypad_unlocked() else 0.0
	if is_instance_valid(tunnel):
		tunnel.set_enabled(_keypad_unlocked() and tunnel.contains(session.world.player.global_position))
		tunnel.set_sealed_access(_power_active("power_sealed_sector"))
		tunnel.set_vault_open(_vault_unlocked())
	_sync_house_authorization()


func _sync_house_authorization() -> void:
	if is_instance_valid(homes): homes.set_meta("secret_house_authorized",_dossier_received())


func _has_keypad_clue(id: String) -> bool:
	return progression != null and progression.has_keypad_clue(id)


func _power_active(id: String) -> bool:
	return progression != null and progression.has_power_node(id)


func _route_active(id: String) -> bool:
	return progression != null and progression.has_route(id)


func _vault_digit_action(point: Vector3) -> Dictionary:
	if not _headquarters_discovered(): return {}
	var best := -1
	var best_distance := 1.3
	for index in VAULT_DIGITS.size():
		var entry: Dictionary = VAULT_DIGITS[index]
		if _vault_digit_found(entry): continue
		var distance := point.distance_to(tunnel.to_global(tunnel.HQ_CENTER+entry.local))
		if distance <= best_distance:
			best = index
			best_distance = distance
	if best < 0: return {}
	return _action("digit_%d"%best,str(VAULT_DIGITS[best].label))


func _collect_vault_digit(index: int) -> bool:
	if index < 0 or index >= VAULT_DIGITS.size(): return false
	var entry: Dictionary = VAULT_DIGITS[index]
	var added: bool = progression.discover_lab_clue(entry.id) if entry.kind == "lab" else progression.discover_audio_log(entry.id)
	if not added: return false
	_emit_state_changed()
	_show_message(str(entry.text)+"  Código: "+_vault_code_progress())
	return true


func _vault_digit_found(entry: Dictionary) -> bool:
	if progression == null: return false
	return progression.has_lab_clue(entry.id) if entry.kind == "lab" else progression.data.audio_logs.has(entry.id)


func _vault_digits_found() -> int:
	var count := 0
	for entry in VAULT_DIGITS:
		if _vault_digit_found(entry): count += 1
	return count


func _vault_code_progress() -> String:
	var marks := PackedStringArray()
	for entry in VAULT_DIGITS:
		marks.append(VAULT_CODE[int(entry.digit)] if _vault_digit_found(entry) else "•")
	return " ".join(marks)


func _vault_hint() -> String:
	var parts := PackedStringArray()
	for entry in VAULT_DIGITS:
		if not _vault_digit_found(entry): parts.append(str(entry.label).to_lower())
	return ", ".join(parts)


func _vault_unlocked() -> bool:
	return progression != null and bool(progression.data.get("final_door_unlocked",false))


func _ski_exit_action() -> Dictionary:
	if session == null or not is_instance_valid(ski_exit) or _transfer_busy or not _vault_unlocked(): return {}
	if not session.ready_for_play or session.state.region_id != "mountain" or not session.state.place_id.is_empty(): return {}
	if session.world.driving.occupied or session.world.gameplay.health <= 0: return {}
	if session.world.player.global_position.distance_to(ski_exit.interaction_global()) > 1.9: return {}
	return _action("ski_enter","Abrir passagem de pedra")


## Subida do forte até o esqui: o elevador fecha, a tela escurece, o jogador vai para a
## serra e a laje de pedra se arrasta atrás dele.
func _ascend_to_ski() -> void:
	if _transfer_busy or session == null or session.state.place_id != "mountain_fort": return
	var fort = session.room
	if not fort.operation.can_ascend():
		_show_message("O elevador não parte com a sala sob fogo.")
		return
	_transfer_busy = true
	_lock_player(true)
	fort.model.set_lift_open(true)
	await get_tree().create_timer(1.1).timeout
	await _curtain(1.0,.7,"Subindo...")
	_lock_player(false)
	var from_mountain: bool = session.state.region_id == "mountain"
	await get_tree().create_timer(2.2).timeout
	var left: bool = await session.leave_place()
	if left and not from_mountain:
		if session.controller.travel("mountain",ski_exit.arrival_global()):
			while session.controller.travel_busy: await get_tree().process_frame
	if left: await _emerge_from_slab()
	else: await _curtain(0.0,.5)
	_transfer_busy = false


func _enter_fort_from_ski() -> void:
	if _transfer_busy or not is_instance_valid(ski_exit): return
	_transfer_busy = true
	_lock_player(true)
	ski_exit.set_open(true)
	await get_tree().create_timer(3.0).timeout
	await _curtain(1.0,.6,"")
	_lock_player(false)
	FORT_PLACE.next_return = ski_exit.arrival_global()
	var entered: bool = await session.enter_place("mountain_fort",false,"secret_network")
	FORT_PLACE.next_return = Vector3.INF
	if entered:
		session.return_point = ski_exit.arrival_global()
		session.access_id = "secret_network"
		session.save_game()
	ski_exit.set_open(false,false)
	await _curtain(0.0,.6)
	_transfer_busy = false


func _emerge_from_slab() -> void:
	ski_exit.activate_now()
	ski_exit.set_open(true,false)
	await _curtain(0.0,.9)
	await get_tree().create_timer(3.4).timeout
	ski_exit.set_open(false)


## Cortina preta com texto opcional (fade em segundos).
func _curtain(alpha: float,seconds: float,text := "") -> void:
	if _curtain_layer == null:
		_curtain_layer = CanvasLayer.new()
		_curtain_layer.layer = 90
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.color = Color.BLACK
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.modulate.a = 0.0
		_curtain_layer.add_child(fill)
		var label := Label.new()
		label.name = "Text"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",30)
		fill.add_child(label)
		session.add_child(_curtain_layer)
	var fill_node: ColorRect = _curtain_layer.get_node("Fill")
	fill_node.get_node("Text").text = text
	var tween := create_tween()
	tween.tween_property(fill_node,"modulate:a",alpha,seconds)
	await tween.finished


func _travel_to_fort() -> void:
	if session == null or not _vault_unlocked() or not is_instance_valid(tunnel): return
	var return_point: Vector3 = tunnel.vault_arrival_global()
	tunnel.set_return_camera(session.world.camera)
	var entered: bool = await session.enter_place("mountain_fort",false,"secret_network")
	if not entered: return
	session.return_point = return_point
	session.access_id = "secret_network"
	session.save_game()


func _travel_to_sewer() -> void:
	if session == null or not _route_active("route_harbor_sewer") or not is_instance_valid(tunnel): return
	var return_point: Vector3 = tunnel.route_arrival_global()
	tunnel.set_return_camera(session.world.camera)
	var entered: bool = await session.enter_place("harbor_sewer",false,"secret_network")
	if not entered: return
	session.return_point = return_point
	session.access_id = "secret_network"
	session.save_game()


func _dossier_received() -> bool:
	return progression != null and bool(progression.data.get("dossier_received",false))


func _house_discovered() -> bool:
	return progression != null and bool(progression.data.get("house_discovered",false))


func _keypad_unlocked() -> bool:
	return progression != null and bool(progression.data.get("keypad_unlocked",false))


func _headquarters_discovered() -> bool:
	return progression != null and bool(progression.data.get("headquarters_discovered",false))


func _sealed_sector_discovered() -> bool:
	return progression != null and bool(progression.data.get("sealed_sector_discovered",false))


func _emit_state_changed() -> void:
	state_changed.emit()
	# The owner can connect state_changed and publish its aggregate snapshot.
	# Saving here is deliberately optional so the file also works in fixtures.
	if session != null and session.has_method("save_game"): session.save_game()


func _show_message(value: String) -> void:
	if session != null and session.has_method("show_message"): session.show_message(value)


func _cellar_global(point: Vector3) -> Vector3:
	return cellar_root.to_global(point)


func _build_annex() -> void:
	var annex := Node3D.new()
	annex.name = "Casa1CellarAnnex"
	home.add_child(annex)
	# The extension reads as a plain pantry from outside. It has no sign, slogan
	# or exterior interaction; the only usable access is from inside Casa 1.
	# The centre is the actual stairwell; only two narrow edge ledges remain.
	for side in [-1.0,1.0]:
		_box(annex,ANNEX_CENTER_LOCAL+Vector3(side*1.46,.03,0),Vector3(.23,.06,ANNEX_SIZE.z),"75694e")
	for side in [-1.0,1.0]:
		_solid_box(annex,"AnnexSide",ANNEX_CENTER_LOCAL+Vector3(side*ANNEX_SIZE.x*.5,1.35,0),Vector3(.18,2.7,ANNEX_SIZE.z),"7c735f")
	_solid_box(annex,"AnnexRear",ANNEX_CENTER_LOCAL+Vector3(0,1.35,-ANNEX_SIZE.z*.5),Vector3(ANNEX_SIZE.x,2.7,.18),"746b59")
	# Plain timber framing makes the small addition read as an old pantry while
	# remaining visually quieter than the house facade.
	for side in [-1.0,1.0]:
		_batch_box(annex,ANNEX_CENTER_LOCAL+Vector3(side*1.47,1.35,-2.54),Vector3(.14,2.55,.12),"544a3d")
		_batch_box(annex,ANNEX_CENTER_LOCAL+Vector3(side*1.47,1.35,2.54),Vector3(.14,2.55,.12),"544a3d")
	for x in [-.95,-.47,0.0,.47,.95]:
		_batch_box(annex,ANNEX_CENTER_LOCAL+Vector3(x,1.35,-2.70),Vector3(.035,2.42,.035),"625746")
	_box(homes.homes[HOME_INDEX].roof,ANNEX_CENTER_LOCAL+Vector3(0,2.82,0),Vector3(ANNEX_SIZE.x+.35,.18,ANNEX_SIZE.z+.35),"635c4c",Vector3(.03,0,0))
	surface_door = Node3D.new()
	surface_door.name = "CellarDoorPivot"
	surface_door.position = Vector3(-.08,0,-4.31)
	home.add_child(surface_door)
	_box(surface_door,Vector3(.73,1.14,.04),Vector3(1.46,2.28,.13),"665845")
	for y in [.38,.76,1.14,1.52,1.90]: _batch_box(surface_door,Vector3(.73,y,.12),Vector3(1.35,.055,.055),"897457")
	for x in [.08,1.38]: _batch_box(surface_door,Vector3(x,1.14,.13),Vector3(.07,2.14,.06),"493d31")
	_batch_cylinder(surface_door,Vector3(1.18,1.10,.18),.055,.055,"aa8952",Vector3(PI*.5,0,0))
	surface_door_body = _solid_box(surface_door,"CellarDoor",Vector3(.73,1.14,.04),Vector3(1.46,2.28,.16),"",Vector3.ZERO,false)
	_build_stair(annex)


func _build_stair(parent: Node3D) -> void:
	var run := STAIR_BOTTOM_LOCAL.z-STAIR_TOP_LOCAL.z
	var drop := STAIR_TOP_LOCAL.y-STAIR_BOTTOM_LOCAL.y
	# The terrain cut ends just behind the door while the inclined ramp begins
	# farther back. This level sill bridges both surfaces so the player's capsule
	# reaches the ramp top instead of falling against its steep front cap.
	# O patamar começa onde a rampa termina (z=-4,75). Começando antes (-4,825), a quina
	# ficava ~5 cm acima da rampa de 41° e prendia a cápsula na subida de volta à casa.
	_solid_box(parent,"EntryLanding",Vector3(.65,-.08,-4.325),Vector3(1.40,.14,.85),"4a5049")
	for index in 15:
		var weight := float(index)/14.0
		var point := STAIR_TOP_LOCAL.lerp(STAIR_BOTTOM_LOCAL,weight)
		_batch_box(parent,point,Vector3(2.55,.18,.46),"4a5049" if index%3 else "545b53")
	var angle := atan2(drop,absf(run))
	var middle := (STAIR_TOP_LOCAL+STAIR_BOTTOM_LOCAL)*.5+Vector3(0,-.12,0)
	var buried_toe := .30
	var ramp_center := middle-Vector3(0,sin(angle),cos(angle))*buried_toe*.5
	_solid_box(parent,"CellarStairRamp",ramp_center,Vector3(2.42,.16,Vector2(absf(run),drop).length()+buried_toe),"",Vector3(-angle,0,0),false)
	for side in [-1.0,1.0]:
		_solid_box(parent,"CellarStairWall",middle+Vector3(side*1.48,1.15,0),Vector3(.18,3.1,5.25),"615d50")


func _build_cellar() -> void:
	cellar_root = Node3D.new()
	cellar_root.name = "Casa1Cellar"
	cellar_root.position = CELLAR_ORIGIN_LOCAL
	home.add_child(cellar_root)
	_solid_box(cellar_root,"CellarFloor",Vector3(0,-.12,0),Vector3(8.9,.22,8.5),"4b5049")
	# Thin triangulated damp patches follow the slab without changing the walk
	# height. Uneven outlines avoid the appearance of rectangular rugs.
	_batch_floor_puddle(cellar_root,Vector3(-2.75,.002,-2.55),PackedVector2Array([
		Vector2(-.74,-.10),Vector2(-.48,-.27),Vector2(.03,-.23),Vector2(.61,-.13),
		Vector2(.70,.08),Vector2(.28,.24),Vector2(-.22,.20),Vector2(-.66,.10),
	]),"263a38")
	_batch_floor_puddle(cellar_root,Vector3(.10,.002,1.55),PackedVector2Array([
		Vector2(-.92,-.08),Vector2(-.64,-.22),Vector2(-.08,-.18),Vector2(.40,-.25),
		Vector2(.91,-.05),Vector2(.72,.16),Vector2(.18,.21),Vector2(-.34,.14),
		Vector2(-.80,.19),
	]),"263a38")
	_batch_floor_puddle(cellar_root,Vector3(2.85,.002,-.15),PackedVector2Array([
		Vector2(-.53,-.06),Vector2(-.25,-.17),Vector2(.18,-.13),Vector2(.56,.02),
		Vector2(.35,.15),Vector2(-.10,.17),Vector2(-.47,.10),
	]),"263a38")
	for wall in [
		[Vector3(-4.45,1.45,-2.535),Vector3(.30,3.0,3.43)],
		[Vector3(-4.45,1.45,2.685),Vector3(.30,3.0,3.13)],
		[Vector3(-4.45,2.68,.15),Vector3(.30,.54,1.94)],
		[Vector3(4.45,1.45,0),Vector3(.30,3.0,8.5)],
		[Vector3(0,1.45,-4.25),Vector3(8.9,3.0,.30)],
	]:
		_solid_box(cellar_root,"CellarWall",wall[0],wall[1],"",Vector3.ZERO,false)
		# Recess the mortar behind the individual stones while retaining the
		# full physical envelope. Flush mortar previously hid their front faces.
		var backing: Vector3 = wall[1]
		if backing.x < .5: backing.x = .20
		elif backing.z < .5: backing.z = .20
		_box(cellar_root,wall[0],backing,"555a51")
	# Full front collision, cut away only in the presentation layer.
	_solid_box(cellar_root,"CellarFrontWall",Vector3(0,1.45,4.25),Vector3(8.9,3.0,.30),"",Vector3.ZERO,false)
	_build_cellar_masonry()
	cellar_ceiling = Node3D.new()
	cellar_ceiling.name = "CellarCeilingCutaway"
	cellar_root.add_child(cellar_ceiling)
	_box(cellar_ceiling,Vector3(0,3.06,0),Vector3(9.0,.24,8.6),"393f3b")
	for x in [-3.55,-1.78,0.0,1.78,3.55]:
		_batch_box(cellar_ceiling,Vector3(x,2.88,0),Vector3(.20,.22,8.35),"443e34")
	# Sparse, ordinary storage makes the room worth reading before the unusual
	# shelf is noticed. Every full-volume object receives matching collision.
	_solid_box(cellar_root,"StorageRack",Vector3(3.45,.85,-1.7),Vector3(1.35,1.7,3.0),"",Vector3.ZERO,false)
	_build_storage_rack()
	_solid_box(cellar_root,"CellarCrates",Vector3(2.7,.48,2.75),Vector3(2.1,.96,1.45),"",Vector3.ZERO,false)
	_build_crate_stack()
	_solid_box(cellar_root,"CellarWorkbench",Vector3(-1.2,.55,3.45),Vector3(2.7,1.1,.9),"",Vector3.ZERO,false)
	_build_radio_workbench()
	# One short-range, shadowless utility lamp keeps the stair and shelf readable
	# without adding overlapping light sources to the streamed exterior.
	_box(cellar_root,Vector3(.35,2.88,.25),Vector3(.70,.12,.24),"8a7757")
	var utility_light := OmniLight3D.new()
	utility_light.name = "CellarUtilityLight"
	utility_light.position = Vector3(.35,2.70,.25)
	utility_light.light_color = Color("c7a36d")
	utility_light.light_energy = 2.15
	utility_light.omni_range = 6.2
	utility_light.shadow_enabled = false
	cellar_root.add_child(utility_light)
	_build_cellar_shelf()


func _build_cellar_masonry() -> void:
	# The load-bearing colliders remain flat; shallow blocks sit entirely inside
	# their volume, so the old, uneven stone reads without changing circulation.
	var stone_colors := ["5d6259","4b514b","66675d","535a52"]
	for row in 5:
		var y := .27+float(row)*.55
		var offset := .48 if row%2 else 0.0
		for column in 9:
			var x := -3.92+float(column)*.98+offset
			if x > 4.05: continue
			var width := .88 if (column+row)%3 else .78
			_batch_box(cellar_root,Vector3(x,y,-4.115),Vector3(width,.46,.025),stone_colors[(column+row*2)%stone_colors.size()])
	for side in [-1.0,1.0]:
		for row in 5:
			var y := .27+float(row)*.55
			for column in 8:
				var z := -3.72+float(column)*1.04+(.50 if row%2 else 0.0)
				if z > 3.85: continue
				if side < 0.0 and z > -.86 and z < 1.16: continue
				_batch_box(cellar_root,Vector3(side*4.305,y,z),Vector3(.025,.46,.92),stone_colors[(column+row+int(side>0.0))%stone_colors.size()])


func _build_storage_rack() -> void:
	var center := Vector3(3.45,0,-1.70)
	for x in [-.54,.54]:
		for z in [-1.32,1.32]:
			_batch_box(cellar_root,center+Vector3(x,.85,z),Vector3(.10,1.70,.10),"53564e")
	for y in [.18,.70,1.22,1.62]:
		_batch_box(cellar_root,center+Vector3(0,y,0),Vector3(1.18,.09,2.82),"81765e")
	for point in [
		Vector3(3.45,.39,-2.55),Vector3(3.45,.91,-1.70),Vector3(3.45,1.43,-.87),
	]:
		_batch_box(cellar_root,point,Vector3(.82,.32,.62),"6d624d")
		_batch_box(cellar_root,point+Vector3(0,.01,.321),Vector3(.70,.06,.025),"9a835c")
	for z in [-2.55,-2.20,-.98,-.63]:
		_batch_cylinder(cellar_root,Vector3(3.45,1.37,z),.105,.28,"657269")


func _build_crate_stack() -> void:
	_build_crate(Vector3(2.26,.31,2.62),Vector3(.90,.62,1.12),"756047")
	_build_crate(Vector3(3.20,.28,2.82),Vector3(.82,.56,.94),"68533f")
	_build_crate(Vector3(2.72,.73,2.72),Vector3(.92,.40,.84),"80694d")


func _build_crate(at: Vector3,size: Vector3,color: String) -> void:
	_batch_box(cellar_root,at,size,color)
	for y in [-.38,.38]:
		_batch_box(cellar_root,at+Vector3(0,y*size.y, size.z*.505),Vector3(size.x*.94,.055,.035),"4c4034")
	for x in [-.42,.42]:
		_batch_box(cellar_root,at+Vector3(x*size.x,0,size.z*.505),Vector3(.055,size.y*.86,.035),"4c4034")


func _build_radio_workbench() -> void:
	var center := Vector3(-1.20,0,3.45)
	_batch_box(cellar_root,center+Vector3(0,.86,0),Vector3(2.70,.16,.90),"806b4e")
	for x in [-1.12,1.12]:
		for z in [-.32,.32]:
			_batch_box(cellar_root,center+Vector3(x,.42,z),Vector3(.13,.84,.13),"564637")
	_batch_box(cellar_root,center+Vector3(0,.62,-.37),Vector3(2.48,.16,.12),"5d4d3b")
	# Box, tuning glass, grille, knobs and aerial form one readable field radio.
	var radio := center+Vector3(-.34,1.13,0)
	_batch_box(cellar_root,radio,Vector3(1.12,.46,.42),"303735")
	_batch_box(cellar_root,radio+Vector3(-.24,.06,.222),Vector3(.44,.22,.025),"404b46")
	for x in [-.40,-.30,-.20,-.10]:
		_batch_box(cellar_root,radio+Vector3(x,.06,.239),Vector3(.022,.18,.018),"788077")
	_batch_box(cellar_root,radio+Vector3(.28,.10,.239),Vector3(.34,.10,.018),"b49457")
	for x in [.18,.38]: _batch_cylinder(cellar_root,radio+Vector3(x,-.10,.244),.055,.035,"aa8952",Vector3(PI*.5,0,0))
	_batch_cylinder(cellar_root,radio+Vector3(.43,.57,-.10),.018,.78,"777b70",Vector3(0,0,-.15))
	_batch_box(cellar_root,center+Vector3(.78,.98,.06),Vector3(.56,.025,.42),"b5aa8b",Vector3(0,-.10,0))


func _build_cellar_shelf() -> void:
	# Shelf is on the cellar's west wall, away from the stair landing. Its
	# contents are geometry only; there are no explanatory labels.
	shelf_pivot = Node3D.new()
	shelf_pivot.name = "SecretShelfPivot"
	# Opposite hinges leave the walking route clear when both panels are open.
	shelf_pivot.position = Vector3(-4.12,0,1.12)
	cellar_root.add_child(shelf_pivot)
	_batch_box(shelf_pivot,Vector3(.11,1.18,-.97),Vector3(.28,2.36,1.94),"514536")
	for z in [.055,1.885]: _batch_box(shelf_pivot,Vector3(.31,1.18,-z),Vector3(.34,2.36,.11),"756047")
	for y in [.06,2.30]: _batch_box(shelf_pivot,Vector3(.31,y,-.97),Vector3(.38,.14,2.08),"806a4b")
	for y in [.32,.78,1.24,1.70,2.16]: _batch_box(shelf_pivot,Vector3(.34,y,-.97),Vector3(.38,.08,1.82),"8d7653")
	var book_colors := ["704b3e","53665c","887252","4a5961","755d68","9a8259"]
	var book_widths := [.11,.14,.09,.16,.12,.10,.15,.08,.13,.11]
	for row in 4:
		var base_y := .36+float(row)*.46
		var z := .14
		for index in book_widths.size():
			var width: float = book_widths[(index+row*2)%book_widths.size()]
			var height := .27+float((index+row)%4)*.025
			var tilt := -.045 if index%5==0 else (.035 if index%4==0 else 0.0)
			_batch_box(shelf_pivot,Vector3(.50,base_y+height*.5,-z-width*.5),Vector3(.24,height,width),book_colors[(index+row)%book_colors.size()],Vector3(-tilt,0,0))
			z += width+.026
			if z > 1.78: break
	shelf_body = _solid_box(shelf_pivot,"SecretBookshelf",Vector3(.18,1.18,-.97),Vector3(.46,2.36,1.94),"",Vector3.ZERO,false)
	tunnel_door = Node3D.new()
	tunnel_door.name = "TunnelDoorPivot"
	tunnel_door.position = Vector3(-4.27,0,-.82)
	cellar_root.add_child(tunnel_door)
	_batch_box(tunnel_door,Vector3(.06,1.18,.97),Vector3(.16,2.36,1.94),"343c3a")
	for y in [.28,.78,1.28,1.78,2.22]: _batch_box(tunnel_door,Vector3(.15,y,.97),Vector3(.08,.07,1.78),"6f746b")
	for z in [.14,1.80]: _batch_box(tunnel_door,Vector3(.15,1.18,z),Vector3(.08,2.18,.08),"6f746b")
	for y in [.30,2.05]:
		for z in [.18,1.76]: _batch_cylinder(tunnel_door,Vector3(.205,y,z),.035,.025,"9b8254",Vector3(0,0,PI*.5))
	tunnel_door_body = _solid_box(tunnel_door,"TunnelDoor",Vector3(.06,1.18,.97),Vector3(.18,2.36,1.94),"",Vector3.ZERO,false)
	# Functional keypad: ten small keys and two controls, with no decorative text.
	_box(cellar_root,KEYPAD_CENTER,Vector3(.18,.78,.56),"303937")
	_batch_box(cellar_root,KEYPAD_CENTER+Vector3(.105,.31,0),Vector3(.025,.11,.40),"607d66")
	for row in 4:
		for column in 3:
			_batch_box(cellar_root,KEYPAD_CENTER+Vector3(.105,.17-float(row)*.125,-.17+float(column)*.17),Vector3(.025,.075,.075),"8b8f7f")


func _build_camera() -> void:
	cellar_camera = Camera3D.new()
	cellar_camera.name = "Casa1CellarCamera"
	cellar_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cellar_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	cellar_camera.size = 10.8
	cellar_camera.near = .12
	cellar_camera.far = 45.0
	cellar_camera.cull_mask = UNDERGROUND_LAYER
	UNDERGROUND_ENVIRONMENT.apply_to(cellar_camera)
	cellar_root.add_child(cellar_camera)
	_update_cellar_camera(_cellar_global(Vector3.ZERO))


func _batch_floor_puddle(parent: Node3D,center: Vector3,outline: PackedVector2Array,color: String) -> void:
	if outline.size() < 3: return
	var key := "%s/%s"%[parent.get_instance_id(),color]
	if not _batches.has(key):
		var created := SurfaceTool.new()
		created.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"surface":created,"parent":parent,"color":color}
	var surface: SurfaceTool = _batches[key].surface
	for index in outline.size():
		var current := outline[index]
		var next := outline[(index+1)%outline.size()]
		for vertex in [
			center,
			center+Vector3(current.x,0,current.y),
			center+Vector3(next.x,0,next.y),
		]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)


func _batch_box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch_mesh(parent,mesh,at,color,angles)


func _batch_cylinder(parent: Node3D,at: Vector3,radius: float,height: float,color: String,angles := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	_batch_mesh(parent,mesh,at,color,angles)


func _batch_mesh(parent: Node3D,mesh: Mesh,at: Vector3,color: String,angles: Vector3) -> void:
	var key := "%s/%s"%[parent.get_instance_id(),color]
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"surface":surface,"parent":parent,"color":color}
	_batches[key].surface.append_from(mesh,0,Transform3D(Basis.from_euler(angles),at))


func _flush_batches() -> void:
	for batch in _batches.values():
		var node := MeshInstance3D.new()
		node.name = "CellarDetailBatch"
		node.mesh = batch.surface.commit()
		node.material_override = _material(batch.color)
		batch.parent.add_child(node)
	_batches.clear()


func _solid_box(parent: Node3D,id: String,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO,with_visual := true) -> StaticBody3D:
	if with_visual and not color.is_empty(): _box(parent,at,size,color,angles)
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.rotation = angles
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","truckers_home_1_secret/"+id)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	solids.append(body)
	return body


func _box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation = angles
	node.material_override = _material(color)
	parent.add_child(node)
	return node


func _material(color: String) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .91
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if color in ["303735","303937","343c3a","53564e","6f746b","777b70","788077","8b8f7f"]:
			material.metallic = .62
			material.roughness = .54
		elif color in ["aa8952","9b8254","b49457"]:
			material.metallic = .78
			material.roughness = .38
		elif color in ["5d6259","4b514b","66675d","535a52","555a51","4b5049"]:
			material.roughness = .98
		elif color == "263a38":
			material.roughness = .24
			material.metallic = .05
		elif color == "607d66":
			material.emission_enabled = true
			material.emission = Color("395a44")
			material.emission_energy_multiplier = .55
		_materials[color] = material
	return _materials[color]


func _apply_underground_layer(root: Node) -> void:
	for node in root.find_children("*","GeometryInstance3D",true,false):
		node.layers = UNDERGROUND_LAYER
	for light in root.find_children("*","Light3D",true,false):
		light.layers = UNDERGROUND_LAYER
		light.light_cull_mask = UNDERGROUND_LAYER


func _enable_player_underground_layer() -> void:
	if session == null or not is_instance_valid(session.world.player): return
	for node in session.world.player.find_children("*","GeometryInstance3D",true,false):
		node.layers |= UNDERGROUND_LAYER


func _exit_tree() -> void:
	if _cellar_occupied: _set_cellar_occupied(false)
