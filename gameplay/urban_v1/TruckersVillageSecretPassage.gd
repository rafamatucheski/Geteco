extends Node3D
## Optional Casa 1 annex and cellar controller.
##
## A casa continua pertencendo a TruckersVillageHomes. Este nó só anexa um
## anexo traseiro estreito, o porão abaixo dele e os mecanismos móveis de acesso.
## NativeRegion e a casca da casa consomem physical_cut_spec() para que o jogador
## ande sem interrupção pela escada definida. As ações de transferência continuam
## como fallback seguro para prévias de cena isoladas que não instalam os cortes.

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
const CLUES := preload("res://data/catalogs/TruckersPassageClues.gd")
# Tabelas em data/catalogs/TruckersPassageClues.gd; reexportadas aqui com o mesmo nome.
const VAULT_DIGITS := CLUES.VAULT_DIGITS
const AUDIO_PICKUPS := CLUES.AUDIO_PICKUPS
const AUDIO_PICKUP_REACH := 1.3
const ACTION_PREFIX := "truckers_village_secret_"
const INTERACTION_REACH := 1.65
const UNDERGROUND_LAYER := 1 << 18

# Coordenadas locais da Casa 1. O anexo ocupa a abertura central existente na
# cerca dos fundos e não acrescenta nem clona mobília na sala principal.
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
## Auxiliares sem estado (01/11, só para este arquivo caber na leitura): o estado continua aqui, e cada
## função antiga virou delegação de uma linha, então testes que chamam `_submit_keypad`,
## `_open_vault_keypad` etc. por nome não mudam. Criados na declaração, e não em configure(), porque
## testes montam a passagem com PASSAGE.new() e chamam as funções direto.
const KEYPAD_PART := preload("res://gameplay/urban_v1/TruckersPassageKeypad.gd")
const TRAVEL_PART := preload("res://gameplay/urban_v1/TruckersPassageTravel.gd")
const CELLAR_BUILDER := preload("res://gameplay/urban_v1/TruckersCellarBuilder.gd")
var _keypad_part: KEYPAD_PART = KEYPAD_PART.new(self)
var _travel_part: TRAVEL_PART = TRAVEL_PART.new(self)
var _cellar_builder: CELLAR_BUILDER = CELLAR_BUILDER.new(self)


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
		# UrbanOperations é um Node, então a passagem normalmente tem transform de mundo
		# identidade. Top-level também protege o cenário subterrâneo remoto se o
		# gerenciador for montado depois sob um dono visual transformado.
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
		# Mantém vivo o piso de destino enquanto visita um esgoto conectado para que
		# FullSession possa validar o ponto de volta subterrâneo na saída.
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
		var audio_action := _audio_pickup_action(point)
		if not audio_action.is_empty(): return audio_action
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
	if target.ends_with("fort_open_door") or target.ends_with("fort_search_desk"): return session.room.operation.perform(target)
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
	if suffix.begins_with("audio_"): return _collect_audio_pickup(int(suffix.trim_prefix("audio_")))
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
	# O túnel é nosso filho e processa depois deste controlador. Preserva a
	# câmera do porão neste único quadro de passagem para que SecretTunnel3D a registre como
	# câmera de volta em vez de registrar por acidente a câmera externa.
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
		and session.player_health() > 0 and not session.player_in_vehicle() \
		and is_instance_valid(session.world.player)


func _maciota_story_action() -> Dictionary:
	if session == null or progression == null or _dossier_received() or not session.ready_for_play:
		return {}
	if session.state.region_id != "harbor" or session.state.place_id != "maciota":
		return {}
	if not session.state.campaign.snapshot().get("completed",[]).has("cobra_finale"):
		return {}
	if session.player_health() <= 0 or session.player_in_vehicle():
		return {}
	if not session.state.campaign.active_id.is_empty():
		return {}
	var room = session.room
	if not is_instance_valid(room) or room.get("interaction_points") == null or not room.interaction_points.has("maciota"):
		return {}
	if session.player_position().distance_to(room.interaction_points.maciota) > 2.0:
		return {}
	return _action("receive_dossier","Conversar")


func _action(suffix: String,label: String) -> Dictionary:
	# FullSession despacha isto pela ação remapeável `interact`. O
	# próprio teclado numérico usa botões de UI com foco normais e ui_cancel/ui_accept.
	return {"id":"urban_v1","target":ACTION_PREFIX+suffix,"label":label}


## Teclados do porão e do cofre: corpo em TruckersPassageKeypad.gd (delegação de uma linha; mesmo nome e padrões).
func _open_keypad() -> void: _keypad_part._open_keypad()
func _open_vault_keypad() -> void: _keypad_part._open_vault_keypad()
func _show_keypad() -> void: _keypad_part._show_keypad()
func _keypad_press(value: String,display: Label) -> void: _keypad_part._keypad_press(value, display)
func _keypad_mask() -> String: return _keypad_part._keypad_mask()
func _active_code() -> String: return _keypad_part._active_code()
func _submit_keypad() -> void: _keypad_part._submit_keypad()
func _submit_vault_keypad() -> void: _keypad_part._submit_vault_keypad()
## Passagens casa/porão/túnel/forte/esgoto e câmera do porão: corpo em TruckersPassageTravel.gd (delegação de uma linha).
func _transfer_to_cellar() -> void: _travel_part._transfer_to_cellar()
func _transfer_to_house() -> void: _travel_part._transfer_to_house()
func _transfer_to_tunnel() -> void: _travel_part._transfer_to_tunnel()
func _finish_tunnel_transfer() -> void: _travel_part._finish_tunnel_transfer()
func _transfer_from_tunnel() -> void: _travel_part._transfer_from_tunnel()
func _set_player_position(point: Vector3) -> void: _travel_part._set_player_position(point)
func _lock_player(value: bool) -> void: _travel_part._lock_player(value)
func _in_cellar(point: Vector3) -> bool: return _travel_part._in_cellar(point)
func _set_cellar_occupied(value: bool,restore_surface_camera := true) -> void: _travel_part._set_cellar_occupied(value, restore_surface_camera)
func _update_cellar_camera(point: Vector3) -> void: _travel_part._update_cellar_camera(point)

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
		tunnel.set_enabled(_keypad_unlocked() and tunnel.contains(session.player_position()))
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


## Índice da gravação 01–03 ao alcance (local do túnel), ou -1. Estático para o teste de contrato
## conferir os pontos sem montar o mundo.
static func audio_pickup_at(progression_state, local_point: Vector3) -> int:
	if progression_state == null: return -1
	var best := -1
	var best_distance := AUDIO_PICKUP_REACH
	for index in AUDIO_PICKUPS.size():
		var entry: Dictionary = AUDIO_PICKUPS[index]
		if progression_state.has_audio_log(entry.id): continue
		var distance := local_point.distance_to(entry.local)
		if distance <= best_distance:
			best = index
			best_distance = distance
	return best


## Registra a gravação uma vez só; true quando entrou agora.
static func collect_audio_pickup(progression_state, index: int) -> bool:
	if progression_state == null or index < 0 or index >= AUDIO_PICKUPS.size(): return false
	return progression_state.discover_audio_log(AUDIO_PICKUPS[index].id)


func _audio_pickup_action(point: Vector3) -> Dictionary:
	var index := audio_pickup_at(progression,tunnel.to_local(point))
	if index < 0: return {}
	return _action("audio_%d"%index,str(AUDIO_PICKUPS[index].label))


func _collect_audio_pickup(index: int) -> bool:
	if not collect_audio_pickup(progression,index): return false
	_emit_state_changed()
	_show_message(str(AUDIO_PICKUPS[index].text)+"  Gravação guardada no Arquivo de Vicente.")
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


## Forte, esqui, cortina e viagens: corpo em TruckersPassageTravel.gd (delegação de uma linha; `await` nas corrotinas).
func _ski_exit_action() -> Dictionary: return _travel_part._ski_exit_action()
func _ascend_to_ski() -> void: await _travel_part._ascend_to_ski()
func _enter_fort_from_ski() -> void: await _travel_part._enter_fort_from_ski()
func _emerge_from_slab() -> void: await _travel_part._emerge_from_slab()
func _curtain(alpha: float,seconds: float,text := "") -> void: await _travel_part._curtain(alpha, seconds, text)
func _travel_to_fort() -> void: await _travel_part._travel_to_fort()
func _travel_to_sewer() -> void: await _travel_part._travel_to_sewer()

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
	# O dono pode conectar state_changed e publicar o snapshot agregado dele.
	# Salvar aqui é opcional de propósito para que o arquivo também funcione em fixtures.
	if session != null and session.has_method("save_game"): session.save_game()


func _show_message(value: String) -> void:
	if session != null and session.has_method("show_message"): session.show_message(value)


func _cellar_global(point: Vector3) -> Vector3:
	return cellar_root.to_global(point)


## Montagem do anexo, da escada e do porão: corpo em TruckersCellarBuilder.gd (delegação de uma linha; mesmo nome e padrões).
func _build_annex() -> void: _cellar_builder._build_annex()
func _build_stair(parent: Node3D) -> void: _cellar_builder._build_stair(parent)
func _build_cellar() -> void: _cellar_builder._build_cellar()
func _build_cellar_masonry() -> void: _cellar_builder._build_cellar_masonry()
func _build_storage_rack() -> void: _cellar_builder._build_storage_rack()
func _build_crate_stack() -> void: _cellar_builder._build_crate_stack()
func _build_crate(at: Vector3,size: Vector3,color: String) -> void: _cellar_builder._build_crate(at, size, color)
func _build_radio_workbench() -> void: _cellar_builder._build_radio_workbench()
func _build_cellar_shelf() -> void: _cellar_builder._build_cellar_shelf()
func _build_camera() -> void: _cellar_builder._build_camera()
func _batch_floor_puddle(parent: Node3D,center: Vector3,outline: PackedVector2Array,color: String) -> void: _cellar_builder._batch_floor_puddle(parent, center, outline, color)
func _batch_box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> void: _cellar_builder._batch_box(parent, at, size, color, angles)
func _batch_cylinder(parent: Node3D,at: Vector3,radius: float,height: float,color: String,angles := Vector3.ZERO) -> void: _cellar_builder._batch_cylinder(parent, at, radius, height, color, angles)
func _batch_mesh(parent: Node3D,mesh: Mesh,at: Vector3,color: String,angles: Vector3) -> void: _cellar_builder._batch_mesh(parent, mesh, at, color, angles)
func _flush_batches() -> void: _cellar_builder._flush_batches()
func _solid_box(parent: Node3D,id: String,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO,with_visual := true) -> StaticBody3D: return _cellar_builder._solid_box(parent, id, at, size, color, angles, with_visual)
func _box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> MeshInstance3D: return _cellar_builder._box(parent, at, size, color, angles)
func _material(color: String) -> StandardMaterial3D: return _cellar_builder._material(color)
func _apply_underground_layer(root: Node) -> void: _cellar_builder._apply_underground_layer(root)
func _enable_player_underground_layer() -> void: _cellar_builder._enable_player_underground_layer()

func _exit_tree() -> void:
	if _cellar_occupied: _set_cellar_occupied(false)
