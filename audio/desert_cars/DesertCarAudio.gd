extends Node3D
## Bounded two-band mixer. Uses the SAME gearbox object as motion and HUD.
## Five roster families use different authored recordings, not one pitch-shifted WAV.
const BANKS := preload("res://audio/EngineBankCache.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
var drivetrain: RefCounted
var vehicle: Node3D
var _bank: Array[AudioStreamWAV] = []
var _layers: Array[AudioStreamPlayer3D] = []
var _indices := [-1,-1]
var _shift: AudioStreamPlayer3D
var _tire: AudioStreamPlayer3D
var _nitro: AudioStreamPlayer3D
var _last_shift := 0
var _range_clock := 0.0
var _in_range := true
var _last_throttle := 0.0
var _blowoff_cooldown := 0.0
var _family := ""
var _external_observing := false
var _last_observed_speed := 0.0

func bind(car: Node3D, state: RefCounted) -> void:
	vehicle = car
	drivetrain = state
	_last_shift = int(state.shift_serial) if state != null else 0
	_last_throttle = float(state.throttle) if state != null else 0.0
	_blowoff_cooldown = .2
	_external_observing = false
	if is_node_ready() and state != null: _apply_profile()

func _ready() -> void:
	if not is_instance_valid(vehicle) or drivetrain == null: set_process(false); return
	name = "DesertCarAudio"
	for i in 2: _layers.append(_player("EngineBand%d" % i,-80.0))
	_apply_profile()
	_shift = _player("ShiftBlowoff",-16.0)
	_shift.stream = load("res://audio/vehicle_fx/sport_blowoff_1.wav")
	_tire = _player("Wheelspin",-80.0)
	_tire.stream = _loop("res://audio/acoustic/skid_muscle.wav" if str(drivetrain.spec.engine_family)=="muscle" else "res://audio/acoustic/skid_street.wav")
	_nitro = _player("Nitro",-80.0)
	_nitro.stream = _loop("res://audio/vehicle_fx/air_brake.wav")

func _apply_profile() -> void:
	var family := str(drivetrain.spec.engine_family)
	if family != _family:
		_family = family
		_bank = BANKS.bank(family)
		_indices = [-1,-1]
	var bus: StringName = &"SFX" if AudioServer.get_bus_index("SFX")>=0 else &"Master"
	if float(drivetrain.spec.get("exhaust",0.0)) > .5: bus = _exhaust_bus()
	for player in _layers: player.bus = bus

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or drivetrain == null: queue_free(); return
	_range_clock -= delta
	_blowoff_cooldown = maxf(0.0,_blowoff_cooldown-delta)
	if _range_clock <= 0.0:
		_range_clock = .2
		var camera := get_viewport().get_camera_3d()
		# Drag has a listener at Dante's car; its wide side camera can be hundreds
		# of metres away. Keep only these two race mixers active and let spatial
		# attenuation use that listener instead of muting by camera distance.
		_in_range = vehicle.has_meta("desert_drag_physics") or (camera != null and camera.global_position.distance_squared_to(vehicle.global_position) < 85.0*85.0)
	var running := bool(vehicle.get("controlled")) or bool(vehicle.get("traffic")) or bool(vehicle.get("external_input")) or absf(float(vehicle.get("speed"))) > .15
	# Race controller owns physics while staging; revving there is still audible.
	running = running or (not vehicle.is_physics_processing() and float(drivetrain.rpm) > 1000.0)
	var active := _in_range and running and vehicle.is_visible_in_tree() and float(vehicle.get("health")) > 0.0 and not bool(vehicle.get("engine_disabled"))
	if not active:
		for player in _layers: player.stop()
		_tire.stop()
		_nitro.stop()
		_external_observing = false
		return
	_synchronize_external(delta)
	var ratio := clampf((float(drivetrain.rpm)-750.0)/maxf(1000.0,float(drivetrain.redline)-750.0),0.0,1.0)
	var band := ratio*6.0
	var low := mini(5,int(floor(band)))
	var fraction := band-float(low)
	var power := float(drivetrain.throttle)
	var cut := -8.0 if float(drivetrain.shift_remaining) > 0.0 else 0.0
	if drivetrain.limiter: cut -= 4.0
	var exhaust := float(drivetrain.spec.get("exhaust",0.0))
	for i in 2:
		var index := low+i
		var player := _layers[i]
		if index >= _bank.size(): continue
		if _indices[i] != index:
			player.stream = _bank[index]
			_indices[i] = index
			player.play()
		elif not player.playing: player.play()
		var weight := sqrt(maxf(.00001,1.0-fraction if i == 0 else fraction))
		player.volume_db = lerpf(player.volume_db,-19.0+linear_to_db(weight)+power*4.0+cut+exhaust*2.0,1.0-exp(-delta*25.0))
		# Small pitch interpolation inside each recording band; family/timbre comes
		# from the source bank. Gear changes drop RPM before this code runs.
		player.pitch_scale = clampf((.30+ratio)/(.30+float(index)/6.0),.75,1.32)
	if int(drivetrain.shift_serial) != _last_shift:
		_last_shift = int(drivetrain.shift_serial)
		_play_shift()
	elif _last_throttle > .65 and power < .25 and float(drivetrain.turbo_pressure) > .5:
		_play_shift()
	_last_throttle = power
	_loop_level(_tire,float(drivetrain.wheelspin),-18.0,delta)
	_loop_level(_nitro,1.0 if drivetrain.nitro_active else 0.0,-24.0,delta)

func _synchronize_external(delta: float) -> void:
	# These native drivers bypass DesertHandling. Never overwrite the player's
	# simulated transmission or either drag racer's authoritative RPM.
	var traffic := bool(vehicle.get("traffic"))
	var external := bool(vehicle.get("external_input"))
	if vehicle.has_meta("desert_drag_physics") or (bool(vehicle.get("controlled")) and not traffic and not external):
		_external_observing = false
		return
	var actual_speed := float(vehicle.get("speed"))
	if not _external_observing: _last_observed_speed = actual_speed
	var acceleration := (absf(actual_speed)-absf(_last_observed_speed))/maxf(.001,delta)
	var drive_load := 0.0
	if traffic:
		# Route following sets speed directly and does not populate throttle_input.
		drive_load = clampf(.25+acceleration*.20,0.0,1.0) if absf(actual_speed)>.15 else 0.0
		if bool(vehicle.get("blocked")) or bool(vehicle.get("junction_wait")): drive_load=0.0
	elif external:
		var pedal := float(vehicle.get("throttle_input"))
		drive_load = absf(pedal) if not bool(vehicle.get("brake_input")) and actual_speed*pedal >= 0.0 else 0.0
	drivetrain.follow_external_motion(actual_speed,drive_load,delta)
	_last_shift = int(drivetrain.shift_serial)
	_last_observed_speed = actual_speed
	_external_observing = true

func _play_shift() -> void:
	if _blowoff_cooldown > 0.0: return
	_blowoff_cooldown = .22
	var turbo := float(drivetrain.spec.boost_gain) > .01
	_shift.stream = load("res://audio/vehicle_fx/sport_blowoff_1.wav" if turbo else "res://audio/vehicle_fx/turbo_shift_0.wav")
	_shift.volume_db = -17.0 if turbo else -25.0
	_shift.play()

func _loop_level(player: AudioStreamPlayer3D, amount: float, level: float, delta: float) -> void:
	var target := level+linear_to_db(maxf(.0001,amount))
	player.volume_db = lerpf(player.volume_db,target,1.0-exp(-delta*16.0))
	if amount > .02 and not player.playing: player.play()
	elif amount <= .02 and player.volume_db < -55.0: player.stop()

func _player(label: String, level: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = label
	p.volume_db = level
	p.max_db = 1.0
	p.unit_size = 12.0
	p.max_distance = 85.0
	if AudioServer.get_bus_index("SFX") >= 0: p.bus = "SFX"
	add_child(p)
	return p

func _loop(path: String) -> AudioStreamWAV:
	var source := load(path) as AudioStreamWAV
	if source == null: return null
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = maxi(1,roundi(stream.get_length()*stream.mix_rate)-8)
	return stream

static func _exhaust_bus() -> StringName:
	const BUS := &"DesertRaceExhaust"
	if AudioServer.get_bus_index(BUS) >= 0: return BUS
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index,BUS)
	AudioServer.set_bus_send(index,&"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master")
	var saturation := AudioEffectDistortion.new()
	saturation.mode = AudioEffectDistortion.MODE_OVERDRIVE
	saturation.drive = .24
	saturation.post_gain = -2.0
	AudioServer.add_bus_effect(index,saturation)
	return BUS
