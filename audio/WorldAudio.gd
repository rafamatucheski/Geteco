extends Node
## Original audio assets, native 3D emitters and bounded player/nearby engine mixers.
const V1_AUDIO := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
const SURFACES := preload("res://audio/v1_ambience/SurfaceResolver3D.gd")
const PROFILES := preload("res://audio/v1_ambience/AmbienceProfile.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const ENGINE_BANKS := preload("res://audio/EngineBankCache.gd")
const DESIGN_BANKS := preload("res://audio/EngineDesignBanks.gd")
const DESIGN_VOICE := preload("res://audio/EngineDesignVoice.gd")
const DESIGN_CATALOG := preload("res://audio/FleetEngineDesign.gd")
const TANK_AUDIO := preload("res://audio/tank/TankAudio.gd")
const SNOWMOBILE_AUDIO := preload("res://audio/snowmobile/SnowmobileAudio.gd")
const ROAD_SOUND := preload("res://audio/vehicle_fx/road.wav")
const AIR_BRAKE_SOUND := preload("res://audio/vehicle_fx/air_brake.wav")
const TURBO_SHIFT_SOUNDS := [preload("res://audio/vehicle_fx/turbo_shift_0.wav"), preload("res://audio/vehicle_fx/turbo_shift_1.wav"), preload("res://audio/vehicle_fx/turbo_shift_2.wav")]
const SPORT_BLOWOFF_SOUNDS := [preload("res://audio/vehicle_fx/sport_blowoff_0.wav"), preload("res://audio/vehicle_fx/sport_blowoff_1.wav"), preload("res://audio/vehicle_fx/sport_blowoff_2.wav")]
const FIREFLY := preload("res://audio/FireflyBank.gd")
## Famílias que estouram o escapamento ao tirar o pé do acelerador em giro alto.
const BACKFIRE_FAMILIES := ["muscle", "sport", "vq35", "m8_v8", "rosso_v12"]
const REVERSE_BEEP_FAMILIES := ["truck", "bus", "fire_diesel"]
const NEARBY_VEHICLE_AUDIO := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const FOOTSTEP_CADENCE := preload("res://audio/FootstepCadence.gd")
## Cidade viva em Harbor: passos e falas dos pedestres, burburinho, leitos de rua e brisa e a
## mixagem nova dos leitos/detalhes. GETECO_CITY_LIFE_AUDIO=0 desliga (A/B) e volta ao anterior.
const CITY_LIFE := preload("res://audio/city_life/CityLifeAudio.gd")
const BED_OFFSETS := {"dockside":-12.0,"swell":-9.0,"rocks":-11.0,"traffic":-12.0,"city":-10.0,"water":-6.0,"port":-15.0,"birds":-9.0,"crickets":-10.0,"workshop":-20.0}
var world
var layers: Array[AudioStreamPlayer] = []
var engine_car: CharacterBody3D
var design_voice: Node3D
var design_rpm := 0.0
var design_cut := 0.0
var design_last_shift := 0
var radio: AudioStreamPlayer
var ambience: AudioStreamPlayer
var footsteps: AudioStreamPlayer3D
var beds: Dictionary = {}
var bed_gains := {"dockside":0.0,"swell":0.0,"rocks":0.0,"traffic":0.0,"city":0.0,"water":0.0,"port":0.0,"birds":0.0,"crickets":0.0,"workshop":0.0}
var bed_targets := bed_gains.duplicate()
var detail: AudioStreamPlayer3D
var activity_audio
var vehicle_ambience
var city_life: Node3D
var _city_life_mix := false
## Região usada na última atualização dos leitos (a mixagem nova vale só em CITY_LIFE.REGIONS).
var _bed_region := ""
var radio_index := -1
var step_distance := 0.0
var previous := Vector3.ZERO
var family := ""
## Banco cujos fluxos estão nas `layers`: `family` ou a ponte `street` enquanto ela carrega.
var engine_bank_family := ""
var engine_swap_gain := 1.0
const ENGINE_BANK_SWAP_SECONDS := 0.12
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
## Camadas gravadas no Firefly: estouro/assobio do turbo, compressor do muscle e bipe de ré.
var extra_audio: AudioStreamPlayer
var blower_audio: AudioStreamPlayer
var reverse_audio: AudioStreamPlayer
var extra_cooldown := 0.0
var _blowoff_mix: Array = []
var _turbo_shift_mix: Array = []
var water_steps: Node3D
var ambience_clock := .25
var detail_clock := 5.0
var detail_variant := 0
var detail_context := ""
var rng := RandomNumberGenerator.new()
const WATER_SOUND = preload("res://runtime/world/OriginalWaterStep.gd")
const FOOTSTEP_VOLUME_DB := -17.0
# Índices V1 preservados; a estação do deserto é acrescentada antes do desligado.
const STATIONS := ["porto_fm","porto_noite","porto_groove","porto_brisa","porto_neon","porto_arcade","porto_pesada","porto_reggae","porto_club","porto_estrada","porto_cruise","fronteira_country"]
const STATION_NAMES := ["PORTO FM · Empty Stretch","PORTO NOITE · Fusion Jazz","PORTO GROOVE · Wednesday Night","PORTO BRISA · Apple Cider","PORTO NEON · Synth Rock","PORTO ARCADE · Chiptune","PORTO PESADA · Metal Fusion","PORTO REGGAE · Sweet Coast","PORTO CLUB · Electronic Outlaw","PORTO ESTRADA · Freeway Fumes","PORTO CRUISE · Midnight Cruiser","FRONTEIRA COUNTRY"]
const COUNTRY_STATION := 11
const RADIO_VOLUME_DB := -6.0
var radio_car: CharacterBody3D
## Música exclusiva de sala pausa só esta voz de rádio; estação e posição de
## reprodução continuam do veículo. A referência fraca também se recupera no free.
var _scoped_music_owner: WeakRef
var radio_notice: Label
var radio_notice_time := 0.0

func _exit_tree() -> void:
	if is_instance_valid(design_voice): design_voice.stop()
	if is_instance_valid(vehicle_ambience) and vehicle_ambience.has_method("shutdown"):
		vehicle_ambience.shutdown()
	for channel in [radio, footsteps, detail, road_audio, shift_audio, air_brake_audio, extra_audio, blower_audio, reverse_audio] + beds.values() + layers:
		if not is_instance_valid(channel): continue
		channel.stop()
		channel.stream = null
	beds.clear()
	layers.clear()
func _ready() -> void:
	DESIGN_BANKS.prewarm.call_deferred(get_tree())
	rng.randomize()
	var desert_ambience := preload("res://audio/desert_ambience/DesertAmbience.gd").new()
	desert_ambience.name = "DesertAmbience"
	desert_ambience.world = world
	add_child(desert_ambience)
	radio = AudioStreamPlayer.new()
	radio.name = "VehicleRadio"
	radio.bus = _bus(&"Radio")
	radio.volume_db = RADIO_VOLUME_DB
	add_child(radio)
	# Leitos gerados no ElevenLabs (2026-10-16): gente falando, trânsito, porto, mata de dia e
	# de noite, e o mar (praia, oceano aberto, ondas nas pedras). Só a oficina segue a do V1.
	_make_bed("traffic",_recorded_bed("city_traffic",V1_AUDIO.bed("street",0)))
	_make_bed("city",_recorded_bed("crowd",V1_AUDIO.bed("street",0)))
	_make_bed("water",_recorded_bed("ocean_shore",V1_AUDIO.bed("water",1)))
	_make_bed("swell",_recorded_bed("ocean_open",null))
	_make_bed("rocks",_recorded_bed("wave_rocks",null))
	_make_bed("port",_recorded_bed("port_terminal",V1_AUDIO.bed("workshop",1)))
	_make_bed("dockside",_recorded_bed("harbor",null))
	_make_bed("birds",_recorded_bed("forest_day",V1_AUDIO.bed("birds",1)))
	_make_bed("crickets",_recorded_bed("forest_night",V1_AUDIO.bed("crickets",0)))
	_make_bed("workshop",V1_AUDIO.bed("workshop",0))
	_city_life_mix = CITY_LIFE.enabled()
	if _city_life_mix:
		# "Rua" é o leito original da V1 (29–37 s: repete menos que os de 5,7 s do ElevenLabs);
		# a brisa do litoral usa o vento regional, que em Harbor não tocava.
		_make_bed("street",V1_AUDIO.bed("street",rng.randi_range(0,1)))
		_make_bed("breeze",V1_AUDIO.regional("wind",1))
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
	if _city_life_mix:
		city_life = CITY_LIFE.new()
		city_life.name = "CityLifeAudio"
		city_life.world = world
		add_child(city_life)
	for index in 7:
		# A câmera ouvinte fica uns 36 m acima do carro ocupado. Na V1 o
		# motor do motorista era áudio de primeiro plano, então não pode sumir com essa distância.
		var layer := AudioStreamPlayer.new()
		layer.name = "PlayerEngineBand%d" % index
		layer.bus = _bus(&"Vehicles")
		layer.max_polyphony = 1
		add_child(layer)
		layers.append(layer)
	road_audio = AudioStreamPlayer.new()
	road_audio.name = "PlayerRoadNoise"
	road_audio.bus = _bus(&"Vehicles")
	var road_stream := ROAD_SOUND.duplicate() as AudioStreamWAV
	road_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	road_stream.loop_end = maxi(1, roundi(road_stream.get_length() * road_stream.mix_rate) - 8)
	road_audio.stream = road_stream
	add_child(road_audio)
	shift_audio = AudioStreamPlayer.new()
	shift_audio.name = "PlayerTurboRelease"
	shift_audio.bus = _bus(&"Vehicles")
	add_child(shift_audio)
	air_brake_audio = AudioStreamPlayer.new()
	air_brake_audio.name = "PlayerAirBrake"
	air_brake_audio.bus = _bus(&"Vehicles")
	add_child(air_brake_audio)
	_ensure_firefly_players()

## Camadas do Firefly. Criadas sob demanda porque há testes que montam o mixer só com
## road/shift/air_brake e não passam por `_ready`.
func _ensure_firefly_players() -> void:
	if extra_audio != null: return
	extra_audio = AudioStreamPlayer.new()
	extra_audio.name = "PlayerEngineExtras"
	extra_audio.bus = _bus(&"Vehicles")
	add_child(extra_audio)
	blower_audio = AudioStreamPlayer.new()
	blower_audio.name = "PlayerSupercharger"
	blower_audio.bus = _bus(&"Vehicles")
	blower_audio.stream = FIREFLY.loop("vehicle_fx", "supercharger_loop.wav")
	add_child(blower_audio)
	reverse_audio = AudioStreamPlayer.new()
	reverse_audio.name = "PlayerReverseBeep"
	reverse_audio.bus = _bus(&"Vehicles")
	reverse_audio.stream = FIREFLY.loop("service_vehicles", "reverse_beep_loop.wav")
	add_child(reverse_audio)

func _engine_fx_channels() -> Array:
	var channels: Array = [road_audio, shift_audio, air_brake_audio]
	for extra in [extra_audio, blower_audio, reverse_audio]:
		if extra != null: channels.append(extra)
	return channels

func _bus(preferred: StringName) -> StringName:
	return preferred if AudioServer.get_bus_index(preferred)>=0 else &"Master"
## Uma tomada sorteada por abertura do jogo; sem o arquivo importado, o leito do V1.
func _recorded_bed(key: String, fallback: AudioStream) -> AudioStream:
	var total := FIREFLY.count("ambience_el", key)
	if total == 0: return fallback
	var looped := FIREFLY.loop("ambience_el", "%s_%d.wav" % [key, rng.randi_range(0, total - 1)])
	return looped if looped != null else fallback
func _make_bed(id: String, stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.name = id.capitalize()+"Ambience"
	player.stream = stream
	player.bus = _bus(&"Ambient")
	player.volume_db = -80
	add_child(player)
	beds[id] = player
	if not bed_gains.has(id): bed_gains[id] = 0.0

func _bed_offset(id: String) -> float:
	if _city_life_mix and _bed_region in CITY_LIFE.REGIONS and CITY_LIFE.BED_OFFSETS.has(id):
		return float(CITY_LIFE.BED_OFFSETS[id])
	return float(BED_OFFSETS.get(id, -80.0))
## V1 `VehicleRadioReceiver`: dirigindo, roda do mouse e R/LB/RB sintonizam. A pé a roda é da
## troca de arma (`Gameplay`), que `can_attack` já barra dentro do carro.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or not _driver_audio_ready(): return
	var direction := 0
	if event.is_action_pressed("radio_toggle"):
		if get_tree().paused or not _radio_tunable(): return
		if radio_index >= 0:
			if is_instance_valid(radio_car): radio_car.set_meta("radio_last_station", radio_index)
			_set_station(-1)
		else: _set_station(clampi(int(radio_car.get_meta("radio_last_station",0)) if is_instance_valid(radio_car) else 0,0,STATIONS.size()-1))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		direction = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
	elif event.is_action_pressed("radio_next"):
		direction = 1
	elif event.is_action_pressed("radio_previous"):
		direction = -1
	if direction == 0 or get_tree().paused or not _radio_tunable(): return
	_cycle_radio(direction)
	get_viewport().set_input_as_handled()

func _driver_audio_ready() -> bool:
	# Ocupado reserva o carro no início do embarque; o controle começa no assento.
	return world.driving.occupied and is_instance_valid(world.driving.car) and world.driving.car.controlled

func set_scoped_music_override(owner: Node) -> bool:
	if not is_instance_valid(owner): return false
	var current: Object = _scoped_music_owner.get_ref() if _scoped_music_owner != null else null
	if is_instance_valid(current) and current != owner: return false
	_scoped_music_owner = weakref(owner)
	if is_instance_valid(radio): radio.stream_paused = true
	return true

func clear_scoped_music_override(owner: Node) -> void:
	var current: Object = _scoped_music_owner.get_ref() if _scoped_music_owner != null else null
	if is_instance_valid(current) and current != owner: return
	_scoped_music_owner = null
	if is_instance_valid(radio): radio.stream_paused = false

func _radio_tunable() -> bool:
	if not _driver_audio_ready(): return false
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
	_set_station(slot if slot < STATIONS.size() else -1)

func _set_station(index: int) -> void:
	radio_index = index if index >= -1 and index < STATIONS.size() else -1
	# Cada carro guarda a própria estação, como `radio_index` em PlayerCar/TrafficVehicle na V1.
	if is_instance_valid(radio_car):
		radio_car.set_meta(&"radio_index",radio_index)
		radio_car.set_meta(&"radio_position",0.0)
	_play_station(0.0)
	_show_station()

func _play_station(from: float) -> void:
	radio.stop()
	radio.stream = null
	if radio_index < 0 or radio_index >= STATIONS.size(): return
	var stream := load("res://audio/living_city/"+STATIONS[radio_index]+".ogg") as AudioStream
	if stream is AudioStreamOggVorbis: stream.loop = true
	radio.stream = stream
	if stream != null: radio.play(clampf(from,0.0,maxf(0.0,stream.get_length()-.5)))

## Na primeira entrada, sorteia uma estação ou desligado e guarda a escolha no veículo.
## Retoma do ponto onde parou e guarda a posição ao sair. Cada carro conserva sua sintonização.
func _update_radio(delta: float) -> void:
	var car: CharacterBody3D = world.driving.car if _driver_audio_ready() else null
	if car != radio_car:
		if is_instance_valid(radio_car) and radio.playing:
			radio_car.set_meta(&"radio_position",radio.get_playback_position())
		radio_car = car
		if car == null:
			radio.stop()
			radio_notice_time = 0.0
		else:
			if not car.has_meta(&"radio_index"):
				car.set_meta(&"radio_index",rng.randi_range(-1,STATIONS.size()-1))
			radio_index = int(car.get_meta(&"radio_index"))
			if radio_index < -1 or radio_index >= STATIONS.size(): radio_index = -1
			_play_station(float(car.get_meta(&"radio_position",0.0)))
	if car != null:
		# A prioridade vem do bus Dialogue: fala audível, incluindo barks e caronas.
		# Não abaixar duas vezes nem manter a rádio abafada por uma caixa de texto.
		radio.volume_db = RADIO_VOLUME_DB
	if _scoped_music_owner != null:
		if not is_instance_valid(_scoped_music_owner.get_ref()):
			_scoped_music_owner = null
			radio.stream_paused = false
		else: radio.stream_paused = true
	radio_notice_time = maxf(0.0,radio_notice_time-delta)
	if is_instance_valid(radio_notice):
		radio_notice.visible = car != null and radio_notice_time > 0.0 and not get_tree().paused and not (world.session != null and world.session.modal)
		radio_notice.modulate.a = clampf(minf(radio_notice_time/.18,(2.0-radio_notice_time)/.18),0,1)

func _show_station() -> void:
	if not is_instance_valid(radio_notice):
		radio_notice = Label.new()
		radio_notice.name = "StationNotice"
		radio_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		radio_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		radio_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ui_style = preload("res://ui/GameStyle.gd")
		radio_notice.add_theme_font_override("font",ui_style.FONT)
		radio_notice.add_theme_font_size_override("font_size",13)
		radio_notice.add_theme_color_override("font_color",ui_style.TEXT)
		radio_notice.add_theme_stylebox_override("normal",ui_style.compact(false,8))
		var hud: Node = world.get("hud") if is_instance_valid(world) else null
		if is_instance_valid(hud) and hud.has_method("attach_station_notice"):
			hud.attach_station_notice(radio_notice)
		else:
			var layer := CanvasLayer.new()
			layer.layer = 8
			add_child(layer)
			layer.add_child(radio_notice)
			radio_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			radio_notice.offset_left = -120
			radio_notice.offset_right = 120
			radio_notice.offset_top = 32
			radio_notice.offset_bottom = 70
	radio_notice.text = STATION_NAMES[radio_index] if radio_index >= 0 else "Rádio desligado"
	radio_notice_time = 2.0
	radio_notice.show()
	radio_notice.modulate.a=0

## Estalo de tiro ouvido de longe. O estampido do jogo (`Gameplay`) some a 37,5 m; daí até
## ~160 m tocava silêncio. Esta camada escuta o mesmo sinal `npc_gunfire` de NPC e polícia
## e só entra depois do alcance do estampido, então nunca soma com ele. No máximo um a cada
## 0,3 s: uma troca de tiros vira rajada distante, não metralhadora de eco.
const DISTANT_GUNFIRE_MIN := 37.5
const DISTANT_GUNFIRE_MAX := 160.0
var _gunfire_linked := false
var _distant_gunfire_msec := -10000

func _link_gunfire() -> void:
	if _gunfire_linked: return
	var gameplay = world.get("gameplay")
	if gameplay == null or not gameplay.has_signal("npc_gunfire"): return
	gameplay.npc_gunfire.connect(_on_npc_gunfire)
	_gunfire_linked = true

func _on_npc_gunfire(origin: Vector3, _direction: Vector3, _shooter: Node) -> void:
	if not is_instance_valid(world.player): return
	var offset: Vector3 = origin - world.player.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance < DISTANT_GUNFIRE_MIN or distance > DISTANT_GUNFIRE_MAX: return
	var now := Time.get_ticks_msec()
	if now - _distant_gunfire_msec < 300: return
	var shot := FIREFLY.stream("weapons_fire", "distant_shot", 0)
	if shot == null: return
	_distant_gunfire_msec = now
	FIREFLY.play_at(self, shot, origin, -7.0, rng.randf_range(0.92, 1.08), DISTANT_GUNFIRE_MAX + 40.0, 30.0)

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.world_audio.process", span, 3000)

func _process_traced(delta: float) -> void:
	_link_gunfire()
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
		# (6.5 m/s) virava uma metralhadora de ~8 passos/s. A passada cresce com a
		# velocidade (0.78 m lento até 2.5 m em sprint), mantendo a cadência em ~1.9–2.6/s.
		var speed := distance / maxf(delta, .0001)
		var stride := FOOTSTEP_CADENCE.stride(speed)
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
	# Carros de rua também têm mecânica desert_powertrain mas mantêm este mixer.
	# Cede só quando o veículo realmente tem um nó de áudio dedicado.
	if not _driver_audio_ready() or world.driving.car.health <= 0 or world.driving.car.engine_disabled or world.driving.car.has_node("DesertCarAudio"):
		if is_instance_valid(design_voice): design_voice.stop()
		engine_car = null
		engine_archetype = ""
		for layer in layers: if layer.playing: layer.stop()
		for channel in _engine_fx_channels(): if channel.playing: channel.stop()
		return
	var current_car: CharacterBody3D = world.driving.car
	_sync_engine_family(current_car)
	tank_start_remaining = maxf(0.0, tank_start_remaining - delta)
	var tops: Array = ENGINE_PROFILE.GEAR_TOPS.get(family, ENGINE_PROFILE.GEAR_TOPS.street)
	var nominal: Array = ENGINE_PROFILE.NOMINAL.get(family, ENGINE_PROFILE.NOMINAL.street)
	var ratio := clampf(absf(current_car.speed) / maxf(float(current_car.max_forward_speed), 1.0), 0.0, 1.0)
	var throttle := ENGINE_PROFILE.drive_load(float(current_car.speed), float(current_car.throttle_input), bool(current_car.brake_input))
	if family == "electric" and ratio < 0.02 and throttle < 0.01:
		for layer in layers: if layer.playing: layer.stop()
		if road_audio.playing: road_audio.stop()
		return
	engine_load = lerpf(engine_load, throttle, 1.0 - exp(-delta * 9.0))
	engine_shift_cooldown = maxf(0.0, engine_shift_cooldown - delta)
	engine_fx_cooldown = maxf(0.0, engine_fx_cooldown - delta)
	var previous_gear := engine_gear
	if ratio < 0.006 or float(current_car.speed) < -0.4:
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
	if family == "snowmobile":
		# Câmbio CVT: com o acelerador o motor sobe logo para a rotação de engate e vai subindo com
		# a velocidade, sem trocas de marcha.
		target = maxf(ENGINE_PROFILE.loaded_rpm(target, idle, engine_load, ratio), lerpf(idle, .62, engine_load))
	elif family != "tank" and family != "electric":
		target = ENGINE_PROFILE.loaded_rpm(target, idle, engine_load, ratio)
	elif ratio < 0.03:
		target = maxf(target, idle + engine_load * (1.0 - idle) * 0.62)
	engine_rpm = lerpf(engine_rpm, target, 1.0 - exp(-delta * (10.0 if target > engine_rpm else 6.0)))
	var spec: Dictionary = FLEET.spec(engine_archetype)
	if _mix_designed_engine(current_car, throttle, previous_gear, delta): return
	_update_vehicle_foley(current_car, spec, ratio, throttle, previous_gear)
	_update_engine_bank(delta)
	# Seleção de camada e pitch seguem as frequências do banco que toca (a ponte tem as suas).
	var bank_nominal: Array = ENGINE_PROFILE.NOMINAL.get(engine_bank_family, nominal)
	var tint := pow(maxf(float(spec.get("engine_pitch", 1.0)), 0.3), 0.35)
	var cycles := float(nominal[6]) * engine_rpm * tint
	var timbre := cycles / maxf(tint, 0.3) * (0.8 + 0.2 * engine_load)
	var lower := 0
	while lower < 5 and timbre > float(bank_nominal[lower + 1]): lower += 1
	var upper := lower + 1
	var blend := clampf(log(maxf(timbre, 0.5) / float(bank_nominal[lower])) / maxf(log(float(bank_nominal[upper]) / float(bank_nominal[lower])), 0.001), 0.0, 1.0)
	var master := -20.0 + engine_load * 7.0 + engine_rpm * 6.5 + ratio * 1.5
	if family == "vq35": master -= 5.0
	if family == "electric": master -= 13.0
	if family == "tank" and tank_start_remaining > 0.0:
		master += linear_to_db(maxf(0.005, smoothstep(0.6, 2.1, TANK_AUDIO.START_SECONDS - tank_start_remaining)))
	for index in 7:
		var share := cos(blend * PI * 0.5) if index == lower else (sin(blend * PI * 0.5) if index == upper else 0.0)
		share *= engine_swap_gain
		var layer := layers[index]
		if share <= 0.002 or layer.stream == null:
			if layer.playing: layer.stop()
			continue
		layer.pitch_scale = clampf(cycles / float(bank_nominal[index]), 0.35, 3.0)
		layer.volume_db = master + linear_to_db(share)
		if not layer.playing: layer.play()

func _ensure_design_voice() -> void:
	if is_instance_valid(design_voice): return
	design_voice = DESIGN_VOICE.new()
	design_voice.name = "PlayerEngineDesign"
	add_child(design_voice)

func _mix_designed_engine(car: CharacterBody3D, throttle: float, previous_gear: int, delta: float) -> bool:
	var profile := DESIGN_CATALOG.profile(engine_archetype)
	if not DESIGN_BANKS.enabled() or not DESIGN_BANKS.is_ready(profile):
		if is_instance_valid(design_voice): design_voice.stop()
		return false
	_ensure_design_voice()
	if not design_voice.configure(engine_archetype): return false
	for layer in layers: layer.stop()
	for channel in [road_audio, shift_audio, extra_audio, blower_audio]:
		if is_instance_valid(channel): channel.stop()
	var bands := DESIGN_CATALOG.rpm_bands(profile)
	var rpm := maxf(float(bands[0]), engine_rpm * float(bands[6]))
	var load_value := throttle
	var shifted := engine_gear != previous_gear
	var cut := 0.0
	var drive: RefCounted = car.get_meta("desert_powertrain") if car.has_meta("desert_powertrain") else null
	if drive != null:
		rpm = float(drive.rpm)
		# O pedal que chega ao câmbio (DesertHandling) é afinado nos últimos 8% da velocidade
		# máxima da rua: com o acelerador cheio a carga caía a ~0,09 no teto, o motor trocava
		# para a camada de desaceleração e o som sustentado ficava ~5 dB abaixo da arrancada
		# (playtest 29/10). O som segue o pedal do jogador; o câmbio mantém o afinamento.
		# GETECO_ENGINE_TAPERED_LOAD=1 devolve o comportamento anterior (A/B).
		load_value = float(drive.throttle) if OS.get_environment("GETECO_ENGINE_TAPERED_LOAD") == "1" else maxf(float(drive.throttle), throttle)
		shifted = int(drive.shift_serial) != design_last_shift
		design_last_shift = int(drive.shift_serial)
		cut = -8.0 if float(drive.shift_remaining) > 0.0 else 0.0
		if drive.limiter: cut -= 4.0
	if design_rpm <= 0.0: design_rpm = rpm
	design_rpm = lerpf(design_rpm, rpm, 1.0 - exp(-delta * (10.0 if rpm > design_rpm else 6.0)))
	design_cut = lerpf(design_cut, cut, 1.0 - exp(-delta * 18.0))
	# O PCM escrito tem uns 3 dB a mais de headroom que os bancos anteriores.
	# Mantém o envelope de carga/RPM do motorista e a presença de primeiro plano.
	var rpm_fraction := clampf(design_rpm / float(bands[6]), 0.0, 1.0)
	var road_fraction := clampf(absf(float(car.speed)) / maxf(float(car.max_forward_speed), 1.0), 0.0, 1.0)
	var level := -17.0 + load_value * 7.0 + rpm_fraction * 6.5 + road_fraction * 1.5 + design_cut
	if family == "vq35": level -= 5.0
	design_voice.update_mix(design_rpm, load_value, delta, level,
		car.global_position, true, true, shifted)
	_update_design_utility_foley(car, throttle)
	return true

func _update_design_utility_foley(car: CharacterBody3D, throttle: float) -> void:
	# Freios a ar e alertas de ré pertencem ao veículo, não à descarga do turbo.
	_ensure_firefly_players()
	if family in REVERSE_BEEP_FAMILIES:
		if absf(float(car.speed)) > 1.25: engine_was_moving_fast = true
		elif engine_was_moving_fast and absf(float(car.speed)) < .375 and throttle < .1:
			engine_was_moving_fast = false
			air_brake_audio.stream = AIR_BRAKE_SOUND
			air_brake_audio.volume_db = -6.0
			air_brake_audio.play()
	if family in REVERSE_BEEP_FAMILIES and float(car.speed) < -.4 and reverse_audio.stream != null:
		reverse_audio.volume_db = -15.0
		if not reverse_audio.playing: reverse_audio.play()
	else: reverse_audio.stop()
	engine_last_throttle = throttle

func _sync_engine_family(car: CharacterBody3D) -> void:
	var archetype := str(car.archetype)
	if engine_car == car and engine_archetype == archetype: return
	engine_car = car
	design_rpm = 0.0
	design_cut = 0.0
	design_last_shift = 0
	if is_instance_valid(design_voice): design_voice.stop()
	engine_archetype = archetype
	engine_gear = 1
	engine_rpm = 0.0
	engine_load = 0.0
	engine_shift_cooldown = 0.0
	engine_turbo_pressure = 0.0
	engine_last_throttle = 0.0
	engine_fx_cooldown = 0.0
	engine_was_moving_fast = false
	for channel in _engine_fx_channels(): if channel.playing: channel.stop()
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
	elif next_family == "snowmobile":
		road_audio.stream = SNOWMOBILE_AUDIO.track_stream()
	elif family in ["tank", "snowmobile"]:
		var road_stream := ROAD_SOUND.duplicate() as AudioStreamWAV
		road_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		road_stream.loop_end = maxi(1, roundi(road_stream.get_length() * road_stream.mix_rate) - 8)
		road_audio.stream = road_stream
	if next_family == family: return
	family = next_family
	# O áudio próximo já aquece e retém estes loops imutáveis de sete faixas.
	# As duplicatas não têm caminho de recurso: carregar os originais aqui de novo
	# erra o cache fraco do ResourceLoader depois que o aquecimento os solta.
	# Não espera a leitura: sem o banco pronto toca a ponte e `_update_engine_bank` troca depois.
	_bind_engine_layers(ENGINE_BANKS.bridge_family(family))
	engine_swap_gain = 1.0

func _bind_engine_layers(bank_family: String) -> void:
	var bank: Array[AudioStreamWAV] = []
	if not bank_family.is_empty(): bank = ENGINE_BANKS.bank(bank_family)
	engine_bank_family = bank_family if bank.size() == 7 else ""
	for index in 7:
		layers[index].stop()
		layers[index].stream = bank[index] if bank.size() == 7 else null

## Troca a ponte pela família certa quando ela termina de carregar: desce ao silêncio, troca
## os fluxos e sobe. Trocar o stream com a camada tocando corta a onda e estala.
func _update_engine_bank(delta: float) -> void:
	if engine_bank_family == family:
		engine_swap_gain = move_toward(engine_swap_gain, 1.0, delta / ENGINE_BANK_SWAP_SECONDS)
		return
	if ENGINE_BANKS.is_ready(family):
		if engine_bank_family.is_empty():
			_bind_engine_layers(family)
			return
		engine_swap_gain = move_toward(engine_swap_gain, 0.0, delta / ENGINE_BANK_SWAP_SECONDS)
		if engine_swap_gain <= 0.001:
			_bind_engine_layers(family)
	elif engine_bank_family.is_empty():
		var bridge := ENGINE_BANKS.bridge_family(family)
		if not bridge.is_empty(): _bind_engine_layers(bridge)

func _update_vehicle_foley(car: CharacterBody3D, spec: Dictionary, _ratio: float, throttle: float, previous_gear: int) -> void:
	if family == "snowmobile":
		# Esteira de borracha por cima do rolamento por superfície (neve, terra) do VehicleRoadAudio.
		var track_gain := SNOWMOBILE_AUDIO.track_gain(float(car.speed))
		if track_gain <= 0.001:
			road_audio.stop()
		else:
			road_audio.pitch_scale = SNOWMOBILE_AUDIO.track_pitch(float(car.speed))
			road_audio.volume_db = -19.0 + linear_to_db(track_gain)
			if not road_audio.playing: road_audio.play()
		engine_last_throttle = throttle
		return
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
	# TireEffects owns surface-aware rolling audio, including coasting with engine off.
	if road_audio.playing: road_audio.stop()
	var heavy_turbo := family in ["bus", "fire_diesel"]
	var sport_turbo := bool(spec.get("turbo_audio", false))
	if sport_turbo:
		var pressure_target := throttle * smoothstep(0.24, 0.82, engine_rpm)
		engine_turbo_pressure = lerpf(engine_turbo_pressure, pressure_target,
			1.0 - exp(-get_process_delta_time() * (3.6 if pressure_target > engine_turbo_pressure else 7.0)))
	else:
		engine_turbo_pressure = 0.0
	# Antes dos blocos abaixo: eles zeram a pressão ao aliviar o turbo e a camada nova precisa dela.
	_update_firefly_foley(car, throttle, sport_turbo)
	if engine_gear > previous_gear and heavy_turbo and (engine_load > 0.20 or engine_rpm > 0.30):
		_play_vehicle_fx(_turbo_shift_sounds(), clampf(-7.0 + engine_load * 6.0 + engine_rpm * 3.0, -14.0, 2.0) - (8.0 if family == "truck" else 0.0))
	elif engine_gear > previous_gear and sport_turbo and engine_turbo_pressure > 0.40:
		_play_vehicle_fx(_blowoff_sounds(), clampf(-21.0 + engine_turbo_pressure * 10.0 + engine_rpm * 2.0, -23.0, -11.0), 1.2)
	if heavy_turbo and engine_fx_cooldown <= 0.0 and engine_last_throttle > 0.65 and throttle < 0.15 and engine_rpm > 0.42:
		_play_vehicle_fx(_turbo_shift_sounds(), -2.0)
	# Mantém o alívio de pressão do cupê baixo e espaçado em frenagens repetidas.
	if sport_turbo and engine_fx_cooldown <= 0.0 and engine_last_throttle > 0.58 and throttle < 0.16 and engine_turbo_pressure > 0.40:
		_play_vehicle_fx(_blowoff_sounds(), clampf(-21.0 + engine_turbo_pressure * 10.0 + engine_rpm * 2.0, -23.0, -11.0), 1.2)
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

## Sons do Firefly casados com o motor do jogador: assobio do turbo subindo/descendo,
## trepidação do compressor, estouro de escapamento, compressor do muscle e bipe de ré.
## Tudo pega do estado que o motor já calcula (rpm, carga, pressão) — nada novo na física.
func _update_firefly_foley(car: CharacterBody3D, throttle: float, sport_turbo: bool) -> void:
	_ensure_firefly_players()
	extra_cooldown = maxf(0.0, extra_cooldown - get_process_delta_time())
	var lifted := engine_last_throttle > 0.6 and throttle < 0.15 and engine_rpm > 0.45
	if extra_cooldown <= 0.0:
		if sport_turbo and lifted and engine_turbo_pressure > 0.7 and rng.randf() < 0.35:
			_play_extra(FIREFLY.take("vehicle_fx", "turbo_flutter", rng), -19.0 + engine_turbo_pressure * 4.0, 1.5)
		elif sport_turbo and lifted and engine_turbo_pressure > 0.45:
			_play_extra(FIREFLY.take("vehicle_fx", "turbo_spooldown", rng), -20.0 + engine_turbo_pressure * 6.0, 2.0)
		elif family in BACKFIRE_FAMILIES and lifted and rng.randf() < 0.5:
			_play_extra(FIREFLY.take("vehicle_fx", "backfire", rng), -15.0 + engine_rpm * 4.0, 2.5)
		elif sport_turbo and throttle > 0.85 and engine_last_throttle < 0.5 and engine_rpm > 0.3:
			_play_extra(FIREFLY.take("vehicle_fx", "turbo_spool", rng), -24.0, 3.5)
	# Compressor do muscle: ronco que sobe com o giro e some quando o pé sai.
	if family == "muscle" and blower_audio.stream != null:
		var want := clampf(0.2 + engine_rpm * 0.8, 0.0, 1.0) * (0.3 + 0.7 * throttle)
		blower_audio.pitch_scale = 0.6 + engine_rpm * 1.0
		blower_audio.volume_db = -21.0 + linear_to_db(maxf(want, 0.0001))
		if want > 0.08 and not blower_audio.playing: blower_audio.play()
		elif want < 0.04 and blower_audio.playing: blower_audio.stop()
	elif blower_audio.playing:
		blower_audio.stop()
	# Bipe de ré dos pesados e da empilhadeira do porto, só enquanto o veículo anda para trás.
	if (family in REVERSE_BEEP_FAMILIES or str(car.get("archetype")) == "port_forklift") and float(car.speed) < -0.4 and reverse_audio.stream != null:
		reverse_audio.volume_db = -15.0
		if not reverse_audio.playing: reverse_audio.play()
	elif reverse_audio.playing:
		reverse_audio.stop()

func _play_extra(audio: AudioStream, volume: float, cooldown: float) -> void:
	if audio == null: return
	extra_audio.stream = audio
	extra_audio.volume_db = volume
	extra_audio.pitch_scale = rng.randf_range(0.97, 1.03)
	extra_audio.play()
	extra_cooldown = cooldown

## Listas cíclicas de `_play_vehicle_fx`: o que o jogo já tinha somado às tomadas novas, no
## mesmo nível (as novas foram normalizadas para casar com as antigas).
func _blowoff_sounds() -> Array:
	if _blowoff_mix.is_empty():
		# Só as gravadas; as sintéticas antigas ficam se o arquivo novo não estiver importado.
		_blowoff_mix = FIREFLY.all("vehicle_fx", "wastegate")
		if _blowoff_mix.is_empty(): _blowoff_mix = SPORT_BLOWOFF_SOUNDS.duplicate()
	return _blowoff_mix

func _turbo_shift_sounds() -> Array:
	if _turbo_shift_mix.is_empty():
		_turbo_shift_mix = FIREFLY.all("vehicle_fx", "diesel_turbo")
		if _turbo_shift_mix.is_empty(): _turbo_shift_mix = TURBO_SHIFT_SOUNDS.duplicate()
	return _turbo_shift_mix

func _play_vehicle_fx(sounds: Array, volume: float, cooldown: float = 0.18) -> void:
	if engine_fx_cooldown > 0.0: return
	engine_fx_variant = (engine_fx_variant + 1) % sounds.size()
	shift_audio.stream = sounds[engine_fx_variant]
	shift_audio.volume_db = volume
	shift_audio.pitch_scale = 0.96 + engine_rpm * 0.12
	shift_audio.play()
	engine_fx_cooldown = cooldown

func _update_ambience(delta: float) -> void:
	if world.session == null: return
	ambience_clock += delta
	# Fala real recebe prioridade no bus; janelas modais mantêm a redução leve.
	var focus := .62 if world.session.modal else 1.0
	if ambience_clock >= .25:
		ambience_clock = 0
		var state = world.session.state
		bed_targets = PROFILES.targets(str(state.region_id),str(state.place_id),world.player.global_position,_dark(),_nearby_crowd_gain())
		bed_targets["traffic"] = float(bed_targets.get("city",0.0))*.8
		bed_targets["dockside"] = float(bed_targets.get("port",0.0))*.7
		bed_targets["swell"] = float(bed_targets.get("water",0.0))*.7
		bed_targets["rocks"] = float(bed_targets.get("port",0.0))*.5+float(bed_targets.get("water",0.0))*.25
		_bed_region = str(state.region_id)
		if _city_life_mix:
			var traffic_presence := 0.5
			if is_instance_valid(vehicle_ambience): traffic_presence = clampf(float(vehicle_ambience.nearby_traffic)/6.0,0.0,1.0)
			CITY_LIFE.shape_beds(bed_targets,_bed_region,str(state.place_id),world.player.global_position,_dark(),traffic_presence)
		detail_context = PROFILES.activity_context(str(state.region_id),str(state.place_id),world.player.global_position)
	for id in beds:
		var target := float(bed_targets.get(id,0.0))*focus
		bed_gains[id] = lerpf(float(bed_gains[id]),target,1.0-exp(-delta/.7))
		var offset: float = _bed_offset(id)
		var player: AudioStreamPlayer = beds[id]
		player.volume_db = offset+linear_to_db(maxf(float(bed_gains[id]),.0001))
		if bed_gains[id]>.005 and player.stream != null and not player.playing: player.play(rng.randf_range(0,maxf(0,player.stream.get_length()-1)))
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
		"port","dock":
			var roll := rng.randf()
			kind = "ship_horn" if roll<.25 else ("clang" if roll<.55 else ("buoy" if roll<.7 else ("gull" if not _dark() else "ship_horn")))
		"nature": kind = "dog" if _dark() else "birds"
		"city":
			kind = "dog" if _dark() else ""
			# Cidade viva: de dia a rua também tem buzina ao longe e gaivota de cidade portuária.
			if _city_life_mix and not _dark():
				var city_roll := rng.randf()
				kind = "car_horn" if city_roll<.35 else ("gull" if city_roll<.55 else "")
	if kind.is_empty():
		detail_clock = rng.randf_range(12,24)
		return
	var recorded_key: String = {"ship_horn":"ship_horn","clang":"container_clang","buoy":"buoy_bell"}.get(kind,"")
	if not recorded_key.is_empty() and FIREFLY.count("ambience_el",recorded_key)>0: detail.stream = FIREFLY.take("ambience_el",recorded_key,rng)
	elif kind=="clang" or kind=="buoy": detail.stream = null
	elif kind=="scrap": detail.stream = V1_AUDIO.regional("scrap",detail_variant)
	elif kind=="car_horn": detail.stream = FIREFLY.take("vehicle_fx","car_horn",rng)
	else: detail.stream = V1_AUDIO.detail(kind,detail_variant)
	detail_variant = (detail_variant+1)%6
	if detail.stream == null:
		detail_clock = 20
		return
	var angle := rng.randf_range(-PI,PI)
	var distance := rng.randf_range(16,30) if kind=="car_horn" else rng.randf_range(5,14)
	detail.global_position = source+Vector3(cos(angle)*distance,1.2,sin(angle)*distance)
	detail.max_distance = 90 if kind=="ship_horn" else (60 if kind=="car_horn" else 48)
	detail.volume_db = -6 if kind=="ship_horn" else (-14 if kind=="workshop" else -10)
	if _city_life_mix:
		# No exterior de Harbor o detalhe é ouvido do jogador, não da câmera (~36 m acima): antes a
		# câmera cortava boa parte deles pelo max_distance e o resto chegava ~24 dB abaixo do
		# nominal. Interiores e outras regiões seguem com a atenuação nativa de sempre.
		var relative: bool = str(world.session.state.place_id).is_empty() and str(world.session.state.region_id) in CITY_LIFE.REGIONS
		CITY_LIFE.configure_detail(detail,relative)
		if relative:
			detail.volume_db = CITY_LIFE.detail_volume_db(kind,detail.volume_db)+CITY_LIFE.hearing_db(distance,6.0,detail.max_distance)
			detail.max_distance = 0.0
	detail.pitch_scale = rng.randf_range(.94,1.04)
	detail.play()
	detail_clock = rng.randf_range(18,34) if kind in ["gull","ship_horn","car_horn"] else rng.randf_range(8,18)

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
