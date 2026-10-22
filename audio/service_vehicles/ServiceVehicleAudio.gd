extends Node3D
## Explicit service registration, engine audio only.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const FLEET = preload("res://runtime/FleetCatalog.gd")
const ENGINE_PROFILE = preload("res://audio/VehicleEngineProfile.gd")
const TANK_AUDIO := preload("res://audio/tank/TankAudio.gd")
const BANKS := preload("res://audio/EngineBankCache.gd")
const DESIGN_BANKS := preload("res://audio/EngineDesignBanks.gd")
const DESIGN_CATALOG := preload("res://audio/FleetEngineDesign.gd")
const DESIGN_VOICE := preload("res://audio/EngineDesignVoice.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
const GROUP := &"service_vehicle_engine_mixer"
## Bipe de ré (Firefly, 2026-10-15) dos serviços pesados, fora do orçamento de motor: no
## máximo dois bipes audíveis ao mesmo tempo, os dos veículos mais próximos.
const BEEP_FAMILIES := ["truck", "bus", "fire_diesel", "ambulance", "diesel"]
const MAX_BEEPERS := 2
var _beepers: Dictionary = {}
const MAX_REGISTERED := 32
const MAX_AUDIBLE := 6
const MAX_VOICES := 12
const MAX_DESIGN_VOICES := MAX_AUDIBLE * 4
const RANGE := 45.0
## Troca da ponte para a família certa: desce ao silêncio antes de trocar o fluxo (trocar com a
## voz tocando estala), como em NearbyVehicleAudio.
const BANK_SWAP_SECONDS := 0.12
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
	DESIGN_BANKS.prewarm.call_deferred(get_tree())
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
	# Banco ainda em leitura não recusa o registro: a viatura toca a ponte até ele ficar pronto.
	var playing_family := family if _ensure_bank(family) else ""
	var on_exit := unregister_id.bind(id)
	vehicle.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	_entries[id] = {"vehicle": weakref(vehicle), "service": service,
		"family": family, "bank_family": playing_family, "swap_gain": 1.0, "active": true, "previous": absf(vehicle.speed),
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
	_drop_beeper(id)
	_entries.erase(id)
	var used := false
	for other in _entries.values():
		if other.family == entry.family or other.bank_family == entry.family:
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
		_clear_beepers()
	set_process(enabled and not _entries.is_empty())

func shutdown() -> void:
	for id in _entries.keys():
		unregister_id(id)
	_free_slots()
	_clear_beepers()
	_banks.clear()
	_world = null
	_listener = null
	set_process(false)

func _exit_tree() -> void:
	shutdown()

func _eligible(vehicle: CharacterBody3D, entry: Dictionary) -> bool:
	# Registration does not transfer engine ownership from the desert adapter.
	if vehicle.has_node("DesertCarAudio"): return false
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
	var reversing: Array[Dictionary] = []
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
		# Dispatch/traffic can bypass the drivetrain, so infer audio load locally.
		entry.design_load = 0.0 if float(entry.acceleration) < -0.2 else clampf(0.12 + ratio * 0.3 + load_value * 0.6, 0.0, 1.0)
		var rpm := clampf(0.1 + ratio * 0.72 + load_value * 0.18, 0, 1) * 6
		entry.rpm = lerpf(entry.rpm, rpm, minf(1, delta * 5))
		if float(vehicle.speed) < -0.4 and entry.family in BEEP_FAMILIES:
			reversing.append({"id": id, "distance": distance})
		if _clock <= 0:
			candidates.append({"id": id, "distance": distance})
	_update_beepers(reversing)
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
			_mix(slot, delta)

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
		if AudioServer.get_bus_index("Vehicles") >= 0:
			player.bus = &"Vehicles"
		add_child(player)
		players.append(player)
	_slots.append({"id": id, "players": players})

func _mix(slot: Dictionary, delta := 0.1) -> void:
	var entry: Dictionary = _entries[slot.id]
	var vehicle: CharacterBody3D = entry.vehicle.get_ref()
	var lower := mini(5, floori(entry.rpm))
	var blend := clampf(float(entry.rpm) - lower, 0, 1)
	var camera := get_viewport().get_camera_3d()
	var audio_height := camera.global_position.y - _listener.global_position.y if camera != null else 0.0
	var at := vehicle.global_position + Vector3.UP * (audio_height + 0.7)
	if _mix_design(slot, entry, vehicle, delta, at): return
	if entry.family == "tank":
		TANK_AUDIO.mix_spatial(slot.players, vehicle, clampf((float(entry.rpm) - 0.6) / 5.4, 0.0, 1.0),
			1.0, -23.0, vehicle.global_position + Vector3.UP * (audio_height + 0.7))
		return
	_update_bank_swap(entry, delta)
	# Parity preserves the shared sample across adjacent layer boundaries.
	for layer in [lower, lower + 1]:
		var player: AudioStreamPlayer3D = slot.players[layer % 2]
		var weight := 1.0 - blend if layer == lower else blend
		player.global_position = vehicle.global_position + Vector3.UP * (audio_height + 0.7)
		var amplitude := sqrt(maxf(0.0, weight)) * float(entry.swap_gain)
		if amplitude <= 0.001 or str(entry.bank_family).is_empty():
			player.stop()
			continue
		var stream: AudioStreamWAV = _banks[entry.bank_family][layer]
		if player.stream != stream:
			player.stop()
			player.stream = stream
		player.volume_db = -23.0 + (-13.0 if entry.family == "electric" else 0.0) + linear_to_db(amplitude)
		player.pitch_scale = 1.0 + clampf(entry.acceleration * 0.01, -0.05, 0.08)
		if not player.playing:
			player.play()

func _mix_design(slot: Dictionary, entry: Dictionary, vehicle: CharacterBody3D, delta: float, at: Vector3) -> bool:
	var voice: Variant = slot.get("design_voice")
	var profile := DESIGN_CATALOG.profile(str(vehicle.archetype))
	if not is_instance_valid(voice):
		if not DESIGN_BANKS.enabled() or not DESIGN_BANKS.is_ready(profile): return false
		voice = DESIGN_VOICE.new()
		voice.name = "ServiceEngineDesign%d" % _slots.find(slot)
		add_child(voice)
		slot.design_voice = voice
	if not voice.configure(str(vehicle.archetype)): return false
	for player in slot.players: player.stop()
	var anchors: Array = DESIGN_CATALOG.rpm_bands(profile)
	var band := 0.0 if absf(float(vehicle.speed)) < 0.35 else clampf(float(entry.rpm), 0.0, 6.0)
	var lower := mini(5, floori(band))
	var target_rpm := exp(lerpf(log(float(anchors[lower])), log(float(anchors[lower + 1])), band - lower))
	var current_rpm := float(entry.get("design_rpm", anchors[0])) if entry.get("design_profile", "") == profile else float(anchors[0])
	var response := 10.0 if target_rpm > current_rpm else 6.0
	entry.design_profile = profile
	entry.design_rpm = lerpf(current_rpm, target_rpm, 1.0 - exp(-maxf(delta, 0.0) * response))
	voice.update_mix(float(entry.design_rpm), float(entry.get("design_load", 0.0)), delta, -23.0, at, false, false)
	return true

## Bipe de ré dos dois veículos de serviço mais próximos que andam para trás.
func _update_beepers(reversing: Array[Dictionary]) -> void:
	reversing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.distance == b.distance: return a.id < b.id
		return a.distance < b.distance)
	var wanted: Array[int] = []
	for candidate in reversing.slice(0, MAX_BEEPERS): wanted.append(candidate.id)
	for id in _beepers.keys():
		if id not in wanted: _drop_beeper(id)
	for id in wanted:
		var vehicle: CharacterBody3D = _entries[id].vehicle.get_ref()
		if not is_instance_valid(vehicle): continue
		var beeper: AudioStreamPlayer3D = _beepers.get(id)
		if beeper == null:
			var loop := FIREFLY.loop("service_vehicles", "reverse_beep_loop.wav")
			if loop == null: continue
			beeper = AudioStreamPlayer3D.new()
			beeper.name = "ReverseBeep%d" % id
			beeper.stream = loop
			beeper.max_distance = 40.0
			beeper.unit_size = 6.0
			beeper.volume_db = -12.0
			if AudioServer.get_bus_index("Vehicles") >= 0: beeper.bus = &"Vehicles"
			add_child(beeper)
			_beepers[id] = beeper
		beeper.global_position = vehicle.global_position
		if not beeper.playing: beeper.play()

func _drop_beeper(id: int) -> void:
	var beeper: AudioStreamPlayer3D = _beepers.get(id)
	if beeper == null: return
	_beepers.erase(id)
	if is_instance_valid(beeper):
		beeper.stop()
		beeper.free()

func _clear_beepers() -> void:
	for id in _beepers.keys(): _drop_beeper(id)

func _release(slot: Dictionary) -> void:
	var voice: Variant = slot.get("design_voice")
	if is_instance_valid(voice): voice.stop()
	for player in slot.players:
		player.stop()
		player.stream = null
	slot.id = 0

func _free_slots() -> void:
	for slot in _slots:
		_release(slot)
		for player in slot.players:
			player.free()
		var voice: Node3D = slot.get("design_voice")
		if is_instance_valid(voice): voice.free()
	_slots.clear()

## Liga a ponte enquanto a família da viatura carrega e troca por ela quando fica pronta.
func _update_bank_swap(entry: Dictionary, delta: float) -> void:
	var current := str(entry.bank_family)
	if current == entry.family:
		entry.swap_gain = move_toward(float(entry.swap_gain), 1.0, delta / BANK_SWAP_SECONDS)
		return
	if _ensure_bank(str(entry.family)):
		if current.is_empty():
			entry.bank_family = entry.family
			return
		entry.swap_gain = move_toward(float(entry.swap_gain), 0.0, delta / BANK_SWAP_SECONDS)
		if float(entry.swap_gain) <= 0.001:
			entry.bank_family = entry.family
	elif current.is_empty():
		var bridge := BANKS.bridge_family(str(entry.family))
		if not bridge.is_empty() and _ensure_bank(bridge):
			entry.bank_family = bridge

## Banco pronto; não guarda o vazio de uma família em leitura para tentar de novo depois.
func _ensure_bank(family: String) -> bool:
	if _banks.has(family):
		return true
	var bank := _load_bank(family)
	if bank.size() != 7:
		return false
	_banks[family] = bank
	return true

func _has_bank(family: String) -> bool:
	return BANKS.has_bank(family)

func _load_bank(family: String) -> Array[AudioStreamWAV]:
	return BANKS.bank(family)

func snapshot() -> Dictionary:
	var audible_ids: Array[int] = []
	var playing_voices := 0
	var design_slots := 0
	for slot in _slots:
		if slot.id != 0: audible_ids.append(int(slot.id))
		for player in slot.players:
			if player.playing: playing_voices += 1
		var voice: Variant = slot.get("design_voice")
		if is_instance_valid(voice):
			design_slots += 1
			playing_voices += int(voice.snapshot().motor_voices)
	return {"registered": _entries.size(), "audible": audible_ids.size(), "audible_ids": audible_ids,
		"playing_voices": playing_voices, "voice_limit": MAX_DESIGN_VOICES if design_slots > 0 else MAX_VOICES,
		"design_slots": design_slots, "design_voice_limit": MAX_DESIGN_VOICES,
		"beepers": _beepers.size(), "beeper_limit": MAX_BEEPERS, "range": RANGE}
