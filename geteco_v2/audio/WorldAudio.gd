extends Node
## Original audio assets, native 3D emitters and bounded player/nearby engine mixers.
const V1_AUDIO := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
const SURFACES := preload("res://audio/v1_ambience/SurfaceResolver3D.gd")
const PROFILES := preload("res://audio/v1_ambience/AmbienceProfile.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const NEARBY_VEHICLE_AUDIO := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const BED_OFFSETS := {"city":-10.0,"water":-6.0,"port":-15.0,"birds":-9.0,"crickets":-10.0,"workshop":-20.0}
var world
var layers: Array[AudioStreamPlayer3D] = []
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
var resolved_families: Dictionary = {}
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
	for channel in [radio, footsteps, detail] + beds.values() + layers:
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
		var layer := AudioStreamPlayer3D.new()
		layer.max_distance = 45
		layer.unit_size = 12
		world.add_child(layer)
		layers.append(layer)
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
	if is_instance_valid(radio_notice): radio_notice.visible = car != null and radio_notice_time > 0.0

func _show_station() -> void:
	if not is_instance_valid(radio_notice):
		var layer := CanvasLayer.new()
		layer.layer = 8
		add_child(layer)
		radio_notice = Label.new()
		radio_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		radio_notice.position = Vector2(-230,82)
		radio_notice.size = Vector2(460,58)
		radio_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		radio_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radio_notice.add_theme_font_size_override("font_size",18)
		radio_notice.add_theme_color_override("font_color",Color("f2e2b9"))
		radio_notice.add_theme_color_override("font_outline_color",Color("172022"))
		radio_notice.add_theme_constant_override("outline_size",6)
		layer.add_child(radio_notice)
	radio_notice.text = STATION_NAMES[radio_index] if radio_index >= 0 else "RÁDIO DESLIGADO"
	radio_notice_time = 3.0
	radio_notice.show()

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
	if not moving:
		engine_car = null
		engine_archetype = ""
		for layer in layers: if layer.playing: layer.stop()
		return
	var current_car: CharacterBody3D = world.driving.car
	if not is_instance_valid(current_car): return
	_sync_engine_family(current_car)
	var ratio: float = absf(engine_car.speed)/maxf(engine_car.max_forward_speed,1)
	var gear := mini(5,int(ratio*6))
	var rpm := clampf(.15+fmod(ratio*6,1)*.7+absf(engine_car.throttle_input)*.12,0,1)*6
	for index in 7:
		var weight := maxf(0,1-absf(rpm-index))
		layers[index].global_position = engine_car.global_position
		layers[index].volume_db = linear_to_db(maxf(.0001,sqrt(weight)))-17
		layers[index].pitch_scale = lerpf(layers[index].pitch_scale,1.0+gear*.015,minf(1,delta*5))
		if layers[index].stream != null and not layers[index].playing: layers[index].play()

func _sync_engine_family(car: CharacterBody3D) -> void:
	var archetype := str(car.archetype)
	if engine_car == car and engine_archetype == archetype: return
	engine_car = car
	engine_archetype = archetype
	var next_family := ""
	if resolved_families.has(archetype):
		next_family = str(resolved_families[archetype])
	else:
		var spec: Dictionary = FLEET.spec(archetype)
		next_family = str(spec.get("engine_family","sport"))
		if not ResourceLoader.exists("res://audio/acoustic/engine_"+next_family+"_0.wav"):
			next_family = "street"
		resolved_families[archetype] = next_family
	if next_family == family: return
	family = next_family
	for index in 7:
		var source := load("res://audio/acoustic/engine_%s_%d.wav"%[family,index])
		if not source is AudioStreamWAV:
			layers[index].stream = null
			continue
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		layers[index].stream = stream

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
