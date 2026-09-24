extends Node3D
## Explicit service registration, engine audio only.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const FLEET = preload("res://runtime/FleetCatalog.gd")
const ENGINE_PROFILE = preload("res://audio/VehicleEngineProfile.gd")
const GROUP := &"service_vehicle_engine_mixer"
const MAX_REGISTERED := 32
const MAX_AUDIBLE := 6
const MAX_VOICES := 12
const RANGE := 45.0
var _entries: Dictionary = {}
var _banks: Dictionary = {}
var _slots: Array[Dictionary] = []
var _world: Node
var _listener: Node3D
var _enabled := true
var _clock := 0.0

func _ready() -> void:
	set_process(false)
	if get_tree().get_first_node_in_group(GROUP) != null:
		push_warning("ServiceVehicleAudio: mixer already exists")
		queue_free()
		return
	add_to_group(GROUP)
	process_priority = 100
	process_mode = Node.PROCESS_MODE_PAUSABLE

func configure(world: Node, listener: Node3D) -> bool:
	if not is_inside_tree() or get_tree().get_first_node_in_group(GROUP) != self:
		return false
	if not is_instance_valid(world) or not is_instance_valid(listener):
		return false
	_world = world
	_listener = listener
	set_process(_enabled and not _entries.is_empty())
	return true

func register_vehicle(vehicle: CharacterBody3D, service: String) -> bool:
	if not is_inside_tree() or get_tree().get_first_node_in_group(GROUP) != self:
		return false
	if not is_instance_valid(_world) or not is_instance_valid(_listener):
		return false
	if not is_instance_valid(vehicle) or not vehicle is VEHICLE:
		return false
	if not vehicle.is_inside_tree() or vehicle.is_queued_for_deletion():
		return false
	if service not in ["police", "medic", "fire", "mortician"]:
		return false
	var id := vehicle.get_instance_id()
	if _entries.has(id):
		return _entries[id].service == service
	if _entries.size() >= MAX_REGISTERED:
		return false
	var spec: Dictionary = FLEET.spec(vehicle.archetype)
	if spec.is_empty():
		return false
	var family := ENGINE_PROFILE.bank_family(str(vehicle.archetype))
	if not _has_bank(family):
		family = "street"
	if not _banks.has(family):
		var bank := _load_bank(family)
		if bank.size() != 7:
			return false
		_banks[family] = bank
	var on_exit := unregister_id.bind(id)
	vehicle.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	_entries[id] = {"vehicle": weakref(vehicle), "service": service,
		"family": family, "active": true, "previous": absf(vehicle.speed),
		"acceleration": 0.0, "rpm": 0.0, "on_exit": on_exit}
	_clock = 0.0
	set_process(_enabled)
	return true

func unregister_vehicle(vehicle: CharacterBody3D) -> void:
	if is_instance_valid(vehicle):
		unregister_id(vehicle.get_instance_id())

func unregister_id(id: int) -> void:
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var vehicle: Node = entry.vehicle.get_ref()
	if is_instance_valid(vehicle) and vehicle.tree_exiting.is_connected(entry.on_exit):
		vehicle.tree_exiting.disconnect(entry.on_exit)
	for slot in _slots:
		if slot.id == id:
			_release(slot)
	_entries.erase(id)
	var used := false
	for other in _entries.values():
		if other.family == entry.family:
			used = true
	if not used:
		_banks.erase(entry.family)
	if _entries.is_empty():
		set_process(false)
		_free_slots()

func set_vehicle_active(vehicle: CharacterBody3D, active: bool) -> void:
	if not is_instance_valid(vehicle) or not _entries.has(vehicle.get_instance_id()):
		return
	var id := vehicle.get_instance_id()
	_entries[id].active = active
	_entries[id].previous = absf(vehicle.speed)
	_entries[id].acceleration = 0.0
	_clock = 0.0
	if not active:
		for slot in _slots:
			if slot.id == id:
				_release(slot)

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_clock = 0.0
	for entry in _entries.values():
		var vehicle: CharacterBody3D = entry.vehicle.get_ref()
		if is_instance_valid(vehicle):
			entry.previous = absf(vehicle.speed)
		entry.acceleration = 0.0
	if not enabled:
		for slot in _slots:
			_release(slot)
	set_process(enabled and not _entries.is_empty())

func shutdown() -> void:
	for id in _entries.keys():
		unregister_id(id)
	_free_slots()
	_banks.clear()
	_world = null
	_listener = null
	set_process(false)

func _exit_tree() -> void:
	shutdown()

func _eligible(vehicle: CharacterBody3D, entry: Dictionary) -> bool:
	if vehicle.is_queued_for_deletion() or not entry.active or not vehicle.is_inside_tree():
		return false
	if not vehicle.can_process() or not vehicle.is_physics_processing() or not vehicle.is_visible_in_tree():
		return false
	if vehicle.health <= 0 or vehicle.engine_disabled:
		return false
	# Dispatch controlled=true is an NPC only while external_input=true.
	if vehicle.controlled and not vehicle.external_input:
		return false
	var driving: Variant = _world.get("driving")
	if is_instance_valid(driving) and driving.occupied and driving.car == vehicle:
		return false
	return vehicle.controlled or vehicle.traffic

func _process(delta: float) -> void:
	if not is_instance_valid(_world) or not is_instance_valid(_listener) or not _listener.is_inside_tree():
		set_enabled(false)
		return
	_clock -= delta
	var candidates: Array[Dictionary] = []
	for id in _entries.keys():
		var entry: Dictionary = _entries[id]
		var vehicle: CharacterBody3D = entry.vehicle.get_ref()
		if not is_instance_valid(vehicle):
			unregister_id(id)
			continue
		var speed := absf(float(vehicle.speed))
		var acceleration := (speed - float(entry.previous)) / maxf(delta, 0.001)
		entry.previous = speed
		var distance := vehicle.global_position.distance_squared_to(_listener.global_position)
		if not _eligible(vehicle, entry) or distance >= RANGE * RANGE:
			entry.acceleration = 0.0
			for slot in _slots:
				if slot.id == id:
					_release(slot)
			continue
		entry.acceleration = lerpf(entry.acceleration, clampf(acceleration, -10, 10), minf(1, delta * 5))
		var ratio := clampf(speed / maxf(vehicle.max_forward_speed, 1), 0, 1)
		var load_value := clampf(maxf(0, entry.acceleration) / maxf(vehicle.drive_acceleration, 1), 0, 1)
		var rpm := clampf(0.1 + ratio * 0.72 + load_value * 0.18, 0, 1) * 6
		entry.rpm = lerpf(entry.rpm, rpm, minf(1, delta * 5))
		if _clock <= 0:
			candidates.append({"id": id, "distance": distance})
	if _clock <= 0:
		_clock = 0.1
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.distance == b.distance: return a.id < b.id
			return a.distance < b.distance)
		var selected: Array[int] = []
		for candidate in candidates.slice(0, MAX_AUDIBLE):
			selected.append(candidate.id)
		for slot in _slots:
			if slot.id not in selected:
				_release(slot)
		for id in selected:
			_assign(id)
	for slot in _slots:
		if slot.id != 0:
			_mix(slot)

func _assign(id: int) -> void:
	for slot in _slots:
		if slot.id == id:
			return
	for slot in _slots:
		if slot.id == 0:
			slot.id = id
			return
	if _slots.size() >= MAX_AUDIBLE:
		return
	var players: Array[AudioStreamPlayer3D] = []
	for index in 2:
		var player := AudioStreamPlayer3D.new()
		player.max_polyphony = 1
		player.max_distance = RANGE
		player.unit_size = 8.0
		if AudioServer.get_bus_index("SFX") >= 0:
			player.bus = &"SFX"
		add_child(player)
		players.append(player)
	_slots.append({"id": id, "players": players})

func _mix(slot: Dictionary) -> void:
	var entry: Dictionary = _entries[slot.id]
	var vehicle: CharacterBody3D = entry.vehicle.get_ref()
	var lower := mini(5, floori(entry.rpm))
	var blend := clampf(float(entry.rpm) - lower, 0, 1)
	var camera := get_viewport().get_camera_3d()
	var audio_height := camera.global_position.y - _listener.global_position.y if camera != null else 0.0
	# Parity preserves the shared sample across adjacent layer boundaries.
	for layer in [lower, lower + 1]:
		var player: AudioStreamPlayer3D = slot.players[layer % 2]
		var weight := 1.0 - blend if layer == lower else blend
		player.global_position = vehicle.global_position + Vector3.UP * (audio_height + 0.7)
		if weight <= 0.001:
			player.stop()
			continue
		var stream: AudioStreamWAV = _banks[entry.family][layer]
		if player.stream != stream:
			player.stop()
			player.stream = stream
		player.volume_db = -23.0 + (-13.0 if entry.family == "electric" else 0.0) + linear_to_db(sqrt(weight))
		player.pitch_scale = 1.0 + clampf(entry.acceleration * 0.01, -0.05, 0.08)
		if not player.playing:
			player.play()

func _release(slot: Dictionary) -> void:
	for player in slot.players:
		player.stop()
		player.stream = null
	slot.id = 0

func _free_slots() -> void:
	for slot in _slots:
		_release(slot)
		for player in slot.players:
			player.free()
	_slots.clear()

func _has_bank(family: String) -> bool:
	for index in 7:
		if not ResourceLoader.exists("res://audio/acoustic/engine_%s_%d.wav" % [family, index]):
			return false
	return true

func _load_bank(family: String) -> Array[AudioStreamWAV]:
	var bank: Array[AudioStreamWAV] = []
	if not _has_bank(family):
		return bank
	for index in 7:
		var source := load("res://audio/acoustic/engine_%s_%d.wav" % [family, index]) as AudioStreamWAV
		if source == null:
			return []
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8)
		bank.append(stream)
	return bank
