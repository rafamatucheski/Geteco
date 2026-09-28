extends Node3D
## Bounded spatial engine bed for nearby traffic and externally driven vehicles.

const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const GROUP := &"nearby_vehicle_engine_mixer"
const SERVICE_GROUP := &"service_vehicle_engine_mixer"
const MAX_TRACKED := 96
const MAX_AUDIBLE := 6
const MAX_VOICES := MAX_AUDIBLE * 2
const RANGE := 45.0
const SELECTION_INTERVAL := 0.1
const FADE_IN_SECONDS := 0.22
const FADE_OUT_SECONDS := 0.28
const BASE_VOLUME_DB := -24.0

var _world: Node
var _listener: Node3D
var _slots: Array[Dictionary] = []
var _states: Dictionary = {}
var _banks: Dictionary = {}
var _family_by_archetype: Dictionary = {}
var _service_mixer: Node
var _selection_clock := 0.0
var _enabled := true


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
	set_process(_enabled)
	return true


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_selection_clock = 0.0
	if not enabled:
		for slot in _slots:
			_release(slot)
		_states.clear()
	set_process(enabled and is_instance_valid(_world) and is_instance_valid(_listener))


func shutdown() -> void:
	set_process(false)
	for slot in _slots:
		_release(slot)
		for player in slot.players:
			player.free()
	_slots.clear()
	_states.clear()
	_banks.clear()
	_family_by_archetype.clear()
	_service_mixer = null
	_world = null
	_listener = null


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
	# Dispatch vehicles intentionally leave the drivable group. Its public unit list is
	# the existing read-only bridge; no dispatch state is changed here.
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
	if vehicle.is_queued_for_deletion() or not vehicle.is_inside_tree():
		return false
	if not vehicle.can_process() or not vehicle.is_physics_processing() or not vehicle.is_visible_in_tree():
		return false
	if vehicle.health <= 0.0 or vehicle.engine_disabled:
		return false
	var driving: Variant = _world.get("driving")
	if is_instance_valid(driving) and driving.occupied and driving.car == vehicle:
		return false
	# Player-controlled vehicles belong to WorldAudio's seven-layer foreground mixer.
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
	var family := _resolve_family(archetype)
	var spec: Dictionary = FLEET.spec(archetype)
	_states[id] = {"vehicle": weakref(vehicle), "family": family,
		"engine_pitch": clampf(float(spec.get("engine_pitch", 1.0)), 0.6, 1.4),
		"previous_speed": absf(float(vehicle.speed)), "acceleration": 0.0, "rpm": 0.6}


func _resolve_family(archetype: String) -> String:
	if _family_by_archetype.has(archetype):
		return str(_family_by_archetype[archetype])
	var family := ENGINE_PROFILE.bank_family(archetype)
	if not _ensure_bank(family):
		family = "street"
		_ensure_bank(family)
	_family_by_archetype[archetype] = family
	return family


func _ensure_bank(family: String) -> bool:
	if _banks.has(family):
		return not (_banks[family] as Array).is_empty()
	var bank: Array[AudioStreamWAV] = []
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		if not ResourceLoader.exists(path):
			_banks[family] = []
			return false
		var source := load(path) as AudioStreamWAV
		if source == null:
			_banks[family] = []
			return false
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8)
		bank.append(stream)
	_banks[family] = bank
	return true


func _assign(id: int) -> void:
	if not _states.has(id) or (_banks.get(_states[id].family, []) as Array).size() != 7:
		return
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
		player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
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
	# Ownership changes must not overlap the foreground or service engine mixers.
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
	var target_rpm := clampf(0.1 + ratio * 0.72 + load_value * 0.18, 0.0, 1.0) * 6.0
	state.rpm = lerpf(float(state.rpm), target_rpm, minf(1.0, delta * 5.0))
	_mix(slot, state, vehicle)


func _mix(slot: Dictionary, state: Dictionary, vehicle: CharacterBody3D) -> void:
	var lower := mini(5, floori(float(state.rpm)))
	var blend := clampf(float(state.rpm) - lower, 0.0, 1.0)
	var bank: Array = _banks[state.family]
	# The top-down camera is high above the road. Keep horizontal 3D panning,
	# while measuring attenuation from the same ground plane as the listener.
	var camera := get_viewport().get_camera_3d()
	var audio_height := camera.global_position.y - _listener.global_position.y if camera != null else 0.0
	for layer in [lower, lower + 1]:
		var player: AudioStreamPlayer3D = slot.players[layer % 2]
		var weight := 1.0 - blend if layer == lower else blend
		player.global_position = vehicle.global_position + Vector3.UP * (audio_height + 0.7)
		var amplitude := sqrt(maxf(0.0, weight)) * float(slot.gain)
		if amplitude <= 0.001:
			player.stop()
			continue
		var stream := bank[layer] as AudioStreamWAV
		if player.stream != stream:
			player.stop()
			player.stream = stream
		player.volume_db = BASE_VOLUME_DB + (-13.0 if state.family == "electric" else 0.0) + linear_to_db(amplitude)
		var acceleration_pitch := clampf(float(state.acceleration) * 0.01, -0.05, 0.08)
		player.pitch_scale = clampf(float(state.engine_pitch) * (1.0 + acceleration_pitch), 0.55, 1.5)
		if not player.playing:
			player.play()


func _slot_has_id(id: int) -> bool:
	for slot in _slots:
		if slot.id == id:
			return true
	return false


func _release(slot: Dictionary) -> void:
	for player in slot.players:
		player.stop()
		player.stream = null
	slot.id = 0
	slot.gain = 0.0
	slot.target_gain = 0.0


func snapshot() -> Dictionary:
	var audible_ids: Array[int] = []
	var playing_voices := 0
	for slot in _slots:
		if slot.id != 0:
			audible_ids.append(slot.id)
		for player in slot.players:
			if player.playing:
				playing_voices += 1
	return {"audible": audible_ids.size(), "audible_ids": audible_ids,
		"playing_voices": playing_voices, "voice_limit": MAX_VOICES,
		"range": RANGE, "families_loaded": _banks.size()}
