extends Node3D
## Bounded two-band mixer. Uses the SAME gearbox object as motion and HUD.
## Legacy banks contain offline combustion synthesis, not field recordings.
const BANKS := preload("res://audio/EngineBankCache.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
var drivetrain: RefCounted
var vehicle: Node3D
var _bank: Array[AudioStreamWAV] = []
var _layers: Array[AudioStreamPlayer3D] = []
var _indices := [-1,-1]
var _shift: AudioStreamPlayer3D
var _tire: AudioStreamPlayer3D
var _last_shift := 0
var _range_clock := 0.0
var _in_range := true
var _last_throttle := 0.0
var _blowoff_cooldown := 0.0
var _family := ""
var _external_observing := false
var _last_observed_speed := 0.0
var _foreground := false
var _recorded_idle: AudioStreamPlayer3D
var _recorded_path := ""

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
	# The driver's close race listener must not amplify rubber above the motor.
	_tire.max_db = -24.0
	_tire.unit_size = 4.0
	_tire.stream = _loop("res://audio/acoustic/skid_muscle.wav" if str(drivetrain.spec.engine_family)=="muscle" else "res://audio/acoustic/skid_street.wav")

func _apply_profile() -> void:
	var family := str(drivetrain.spec.engine_family)
	if family != _family:
		_family = family
		_bank = BANKS.bank(family)
		_indices = [-1,-1]
	var bus: StringName = &"SFX" if AudioServer.get_bus_index("SFX")>=0 else &"Master"
	for player in _layers: player.bus = bus
	_sync_recorded_idle()

func _sync_recorded_idle() -> void:
	var id := str(drivetrain.car_id)
	var path := ""
	if id == "desert_bison": path = "res://audio/desert_cars/bison_idle.wav"
	elif id in ["desert_coyote","desert_coyote_drag"]: path = "res://audio/desert_cars/coyote_idle.wav"
	if path == _recorded_path: return
	_recorded_path = path
	if is_instance_valid(_recorded_idle):
		_recorded_idle.free()
		_recorded_idle = null
	if path.is_empty(): return
	_recorded_idle = _player("RecordedIdle",-80.0)
	_recorded_idle.stream = _loop(path)
	# Reapply foreground settings when tuning rebinds an occupied vehicle.
	_foreground = false

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or drivetrain == null: queue_free(); return
	# Match WorldAudio's foreground engine for Dante. A raised or cinematic
	# camera must not attenuate/mute his own motor; NPCs keep spatial falloff.
	var foreground := bool(vehicle.get("controlled")) and not bool(vehicle.get("traffic")) and not bool(vehicle.get("external_input"))
	if foreground != _foreground:
		_foreground = foreground
		for player in _layers + [_shift, _tire]:
			player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if foreground else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			player.max_distance = 0.0 if foreground else 85.0
			player.panning_strength = 0.0 if foreground else 1.0
			player.attenuation_filter_db = 0.0 if foreground else -24.0
		if is_instance_valid(_recorded_idle):
			_recorded_idle.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if foreground else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			_recorded_idle.max_distance = 0.0 if foreground else 85.0
			_recorded_idle.panning_strength = 0.0 if foreground else 1.0
			_recorded_idle.attenuation_filter_db = 0.0 if foreground else -24.0
		_range_clock = 0.0
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
	var active := (_foreground or _in_range) and running and vehicle.is_visible_in_tree() and float(vehicle.get("health")) > 0.0 and not bool(vehicle.get("engine_disabled"))
	if not active:
		for player in _layers: player.stop()
		_tire.stop()
		_shift.stop()
		if is_instance_valid(_recorded_idle): _recorded_idle.stop()
		_external_observing = false
		return
	_synchronize_external(delta)
	# Each nominal value is complete four-stroke cycles per second: RPM / 120.
	# Align both bands to that SAME rate, otherwise the crossfade plays two
	# incompatible notes and produces beating/chirps as the engine accelerates.
	var nominal: Array = PROFILE.NOMINAL.get(_family, PROFILE.NOMINAL.street)
	var cycles := maxf(1.0,float(drivetrain.rpm)/120.0)
	var low := 0
	while low < 5 and cycles > float(nominal[low+1]): low += 1
	var fraction := clampf(log(cycles/float(nominal[low]))/log(float(nominal[low+1])/float(nominal[low])),0.0,1.0)
	var power := float(drivetrain.throttle)
	var cut := -8.0 if float(drivetrain.shift_remaining) > 0.0 else 0.0
	if drivetrain.limiter: cut -= 4.0
	var exhaust := float(drivetrain.spec.get("exhaust",0.0))
	# Injection increases engine load. It is not an external air-brake purge.
	var nitro_load := 1.5 if drivetrain.nitro_active else 0.0
	# Real idle recordings supply low-speed character for these two families.
	# Do not stretch an idle recording across the entire rev range: fade it out
	# before 2000 RPM, leaving the RPM-aligned load banks in charge.
	var idle_weight := 0.0
	if is_instance_valid(_recorded_idle):
		idle_weight = (1.0-smoothstep(1050.0,2000.0,float(drivetrain.rpm)))*(1.0-power*.4)
		_recorded_idle.pitch_scale = clampf(float(drivetrain.rpm)/(750.0 if _family == "diesel" else 900.0),.85,1.6)
		_loop_level(_recorded_idle,idle_weight,-14.0,delta)
	var synthesized_gain := linear_to_db(1.0-idle_weight*.82)
	for i in 2:
		var index := low+i
		# Adjacent bands alternate players. Keep the shared band playing through
		# every boundary instead of restarting both samples at audible volume.
		var slot := index % 2
		var player := _layers[slot]
		if index >= _bank.size(): continue
		if _indices[slot] != index:
			player.volume_db = -80.0
			player.stream = _bank[index]
			_indices[slot] = index
			player.play()
		elif not player.playing: player.play()
		var weight := sqrt(maxf(.00001,1.0-fraction if i == 0 else fraction))
		player.volume_db = lerpf(player.volume_db,-19.0+linear_to_db(weight)+power*4.0+cut+exhaust*2.0+nitro_load+synthesized_gain,1.0-exp(-delta*25.0))
		player.pitch_scale = clampf(cycles/float(nominal[index]),.35,3.0)
	if int(drivetrain.shift_serial) != _last_shift:
		_last_shift = int(drivetrain.shift_serial)
		_play_shift()
	elif _last_throttle > .65 and power < .25 and float(drivetrain.turbo_pressure) > .5:
		_play_shift()
	_last_throttle = power
	_loop_level(_tire,float(drivetrain.wheelspin),-28.0,delta)

func has_wheelspin_voice() -> bool:
	# Only claim the longitudinal tire sound while it is actually being mixed.
	# Braking/cornering remain owned by VehicleTireEffects.
	return is_instance_valid(_tire) and _tire.playing and drivetrain != null and float(drivetrain.wheelspin) > .02

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
	# Aspirated engines have no pressurized intake to vent. A stock diesel also
	# does not close a gasoline throttle plate on shifts. The RPM/load dip is
	# already supplied by the authoritative transmission.
	if float(drivetrain.spec.boost_gain) <= .01 or _family == "diesel" or float(drivetrain.turbo_pressure) < .25: return
	_blowoff_cooldown = .22
	_shift.volume_db = -23.0
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
