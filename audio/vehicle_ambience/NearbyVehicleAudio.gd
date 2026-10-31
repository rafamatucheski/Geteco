extends Node3D
## Fundo espacial limitado de motores para o trânsito próximo e veículos dirigidos externamente.

const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const TANK_AUDIO := preload("res://audio/tank/TankAudio.gd")
const BANKS := preload("res://audio/EngineBankCache.gd")
const DESIGN_BANKS := preload("res://audio/EngineDesignBanks.gd")
const DESIGN_CATALOG := preload("res://audio/FleetEngineDesign.gd")
const DESIGN_VOICE := preload("res://audio/EngineDesignVoice.gd")
const GROUP := &"nearby_vehicle_engine_mixer"
const SERVICE_GROUP := &"service_vehicle_engine_mixer"
const MAX_TRACKED := 96
const MAX_AUDIBLE := 6
const MAX_VOICES := MAX_AUDIBLE * 2
const MAX_DESIGN_VOICES := MAX_AUDIBLE * 4
const RANGE := 45.0
const SELECTION_INTERVAL := 0.1
const FADE_IN_SECONDS := 0.22
const FADE_OUT_SECONDS := 0.28
const BASE_VOLUME_DB := -24.0
## Troca da ponte (`street`) para a família certa quando ela termina de carregar: desce até o
## silêncio, troca o fluxo e sobe. Trocar o stream com a voz tocando corta a onda e estala.
const BANK_SWAP_SECONDS := 0.12
## Cidade viva (GETECO_CITY_LIFE_AUDIO, padrão ligado; =0 volta ao modo antigo para A/B).
## O ouvinte do Godot é a câmera, ~36 m acima/atrás do jogador. Erguer o emissor à altura dela
## não bastava: um carro colado no jogador ainda ficava ~25–29 m do ouvinte na horizontal, e a
## atenuação nativa dava -11 dB (inverso, unit_size 8) + ~-9 dB da rampa linear do max_distance
## (1 - d/45) + o filtro de -24 dB acima de 5 kHz; quem passava ~16 m à frente (longe da câmera)
## saía do max_distance e sumia. Com BASE_VOLUME_DB -24 sobre bancos de -12 a -15 dBFS rms,
## o trânsito chegava perto de -46 dBFS: mudo. Agora, como em `Gameplay._hearing_gain_db`, a
## posição só dá o panorama e a perda vem da distância ao JOGADOR: 0 dB até 8 m, inverso da
## distância daí em diante e rampa até zero em RANGE. Conta (não medida no ouvido): um carro a
## Na calibração anterior, a 8 m ficava ~-22 a -25 dBFS rms com +10 dB do SFX.
## Agora acompanha Vehicles sem esse reforço, assim como o motor do jogador.
## Mesmo teto de 6 carros e 12/24 vozes; valores percebidos dependem da mixagem.
const CITY_LIFE := preload("res://audio/city_life/CityLifeAudio.gd")
const HEARING_REFERENCE := 8.0
const PLAYER_RELATIVE_VOLUME_DB := -20.0

var _world: Node
var _listener: Node3D
var _slots: Array[Dictionary] = []
var _states: Dictionary = {}
var _banks: Dictionary = {}
var _family_by_archetype: Dictionary = {}
var _service_mixer: Node
var _selection_clock := 0.0
var _enabled := true
var _player_relative := false
## Veículos elegíveis dentro de RANGE na última seleção (o leito de trânsito de WorldAudio segue).
var nearby_traffic := 0


func _ready() -> void:
	set_process(false)
	if get_tree().get_first_node_in_group(GROUP) != null:
		push_warning("NearbyVehicleAudio: mixer already exists")
		queue_free()
		return
	add_to_group(GROUP)
	process_priority = 90
	process_mode = Node.PROCESS_MODE_PAUSABLE


func configure(world: Node, listener: Node3D) -> bool:
	if not is_inside_tree() or get_tree().get_first_node_in_group(GROUP) != self:
		return false
	if not is_instance_valid(world) or not is_instance_valid(listener):
		return false
	_world = world
	_listener = listener
	_selection_clock = 0.0
	# Antes de qualquer voz: o modo vale para todas as que este mixer criar.
	if _slots.is_empty(): _player_relative = CITY_LIFE.enabled()
	BANKS.prewarm.call_deferred(get_tree())
	DESIGN_BANKS.prewarm.call_deferred(get_tree())
	set_process(_enabled)
	return true


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_selection_clock = 0.0
	if not enabled:
		for slot in _slots:
			_release(slot)
		_states.clear()
		nearby_traffic = 0
	set_process(enabled and is_instance_valid(_world) and is_instance_valid(_listener))


func shutdown() -> void:
	set_process(false)
	for slot in _slots:
		_release(slot)
		for player in slot.players:
			player.free()
		var voice: Node3D = slot.get("design_voice")
		if is_instance_valid(voice): voice.free()
	_slots.clear()
	_states.clear()
	_banks.clear()
	_family_by_archetype.clear()
	_service_mixer = null
	_world = null
	_listener = null
	nearby_traffic = 0


func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	if not is_instance_valid(_world) or not is_instance_valid(_listener) or not _listener.is_inside_tree():
		set_enabled(false)
		return
	_selection_clock -= delta
	if _selection_clock <= 0.0:
		_selection_clock = SELECTION_INTERVAL
		_select_nearby()
	for slot in _slots:
		_update_slot(slot, delta)


func _select_nearby() -> void:
	_service_mixer = get_tree().get_first_node_in_group(SERVICE_GROUP)
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	for candidate in _discover_vehicles():
		if not is_instance_valid(candidate) or not candidate is VEHICLE:
			continue
		var vehicle := candidate as CharacterBody3D
		var id := vehicle.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		if not _eligible(vehicle) or _service_mixer_handles(vehicle):
			continue
		var distance_squared := vehicle.global_position.distance_squared_to(_listener.global_position)
		if distance_squared >= RANGE * RANGE:
			continue
		var priority_distance := distance_squared + (0.0 if absf(float(vehicle.speed)) > 0.35 else 36.0)
		candidates.append({"id": id, "vehicle": vehicle, "distance": distance_squared,
			"priority_distance": priority_distance})
	nearby_traffic = candidates.size()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.priority_distance == b.priority_distance:
			return a.id < b.id
		return a.priority_distance < b.priority_distance)
	if candidates.size() > MAX_TRACKED:
		candidates.resize(MAX_TRACKED)
	var selected: Array[int] = []
	for candidate in candidates.slice(0, MAX_AUDIBLE):
		var id: int = candidate.id
		selected.append(id)
		_ensure_state(candidate.vehicle)
	for slot in _slots:
		if slot.id != 0 and slot.id not in selected:
			slot.target_gain = 0.0
	for candidate in candidates.slice(0, MAX_AUDIBLE):
		_assign(int(candidate.id))
	for id in _states.keys():
		if id not in seen and not _slot_has_id(id):
			_states.erase(id)


func _discover_vehicles() -> Array:
	var result: Array = get_tree().get_nodes_in_group(&"drivable")
	result.append_array(get_tree().get_nodes_in_group(&"public_transport_vehicle"))
	# Veículos de despacho saem de propósito do grupo dirigível. A lista pública de unidades é
	# a ponte só de leitura existente; nenhum estado de despacho muda aqui.
	var dispatch: Variant = _world.get("dispatch")
	if not is_instance_valid(dispatch):
		return result
	var units: Variant = dispatch.get("units")
	if not units is Array:
		return result
	for unit in units:
		if unit == null or unit.get("finished") == true:
			continue
		var vehicle: Variant = unit.get("vehicle")
		if is_instance_valid(vehicle):
			result.append(vehicle)
	return result


func _eligible(vehicle: CharacterBody3D) -> bool:
	# The dedicated desert adapter already owns these vehicles' engine audio.
	if vehicle.has_node("DesertCarAudio"): return false
	if vehicle.is_queued_for_deletion() or not vehicle.is_inside_tree():
		return false
	if not vehicle.can_process() or not vehicle.is_physics_processing() or not vehicle.is_visible_in_tree():
		return false
	if vehicle.health <= 0.0 or vehicle.engine_disabled:
		return false
	var driving: Variant = _world.get("driving")
	if is_instance_valid(driving) and driving.occupied and driving.car == vehicle:
		return false
	# Player-controlled vehicles belong to WorldAudio's foreground mixer.
	if vehicle.controlled and not vehicle.external_input:
		return false
	return vehicle.traffic or (vehicle.controlled and vehicle.external_input)


func _service_mixer_handles(vehicle: CharacterBody3D) -> bool:
	if not is_instance_valid(_service_mixer):
		return false
	if _service_mixer.has_method("handles_vehicle"):
		return bool(_service_mixer.call("handles_vehicle", vehicle))
	# Compatibility until ServiceVehicleAudio exposes:
	# handles_vehicle(vehicle: CharacterBody3D) -> bool.
	var entries: Variant = _service_mixer.get("_entries")
	return entries is Dictionary and entries.has(vehicle.get_instance_id())


func _ensure_state(vehicle: CharacterBody3D) -> void:
	var id := vehicle.get_instance_id()
	if _states.has(id):
		_states[id].vehicle = weakref(vehicle)
		return
	var archetype := str(vehicle.archetype)
	var wanted := _resolve_family(archetype)
	var spec: Dictionary = FLEET.spec(archetype)
	# "family" é o banco que toca agora (pode ser a ponte); "wanted_family", o da viatura.
	_states[id] = {"vehicle": weakref(vehicle), "family": wanted, "wanted_family": wanted, "swap_gain": 1.0,
		"engine_pitch": clampf(float(spec.get("engine_pitch", 1.0)), 0.6, 1.4),
		"previous_speed": absf(float(vehicle.speed)), "acceleration": 0.0, "rpm": 0.6}


func _resolve_family(archetype: String) -> String:
	if _family_by_archetype.has(archetype):
		return str(_family_by_archetype[archetype])
	# Existência no disco, não prontidão: a família ainda em leitura não pode virar `street`
	# para sempre neste arquétipo.
	var family := ENGINE_PROFILE.bank_family(archetype)
	if not BANKS.has_bank(family):
		family = "street"
	_family_by_archetype[archetype] = family
	return family


## Banco pronto para tocar. Não guarda o vazio de uma família ainda em leitura: o próximo
## pedido tenta de novo sem esperar.
func _ensure_bank(family: String) -> bool:
	if _banks.has(family):
		return (_banks[family] as Array).size() == 7
	var bank := BANKS.bank(family)
	if bank.size() != 7:
		return false
	_banks[family] = bank
	return true


func _assign(id: int) -> void:
	if not _states.has(id):
		return
	var state: Dictionary = _states[id]
	if not _ensure_bank(str(state.family)):
		var playable := BANKS.bridge_family(str(state.wanted_family))
		if playable.is_empty() or not _ensure_bank(playable):
			return
		state.family = playable
	for slot in _slots:
		if slot.id == id:
			slot.target_gain = 1.0
			return
	for slot in _slots:
		if slot.id == 0:
			_bind_slot(slot, id)
			return
	if _slots.size() >= MAX_AUDIBLE:
		return
	var players: Array[AudioStreamPlayer3D] = []
	for index in 2:
		var player := AudioStreamPlayer3D.new()
		player.name = "VehicleEngineVoice%d" % (_slots.size() * 2 + index)
		player.max_polyphony = 1
		player.max_distance = RANGE
		player.unit_size = 8.0
		player.bus = &"Vehicles" if AudioServer.get_bus_index("Vehicles") >= 0 else &"Master"
		if _player_relative: CITY_LIFE.make_player_relative(player)
		add_child(player)
		players.append(player)
	var slot := {"id": 0, "players": players, "gain": 0.0, "target_gain": 0.0}
	_slots.append(slot)
	_bind_slot(slot, id)


func _bind_slot(slot: Dictionary, id: int) -> void:
	slot.id = id
	slot.gain = 0.0
	slot.target_gain = 1.0


func _update_slot(slot: Dictionary, delta: float) -> void:
	if slot.id == 0:
		return
	if not _states.has(slot.id):
		_release(slot)
		return
	var state: Dictionary = _states[slot.id]
	var vehicle: CharacterBody3D = state.vehicle.get_ref()
	if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		_states.erase(slot.id)
		_release(slot)
		return
	# Trocas de posse não podem se sobrepor aos mixers de motor de primeiro plano ou de serviço.
	if not _eligible(vehicle) or _service_mixer_handles(vehicle):
		_states.erase(slot.id)
		_release(slot)
		return
	var fade_seconds := FADE_IN_SECONDS if slot.target_gain > slot.gain else FADE_OUT_SECONDS
	slot.gain = move_toward(float(slot.gain), float(slot.target_gain), delta / fade_seconds)
	if slot.target_gain <= 0.0 and slot.gain <= 0.001:
		_states.erase(slot.id)
		_release(slot)
		return
	var speed := absf(float(vehicle.speed))
	var acceleration := (speed - float(state.previous_speed)) / maxf(delta, 0.001)
	state.previous_speed = speed
	state.acceleration = lerpf(float(state.acceleration), clampf(acceleration, -10.0, 10.0), minf(1.0, delta * 5.0))
	var ratio := clampf(speed / maxf(float(vehicle.max_forward_speed), 1.0), 0.0, 1.0)
	var load_value := clampf(maxf(0.0, float(state.acceleration)) / maxf(float(vehicle.drive_acceleration), 1.0), 0.0, 1.0)
	# Controladores de trânsito podem contornar o trem de força. Deduz a carga sem escrever
	# no estado de física deles nem ler um RPM que parou de atualizar.
	state.design_load = 0.0 if float(state.acceleration) < -0.2 else clampf(0.12 + ratio * 0.3 + load_value * 0.6, 0.0, 1.0)
	var target_rpm := clampf(0.1 + ratio * 0.72 + load_value * 0.18, 0.0, 1.0) * 6.0
	state.rpm = lerpf(float(state.rpm), target_rpm, minf(1.0, delta * 5.0))
	_update_bank_swap(state, delta)
	_mix(slot, state, vehicle, delta)


func _update_bank_swap(state: Dictionary, delta: float) -> void:
	if state.family != state.wanted_family and _ensure_bank(str(state.wanted_family)):
		state.swap_gain = move_toward(float(state.swap_gain), 0.0, delta / BANK_SWAP_SECONDS)
		if float(state.swap_gain) <= 0.001:
			state.family = state.wanted_family
	elif float(state.swap_gain) < 1.0:
		state.swap_gain = move_toward(float(state.swap_gain), 1.0, delta / BANK_SWAP_SECONDS)


func _mix(slot: Dictionary, state: Dictionary, vehicle: CharacterBody3D, delta := 0.1) -> void:
	var lower := mini(5, floori(float(state.rpm)))
	var blend := clampf(float(state.rpm) - lower, 0.0, 1.0)
	var bank: Array = _banks[state.family]
	# A câmera de cima fica bem acima da rua. Mantém o pan 3D horizontal,
	# medindo a atenuação a partir do mesmo plano de chão do ouvinte.
	var camera := get_viewport().get_camera_3d()
	var audio_height := camera.global_position.y - _listener.global_position.y if camera != null else 0.0
	var at := vehicle.global_position + Vector3.UP * (audio_height + 0.7)
	var base_db := _base_volume_db(vehicle)
	if _mix_design(slot, state, vehicle, delta, at, base_db): return
	if state.family == "tank":
		TANK_AUDIO.mix_spatial(slot.players, vehicle, clampf((float(state.rpm) - 0.6) / 5.4, 0.0, 1.0),
			float(slot.gain), base_db, vehicle.global_position + Vector3.UP * (audio_height + 0.7))
		return
	for layer in [lower, lower + 1]:
		var player: AudioStreamPlayer3D = slot.players[layer % 2]
		var weight := 1.0 - blend if layer == lower else blend
		player.global_position = vehicle.global_position + Vector3.UP * (audio_height + 0.7)
		var amplitude := sqrt(maxf(0.0, weight)) * float(slot.gain) * float(state.get("swap_gain", 1.0))
		if amplitude <= 0.001:
			player.stop()
			continue
		var stream := bank[layer] as AudioStreamWAV
		if player.stream != stream:
			player.stop()
			player.stream = stream
		player.volume_db = base_db + (-13.0 if state.family == "electric" else 0.0) + linear_to_db(amplitude)
		var acceleration_pitch := clampf(float(state.acceleration) * 0.01, -0.05, 0.08)
		player.pitch_scale = clampf(float(state.engine_pitch) * (1.0 + acceleration_pitch), 0.55, 1.5)
		if not player.playing:
			player.play()


func _mix_design(slot: Dictionary, state: Dictionary, vehicle: CharacterBody3D, delta: float, at: Vector3, base_db := BASE_VOLUME_DB) -> bool:
	var voice: Variant = slot.get("design_voice")
	var profile := DESIGN_CATALOG.profile(str(vehicle.archetype))
	if not is_instance_valid(voice):
		if not DESIGN_BANKS.enabled() or not DESIGN_BANKS.is_ready(profile): return false
		voice = DESIGN_VOICE.new()
		voice.name = "NearbyEngineDesign%d" % _slots.find(slot)
		voice.player_relative = _player_relative
		add_child(voice)
		slot.design_voice = voice
	# Religar também cala um espaço reaproveitado quando o próximo carro é dedicado/antigo.
	if not voice.configure(str(vehicle.archetype)): return false
	for player in slot.players: player.stop()
	if float(slot.gain) <= 0.001:
		voice.stop()
		return true
	var anchors: Array = DESIGN_CATALOG.rpm_bands(profile)
	var band := 0.0 if absf(float(vehicle.speed)) < 0.35 else clampf(float(state.rpm), 0.0, 6.0)
	var lower := mini(5, floori(band))
	var target_rpm := exp(lerpf(log(float(anchors[lower])), log(float(anchors[lower + 1])), band - lower))
	var current_rpm := float(state.get("design_rpm", anchors[0])) if state.get("design_profile", "") == profile else float(anchors[0])
	var response := 10.0 if target_rpm > current_rpm else 6.0
	state.design_profile = profile
	state.design_rpm = lerpf(current_rpm, target_rpm, 1.0 - exp(-maxf(delta, 0.0) * response))
	voice.update_mix(float(state.design_rpm), float(state.get("design_load", 0.0)), delta,
		base_db + linear_to_db(float(slot.gain)), at, false, false)
	return true


## Nível de referência do veículo. No modo antigo, a atenuação nativa (da câmera) cuida da
## distância; com a cidade viva, a perda vem daqui, medida do jogador no plano do chão.
func _base_volume_db(vehicle: Node3D) -> float:
	if not _player_relative or not is_instance_valid(_listener): return BASE_VOLUME_DB
	var offset := vehicle.global_position - _listener.global_position
	offset.y = 0.0
	return PLAYER_RELATIVE_VOLUME_DB + engine_hearing_db(offset.length())


## 0 dB até HEARING_REFERENCE, inverso da distância depois, vezes a rampa linear até RANGE.
static func engine_hearing_db(distance: float) -> float:
	var gain := HEARING_REFERENCE / maxf(distance, HEARING_REFERENCE) * clampf(1.0 - distance / RANGE, 0.0, 1.0)
	return linear_to_db(gain) if gain > 0.0001 else -80.0


func _slot_has_id(id: int) -> bool:
	for slot in _slots:
		if slot.id == id:
			return true
	return false


func _release(slot: Dictionary) -> void:
	var voice: Variant = slot.get("design_voice")
	if is_instance_valid(voice): voice.stop()
	for player in slot.players:
		player.stop()
		player.stream = null
	slot.id = 0
	slot.gain = 0.0
	slot.target_gain = 0.0


func snapshot() -> Dictionary:
	var audible_ids: Array[int] = []
	var playing_voices := 0
	var design_slots := 0
	for slot in _slots:
		if slot.id != 0:
			audible_ids.append(slot.id)
		for player in slot.players:
			if player.playing:
				playing_voices += 1
		var voice: Variant = slot.get("design_voice")
		if is_instance_valid(voice):
			design_slots += 1
			playing_voices += int(voice.snapshot().motor_voices)
	return {"audible": audible_ids.size(), "audible_ids": audible_ids,
		"playing_voices": playing_voices, "voice_limit": MAX_DESIGN_VOICES if design_slots > 0 else MAX_VOICES,
		"design_slots": design_slots, "design_voice_limit": MAX_DESIGN_VOICES,
		"range": RANGE, "families_loaded": _banks.size(), "player_relative": _player_relative,
		"nearby_traffic": nearby_traffic}
