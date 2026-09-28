extends Node
## Original audio assets, native 3D emitters and bounded player/nearby engine mixers.
const V1_AUDIO := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
const SURFACES := preload("res://audio/v1_ambience/SurfaceResolver3D.gd")
const PROFILES := preload("res://audio/v1_ambience/AmbienceProfile.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const TANK_AUDIO := preload("res://audio/tank/TankAudio.gd")
const ROAD_SOUND := preload("res://audio/vehicle_fx/road.wav")
const AIR_BRAKE_SOUND := preload("res://audio/vehicle_fx/air_brake.wav")
const TURBO_SHIFT_SOUNDS := [preload("res://audio/vehicle_fx/turbo_shift_0.wav"), preload("res://audio/vehicle_fx/turbo_shift_1.wav"), preload("res://audio/vehicle_fx/turbo_shift_2.wav")]
const SPORT_BLOWOFF_SOUNDS := [preload("res://audio/vehicle_fx/sport_blowoff_0.wav"), preload("res://audio/vehicle_fx/sport_blowoff_1.wav"), preload("res://audio/vehicle_fx/sport_blowoff_2.wav")]
const NEARBY_VEHICLE_AUDIO := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const BED_OFFSETS := {"city":-10.0,"water":-6.0,"port":-15.0,"birds":-9.0,"crickets":-10.0,"workshop":-20.0}
var world
var layers: Array[AudioStreamPlayer] = []
var engine_car: CharacterBody3D
var radio: AudioStreamPlayer
var ambience: AudioStreamPlayer
var footsteps: AudioStreamPlayer3D
var beds: Dictionary = {}
var bed_gains := {"city":0.0,"water":0.0,"port":0.0,"birds":0.0,"crickets":0.0,"workshop":0.0}
var bed_targets := bed_gains.duplicate()
var detail: AudioStreamPlayer3D
var activity_audio
var vehicle_ambience
var radio_index := -1
var step_distance := 0.0
var previous := Vector3.ZERO
var family := ""
var engine_archetype := ""
var engine_gear := 1
var engine_rpm := 0.0
var engine_shift_cooldown := 0.0
var engine_load := 0.0
var engine_turbo_pressure := 0.0
var engine_last_throttle := 0.0
var engine_fx_cooldown := 0.0
var engine_fx_variant := 0
var engine_was_moving_fast := false
var tank_start_remaining := 0.0
var road_audio: AudioStreamPlayer
var shift_audio: AudioStreamPlayer
var air_brake_audio: AudioStreamPlayer
var water_steps: Node3D
var ambience_clock := .25
var detail_clock := 5.0
var detail_variant := 0
var detail_context := ""
var rng := RandomNumberGenerator.new()
const WATER_SOUND = preload("res://runtime/world/OriginalWaterStep.gd")
const FOOTSTEP_VOLUME_DB := -17.0
# Mesma ordem e nomes de `LivingCityAudio.stations()` da V1; o desligado vem depois da última.
const STATIONS := ["porto_fm","porto_noite","porto_groove","porto_brisa","porto_neon","porto_arcade","porto_pesada","porto_reggae","porto_club","porto_estrada","porto_cruise"]
const STATION_NAMES := ["PORTO FM · Empty Stretch","PORTO NOITE · Fusion Jazz","PORTO GROOVE · Wednesday Night","PORTO BRISA · Apple Cider","PORTO NEON · Synth Rock","PORTO ARCADE · Chiptune","PORTO PESADA · Metal Fusion","PORTO REGGAE · Sweet Coast","PORTO CLUB · Electronic Outlaw","PORTO ESTRADA · Freeway Fumes","PORTO CRUISE · Midnight Cruiser"]
const RADIO_VOLUME_DB := -12.0
var radio_car: CharacterBody3D
var radio_focus := 1.0
var radio_notice: Label
var radio_notice_time := 0.0
func _exit_tree() -> void:
	if is_instance_valid(vehicle_ambience) and vehicle_ambience.has_method("shutdown"):
		vehicle_ambience.shutdown()
	for channel in [radio, footsteps, detail, road_audio, shift_audio, air_brake_audio] + beds.values() + layers:
		if not is_instance_valid(channel): continue
		channel.stop()
		channel.stream = null
	beds.clear()
	layers.clear()
func _ready() -> void:
	rng.randomize()
	radio = AudioStreamPlayer.new()
	radio.name = "VehicleRadio"
	radio.bus = _bus(&"Music")
	radio.volume_db = RADIO_VOLUME_DB
	add_child(radio)
	_make_bed("city",V1_AUDIO.bed("street",0))
	_make_bed("water",V1_AUDIO.bed("water",1))
	_make_bed("port",V1_AUDIO.bed("workshop",1))
	_make_bed("birds",V1_AUDIO.bed("birds",1))
	_make_bed("crickets",V1_AUDIO.bed("crickets",0))
	_make_bed("workshop",V1_AUDIO.bed("workshop",0))
	ambience = beds.city
	detail = AudioStreamPlayer3D.new()
	detail.name = "NearbyV1Detail"
	detail.bus = _bus(&"Ambient")
	detail.max_distance = 55
	detail.unit_size = 8
	detail.volume_db = -12
	world.add_child(detail)
	footsteps = AudioStreamPlayer3D.new()
	# `unit_size` mais baixo que o de `Gameplay._audio_pool`/`_reload_audio` (9): na distância
	# real da câmera ortogonal (`CameraRig.EXTERIOR_OFFSET`, ~36 unidades) um valor alto (era 10)
	# atenuava pouquíssimo e o passo soava mais alto que tiro/recarga, que atenuavam muito mais.
	# `volume_db` inicial vem de `FOOTSTEP_VOLUME_DB`; cada passo aplica um jitter em cima (ver `_process`).
	footsteps.unit_size = 6
	footsteps.volume_db = FOOTSTEP_VOLUME_DB
	footsteps.bus = _bus(&"SFX")
	world.player.add_child(footsteps)
	previous = world.player.position
	water_steps = preload("res://runtime/world/WaterSteps.gd").new()
	world.add_child(water_steps)
	activity_audio = preload("res://audio/v1_ambience/ActivityAudioBridge.gd").new()
	activity_audio.world = world
	add_child(activity_audio)
	vehicle_ambience = NEARBY_VEHICLE_AUDIO.new()
	vehicle_ambience.name = "NearbyVehicleAudio"
	add_child(vehicle_ambience)
	if not vehicle_ambience.configure(world, world.player):
		push_warning("WorldAudio: nearby vehicle engine mixer could not be configured")
		vehicle_ambience.queue_free()
		vehicle_ambience = null
	for index in 7:
		# The listener camera sits about 36 m above the occupied car. In V1 the
		# driver's engine was foreground audio, so it must not fade with that gap.
		var layer := AudioStreamPlayer.new()
		layer.name = "PlayerEngineBand%d" % index
		layer.bus = _bus(&"SFX")
		layer.max_polyphony = 1
		add_child(layer)
		layers.append(layer)
	road_audio = AudioStreamPlayer.new()
	road_audio.name = "PlayerRoadNoise"
	road_audio.bus = _bus(&"SFX")
	var road_stream := ROAD_SOUND.duplicate() as AudioStreamWAV
	road_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	road_stream.loop_end = maxi(1, roundi(road_stream.get_length() * road_stream.mix_rate) - 8)
	road_audio.stream = road_stream
	add_child(road_audio)
	shift_audio = AudioStreamPlayer.new()
	shift_audio.name = "PlayerTurboRelease"
	shift_audio.bus = _bus(&"SFX")
	add_child(shift_audio)
	air_brake_audio = AudioStreamPlayer.new()
	air_brake_audio.name = "PlayerAirBrake"
	air_brake_audio.bus = _bus(&"SFX")
	add_child(air_brake_audio)
func _bus(preferred: StringName) -> StringName:
	return preferred if AudioServer.get_bus_index(preferred)>=0 else &"Master"
func _make_bed(id: String, stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.name = id.capitalize()+"Ambience"
	player.stream = stream
	player.bus = _bus(&"Ambient")
	player.volume_db = -80
	add_child(player)
	beds[id] = player
## V1 `VehicleRadioReceiver`: dirigindo, roda do mouse e R/LB/RB sintonizam. A pé a roda é da
## troca de arma (`Gameplay`), que `can_attack` já barra dentro do carro.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or not world.driving.occupied: return
	var direction := 0
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		direction = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
	elif event.is_action_pressed("radio_next"):
		direction = 1
	elif event.is_action_pressed("radio_previous"):
		direction = -1
	if direction == 0 or get_tree().paused or not _radio_tunable(): return
	_cycle_radio(direction)
	get_viewport().set_input_as_handled()

func _radio_tunable() -> bool:
	var session = world.session
	if session != null:
		if session.get("dialogue_open") == true or session.get("modal") == true: return false
		var rebinding: Variant = session.get("rebinding_action")
		if rebinding != null and not str(rebinding).is_empty(): return false
	var controls := get_node_or_null("/root/GameInput")
	return controls == null or controls.get("remapping") != true

func _cycle_radio(direction: int) -> void:
	var slot := radio_index if radio_index >= 0 else STATIONS.size()
	slot = posmod(slot+direction,STATIONS.size()+1)
	radio_index = slot if slot < STATIONS.size() else -1
	# Cada carro guarda a própria estação, como `radio_index` em PlayerCar/TrafficVehicle na V1.
	if is_instance_valid(radio_car):
		radio_car.set_meta(&"radio_index",radio_index)
		radio_car.set_meta(&"radio_position",0.0)
	_play_station(0.0)
	_show_station()

func _play_station(from: float) -> void:
	radio.stop()
	radio.stream = null
	if radio_index < 0: return
	var stream := load("res://audio/living_city/"+STATIONS[radio_index]+".ogg") as AudioStream
	if stream is AudioStreamOggVorbis: stream.loop = true
	radio.stream = stream
	if stream != null: radio.play(clampf(from,0.0,maxf(0.0,stream.get_length()-.5)))

## Entrar no carro liga a estação dele (a primeira, se nunca foi sintonizado) e retoma do ponto
## onde parou; sair para a rádio e guarda a posição. Trocar de carro não leva a música junto.
func _update_radio(delta: float) -> void:
	var car: CharacterBody3D = world.driving.car if world.driving.occupied and is_instance_valid(world.driving.car) else null
	if car != radio_car:
		if is_instance_valid(radio_car) and radio.playing:
			radio_car.set_meta(&"radio_position",radio.get_playback_position())
		radio_car = car
		if car == null:
			radio.stop()
			radio_notice_time = 0.0
		else:
			radio_index = int(car.get_meta(&"radio_index",0))
			_play_station(float(car.get_meta(&"radio_position",0.0)))
	if car != null:
		var dialogue: bool = world.session != null and world.session.get("dialogue_open") == true
		radio_focus = move_toward(radio_focus,.2 if dialogue else 1.0,delta*3.0)
		radio.volume_db = RADIO_VOLUME_DB+linear_to_db(maxf(radio_focus,.001))
	radio_notice_time = maxf(0.0,radio_notice_time-delta)
	if is_instance_valid(radio_notice):
		radio_notice.visible = car != null and radio_notice_time > 0.0 and not get_tree().paused and not (world.session != null and world.session.modal)
		radio_notice.modulate.a = clampf(minf(radio_notice_time/.18,(2.0-radio_notice_time)/.18),0,1)

func _show_station() -> void:
	if not is_instance_valid(radio_notice):
		var layer := CanvasLayer.new()
		layer.layer = 8
		add_child(layer)
		radio_notice = Label.new()
		radio_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		radio_notice.offset_left = -264
		radio_notice.offset_right = -24
		radio_notice.offset_top = 100
		radio_notice.offset_bottom = 138
		radio_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		radio_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ui_style = preload("res://ui/GameStyle.gd")
		radio_notice.add_theme_font_override("font",ui_style.STRONG)
		radio_notice.add_theme_font_size_override("font_size",16)
		radio_notice.add_theme_color_override("font_color",ui_style.TEXT)
		radio_notice.add_theme_stylebox_override("normal",ui_style.compact(false,8))
		layer.add_child(radio_notice)
	radio_notice.text = STATION_NAMES[radio_index] if radio_index >= 0 else "RÁDIO DESLIGADO"
	radio_notice_time = 2.0
	radio_notice.show()
	radio_notice.modulate.a=0

func _process(delta: float) -> void:
	_update_ambience(delta)
	_update_radio(delta)
	var moving: bool = world.driving.occupied
	var distance: float = world.player.position.distance_to(previous)
	previous = world.player.position
	var interior: bool = world.session!=null and not str(world.session.state.place_id).is_empty()
	if moving or distance>=2:
		step_distance = 0
		water_steps.clear_trail()
	elif interior:
		water_steps.clear_trail()
	if not moving and distance < 2 and world.player.is_on_floor():
		# Passada real: uma pessoa correndo não dá o dobro de passos por segundo que andando,
		# dá passos mais LONGOS. Distância fixa (0.8 m) por passo ignorava isso: em sprint
		# (6.5 m/s) virava uma metralhadora de ~8 passos/s. Aqui a passada cresce com a
		# velocidade (0.62 m parado/lento até ~1.85 m em sprint), prendendo a cadência a uma
		# faixa humana de ~3 a 3.5 passos/s em qualquer velocidade.
		var speed := distance / maxf(delta, .0001)
		var stride := clampf(speed / 3.2, .62, 1.85)
		step_distance += distance
		if step_distance > stride:
			step_distance = 0
			var water: bool = water_steps.actor_step(world.player,Input.is_action_pressed("sprint"),interior)
			var surface := "water" if water else SURFACES.resolve(world,_raining())
			footsteps.stream = WATER_SOUND.sound(rng.randi_range(0,3)) if water else V1_AUDIO.footstep(surface,rng.randi_range(0,3))
			footsteps.pitch_scale = 1.0 if water else V1_AUDIO.footstep_pitch(surface)*rng.randf_range(.97,1.03)
			# Passo sutil: leve variação de volume por passo (pé esquerdo/direito nunca bate
			# exatamente igual) em vez do mesmo dB fixo toda vez.
			footsteps.volume_db = FOOTSTEP_VOLUME_DB + rng.randf_range(-1.5,1.5)
			footsteps.play()
	if not moving or not is_instance_valid(world.driving.car) or world.driving.car.health <= 0 or world.driving.car.engine_disabled:
		engine_car = null
		engine_archetype = ""
		for layer in layers: if layer.playing: layer.stop()
		for channel in [road_audio, shift_audio, air_brake_audio]: if channel.playing: channel.stop()
		return
	var current_car: CharacterBody3D = world.driving.car
	_sync_engine_family(current_car)
	tank_start_remaining = maxf(0.0, tank_start_remaining - delta)
	var tops: Array = ENGINE_PROFILE.GEAR_TOPS.get(family, ENGINE_PROFILE.GEAR_TOPS.street)
	var nominal: Array = ENGINE_PROFILE.NOMINAL.get(family, ENGINE_PROFILE.NOMINAL.street)
	var ratio := clampf(absf(current_car.speed) / maxf(float(current_car.max_forward_speed), 1.0), 0.0, 1.0)
	var throttle := absf(float(current_car.throttle_input))
	if family == "electric" and ratio < 0.02 and throttle < 0.01:
		for layer in layers: if layer.playing: layer.stop()
		if road_audio.playing: road_audio.stop()
		return
	engine_load = lerpf(engine_load, throttle, 1.0 - exp(-delta * 9.0))
	engine_shift_cooldown = maxf(0.0, engine_shift_cooldown - delta)
	engine_fx_cooldown = maxf(0.0, engine_fx_cooldown - delta)
	var previous_gear := engine_gear
	if ratio < 0.006:
		engine_gear = 1
		engine_shift_cooldown = 0.0
	elif engine_shift_cooldown <= 0.0:
		if engine_gear < tops.size() and ratio > float(tops[engine_gear - 1]):
			engine_gear += 1
			engine_shift_cooldown = 0.25 if family in ["truck", "bus", "fire_diesel", "tank"] else 0.16
		elif engine_gear > 1 and ratio < float(tops[engine_gear - 2]) - 0.045:
			engine_gear -= 1
			engine_shift_cooldown = 0.16
	var idle := float(nominal[0]) / float(nominal[6])
	var gear_top := float(tops[engine_gear - 1])
	var top_fraction := lerpf(0.86, 1.0, float(engine_gear - 1) / maxf(float(tops.size() - 1), 1.0))
	if engine_gear == tops.size(): top_fraction = 0.87
	var target := maxf(idle, clampf(ratio / maxf(gear_top, 0.01) * top_fraction, 0.0, 1.0))
	if ratio < 0.03: target = maxf(target, idle + engine_load * (1.0 - idle) * 0.62)
	engine_rpm = lerpf(engine_rpm, target, 1.0 - exp(-delta * (18.0 if ratio > 0.03 else 8.0)))
	var spec: Dictionary = FLEET.spec(engine_archetype)
	_update_vehicle_foley(current_car, spec, ratio, throttle, previous_gear)
	var tint := pow(maxf(float(spec.get("engine_pitch", 1.0)), 0.3), 0.35)
	var cycles := float(nominal[6]) * engine_rpm * tint
	var timbre := cycles / maxf(tint, 0.3) * (0.8 + 0.2 * engine_load)
	var lower := 0
	while lower < 5 and timbre > float(nominal[lower + 1]): lower += 1
	var upper := lower + 1
	var blend := clampf(log(maxf(timbre, 0.5) / float(nominal[lower])) / maxf(log(float(nominal[upper]) / float(nominal[lower])), 0.001), 0.0, 1.0)
	var master := -20.0 + engine_load * 7.0 + engine_rpm * 6.5 + ratio * 1.5
	if family == "vq35": master -= 5.0
	if family == "electric": master -= 13.0
	if family == "tank" and tank_start_remaining > 0.0:
		master += linear_to_db(maxf(0.005, smoothstep(0.6, 2.1, TANK_AUDIO.START_SECONDS - tank_start_remaining)))
	for index in 7:
		var share := cos(blend * PI * 0.5) if index == lower else (sin(blend * PI * 0.5) if index == upper else 0.0)
		var layer := layers[index]
		if share <= 0.002 or layer.stream == null:
			if layer.playing: layer.stop()
			continue
		layer.pitch_scale = clampf(cycles / float(nominal[index]), 0.35, 3.0)
		layer.volume_db = master + linear_to_db(share)
		if not layer.playing: layer.play()

func _sync_engine_family(car: CharacterBody3D) -> void:
	var archetype := str(car.archetype)
	if engine_car == car and engine_archetype == archetype: return
	engine_car = car
	engine_archetype = archetype
	engine_gear = 1
	engine_rpm = 0.0
	engine_load = 0.0
	engine_shift_cooldown = 0.0
	engine_turbo_pressure = 0.0
	engine_last_throttle = 0.0
	engine_fx_cooldown = 0.0
	engine_was_moving_fast = false
	for channel in [road_audio, shift_audio, air_brake_audio]: if channel.playing: channel.stop()
	var next_family: String = ENGINE_PROFILE.bank_family(archetype)
	tank_start_remaining = 0.0
	if next_family == "tank":
		road_audio.stream = TANK_AUDIO.tracks_stream()
		if TANK_AUDIO.claim_start(car):
			shift_audio.stream = TANK_AUDIO.start_stream()
			shift_audio.pitch_scale = 1.0
			shift_audio.volume_db = -13.0
			shift_audio.play()
			tank_start_remaining = TANK_AUDIO.START_SECONDS
	elif family == "tank":
		var road_stream := ROAD_SOUND.duplicate() as AudioStreamWAV
		road_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		road_stream.loop_end = maxi(1, roundi(road_stream.get_length() * road_stream.mix_rate) - 8)
		road_audio.stream = road_stream
	if next_family == family: return
	family = next_family
	for index in 7:
		layers[index].stop()
		if family == "tank":
			var bank := TANK_AUDIO.engine_bank()
			layers[index].stream = bank[index] if bank.size() == 7 else null
			continue
		var source := load("res://audio/acoustic/engine_%s_%d.wav"%[family,index])
		if not source is AudioStreamWAV:
			layers[index].stream = null
			continue
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = maxi(1, roundi(stream.get_length()*stream.mix_rate) - 8)
		layers[index].stream = stream

func _update_vehicle_foley(car: CharacterBody3D, spec: Dictionary, ratio: float, throttle: float, previous_gear: int) -> void:
	if family == "tank":
		var gain := TANK_AUDIO.tracks_gain(float(car.speed))
		if gain <= 0.001:
			road_audio.stop()
		else:
			road_audio.pitch_scale = TANK_AUDIO.tracks_pitch(float(car.speed))
			road_audio.volume_db = -17.0 + linear_to_db(gain)
			if not road_audio.playing: road_audio.play()
		engine_last_throttle = throttle
		return
	# V1 VehicleEngineSound._update_road: an absolute-speed cue independent of RPM.
	if ratio < 0.04:
		if road_audio.playing: road_audio.stop()
	else:
		var heavy := family in ["truck", "bus", "fire_diesel"]
		road_audio.pitch_scale = clampf((0.72 + ratio * 0.85) * (0.78 if heavy else 1.0), 0.4, 2.0)
		road_audio.volume_db = -42.0 + ratio * 21.0 + (3.0 if heavy else 0.0)
		if not road_audio.playing: road_audio.play()
	var heavy_turbo := family in ["bus", "fire_diesel"]
	var sport_turbo := bool(spec.get("turbo_audio", false))
	if sport_turbo:
		var pressure_target := throttle * smoothstep(0.24, 0.82, engine_rpm)
		engine_turbo_pressure = lerpf(engine_turbo_pressure, pressure_target,
			1.0 - exp(-get_process_delta_time() * (3.6 if pressure_target > engine_turbo_pressure else 7.0)))
	else:
		engine_turbo_pressure = 0.0
	if engine_gear > previous_gear and heavy_turbo and (engine_load > 0.20 or engine_rpm > 0.30):
		_play_vehicle_fx(TURBO_SHIFT_SOUNDS, clampf(-7.0 + engine_load * 6.0 + engine_rpm * 3.0, -14.0, 2.0) - (8.0 if family == "truck" else 0.0))
	elif engine_gear > previous_gear and sport_turbo and engine_turbo_pressure > 0.16:
		_play_vehicle_fx(SPORT_BLOWOFF_SOUNDS, clampf(-11.0 + engine_turbo_pressure * 10.0 + engine_rpm * 2.0, -13.0, -1.0))
	if heavy_turbo and engine_fx_cooldown <= 0.0 and engine_last_throttle > 0.65 and throttle < 0.15 and engine_rpm > 0.42:
		_play_vehicle_fx(TURBO_SHIFT_SOUNDS, -2.0)
	if sport_turbo and engine_fx_cooldown <= 0.0 and engine_last_throttle > 0.58 and throttle < 0.16 and engine_turbo_pressure > 0.18:
		_play_vehicle_fx(SPORT_BLOWOFF_SOUNDS, clampf(-11.0 + engine_turbo_pressure * 10.0 + engine_rpm * 2.0, -13.0, -1.0))
		engine_turbo_pressure *= 0.24
	if family in ["truck", "bus", "fire_diesel"]:
		if absf(float(car.speed)) > 1.25: engine_was_moving_fast = true
		elif engine_was_moving_fast and absf(float(car.speed)) < 0.375 and throttle < 0.1:
			engine_was_moving_fast = false
			air_brake_audio.stream = AIR_BRAKE_SOUND
			air_brake_audio.volume_db = -6.0
			air_brake_audio.pitch_scale = randf_range(0.96, 1.04)
			air_brake_audio.play()
	engine_last_throttle = throttle

func _play_vehicle_fx(sounds: Array, volume: float) -> void:
	if engine_fx_cooldown > 0.0: return
	engine_fx_variant = (engine_fx_variant + 1) % sounds.size()
	shift_audio.stream = sounds[engine_fx_variant]
	shift_audio.volume_db = volume
	shift_audio.pitch_scale = 0.96 + engine_rpm * 0.12
	shift_audio.play()
	engine_fx_cooldown = 0.18

func _update_ambience(delta: float) -> void:
	if world.session == null: return
	ambience_clock += delta
	var focus := .35 if world.session.dialogue_open else (.62 if world.session.modal else 1.0)
	if ambience_clock >= .25:
		ambience_clock = 0
		var state = world.session.state
		bed_targets = PROFILES.targets(str(state.region_id),str(state.place_id),world.player.global_position,_dark(),_nearby_crowd_gain())
		detail_context = PROFILES.activity_context(str(state.region_id),str(state.place_id),world.player.global_position)
	for id in beds:
		var target := float(bed_targets.get(id,0.0))*focus
		bed_gains[id] = lerpf(float(bed_gains[id]),target,1.0-exp(-delta/.7))
		var offset: float = BED_OFFSETS[id]
		var player: AudioStreamPlayer = beds[id]
		player.volume_db = offset+linear_to_db(maxf(float(bed_gains[id]),.0001))
		if bed_gains[id]>.005 and not player.playing: player.play(rng.randf_range(0,maxf(0,player.stream.get_length()-1)))
		elif bed_gains[id]<=.001 and player.playing: player.stop()
	detail_clock -= delta
	if focus<.8 or detail_context.is_empty():
		if detail.playing and not str(world.session.state.place_id).is_empty() and detail_context!="workshop": detail.stop()
		return
	if detail_clock<=0 and not detail.playing:
		_play_context_detail()

func _play_context_detail() -> void:
	var kind := ""
	var source: Vector3 = world.player.global_position
	match detail_context:
		"workshop": kind = "workshop"
		"salvage","sawmill": kind = "scrap"
		"port","dock": kind = "gull" if not _dark() and rng.randf()<.65 else "ship_horn"
		"nature": kind = "dog" if _dark() else "birds"
		"city": kind = "dog" if _dark() else ""
	if kind.is_empty():
		detail_clock = rng.randf_range(12,24)
		return
	if kind=="scrap": detail.stream = V1_AUDIO.regional("scrap",detail_variant)
	else: detail.stream = V1_AUDIO.detail(kind,detail_variant)
	detail_variant = (detail_variant+1)%6
	if detail.stream == null:
		detail_clock = 20
		return
	var angle := rng.randf_range(-PI,PI)
	var distance := rng.randf_range(5,14)
	detail.global_position = source+Vector3(cos(angle)*distance,1.2,sin(angle)*distance)
	detail.max_distance = 90 if kind=="ship_horn" else 48
	detail.volume_db = -6 if kind=="ship_horn" else (-14 if kind=="workshop" else -10)
	detail.pitch_scale = rng.randf_range(.94,1.04)
	detail.play()
	detail_clock = rng.randf_range(18,34) if kind in ["gull","ship_horn"] else rng.randf_range(8,18)

func _nearby_crowd_gain() -> float:
	var count := 0
	for actor in world.people:
		if is_instance_valid(actor) and actor.visible and actor.global_position.distance_to(world.player.global_position)<12:
			count += 1
			if count>=4: break
	return clampf(.25+float(count)*.2,.25,1.0)

func _dark() -> bool:
	var weather = world.session.weather
	if weather == null: return false
	var time := float(weather.time_of_day)
	return time<.28 or time>.78

func _raining() -> bool:
	var weather = world.session.weather
	return weather!=null and world.session.state.region_id=="harbor" and int(weather.weather_state) in [1,2] and world.session.state.place_id.is_empty()
