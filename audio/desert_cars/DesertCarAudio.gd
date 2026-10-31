extends Node3D
## Mixer escrito de carga/desaceleração, usando o MESMO câmbio do movimento e do HUD.
## Os bancos antigos continuam disponíveis enquanto os compartilhados aquecem e para diagnóstico A/B.
const BANKS := preload("res://audio/EngineBankCache.gd")
const DESIGN_BANKS := preload("res://audio/EngineDesignBanks.gd")
const DESIGN_VOICE := preload("res://audio/EngineDesignVoice.gd")
const DESIGN_CATALOG := preload("res://audio/FleetEngineDesign.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const SHIFT_BLOWOFF := preload("res://audio/vehicle_fx/sport_blowoff_1.wav")
var drivetrain: RefCounted
var vehicle: Node3D
var _bank: Array[AudioStreamWAV] = []
var _layers: Array[AudioStreamPlayer3D] = []
var _indices := [-1,-1]
var _shift: AudioStreamPlayer3D
var _tire: AudioStreamPlayer3D
# Pneu patinando na arrancada (burnout/largada). Era -28 dB com teto -24, ~20 dB abaixo do motor
# (-16..-5): inaudível, e por ser esta a voz do burnout o chiado de VehicleTireEffects fica calado
# enquanto ela toca (has_wheelspin_voice). Playtest 30/10 ("derrapagem não dá para ouvir"): sobe
# para -14 com teto -10, presente mas ainda abaixo do motor a fundo, que é o que o drag precisa ouvir.
const WHEELSPIN_DB := -14.0
const WHEELSPIN_MAX_DB := -10.0
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
var _audible_rpm := 0.0
var _audible_load := 0.0
var _audible_cut := 0.0
var _design_voice: Node3D
var race_role := ""
var _spatial_dirty := true

func set_race_role(role: String) -> void:
	var next := role if role in ["player","rival"] else ""
	if race_role==next: return
	race_role=next
	_spatial_dirty=true
	_apply_design_role()

func _race_gain() -> float:
	return -4.0 if race_role=="rival" else 0.0

func _apply_spatial_role() -> void:
	for player in _layers+[_shift,_tire,_recorded_idle]:
		if not is_instance_valid(player): continue
		player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED if _foreground else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.max_distance=0.0 if _foreground else 85.0
		player.panning_strength=0.0 if _foreground else 1.0
		player.attenuation_filter_db=0.0 if _foreground else -24.0
		player.unit_size=4.0 if player==_tire else (3.0 if race_role=="rival" else 12.0)
		player.max_db=WHEELSPIN_MAX_DB if player==_tire else (-18.0 if race_role=="rival" else 1.0)
	_spatial_dirty=false

func _apply_design_role() -> void:
	if not is_instance_valid(_design_voice): return
	# Cuida só destas vozes por carro; sem mudar bus global nem banco de motor compartilhado.
	# Com 4 m de separação entre faixas, uma escala de fonte de 12 m amplificava o adversário.
	_design_voice.spatial_unit_size=3.0 if race_role=="rival" else 12.0
	for player in _design_voice.get_children():
		if not player is AudioStreamPlayer3D: continue
		player.unit_size=_design_voice.spatial_unit_size
		player.max_db=-18.0 if race_role=="rival" else 3.0

func bind(car: Node3D, state: RefCounted) -> void:
	vehicle = car
	drivetrain = state
	_audible_rpm = float(state.rpm) if state != null else 0.0
	_audible_load = 0.0
	_audible_cut = 0.0
	_last_shift = int(state.shift_serial) if state != null else 0
	_last_throttle = float(state.throttle) if state != null else 0.0
	_blowoff_cooldown = .2
	_external_observing = false
	_spatial_dirty = true
	if is_node_ready() and state != null: _apply_profile()

func _ready() -> void:
	if not is_instance_valid(vehicle) or drivetrain == null: set_process(false); return
	DESIGN_BANKS.prewarm.call_deferred(get_tree())
	name = "DesertCarAudio"
	for i in 2: _layers.append(_player("EngineBand%d" % i,-80.0))
	_apply_profile()
	_shift = _player("ShiftBlowoff",-16.0)
	_shift.stream = SHIFT_BLOWOFF
	_tire = _player("Wheelspin",-80.0)
	# O ouvinte próximo da corrida do motorista não pode pôr o pneu acima do motor.
	_tire.max_db = WHEELSPIN_MAX_DB
	_tire.unit_size = 4.0
	# Mesmo guincho novo de VehicleTireEffects (tools/generate_tire_skid_loops.py); os skid_*.wav
	# antigos eram 1 s de seno puro com ruído branco e se repetiam a cada segundo.
	_tire.stream = _loop("res://audio/vehicle_fx/tire_squeal_muscle.wav" if str(drivetrain.spec.engine_family)=="muscle" else "res://audio/vehicle_fx/tire_squeal_street.wav")

func _apply_profile() -> void:
	var family := str(drivetrain.spec.engine_family)
	if family != _family:
		_family = family
		_bank = BANKS.bank(family)
		_indices = [-1,-1]
	var bus: StringName = &"Vehicles" if AudioServer.get_bus_index("Vehicles")>=0 else &"Master"
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
	# Reaplica os ajustes de primeiro plano quando o tuning religa um veículo ocupado.
	_foreground = false

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or drivetrain == null: queue_free(); return
	# Bate com o motor de primeiro plano do WorldAudio para o Dante. Uma câmera elevada ou
	# cinematográfica não pode atenuar/calar o próprio motor dele; NPCs mantêm a queda espacial.
	var foreground := race_role=="player" or (race_role!="rival" and bool(vehicle.get("controlled")) and not bool(vehicle.get("traffic")) and not bool(vehicle.get("external_input")))
	if foreground != _foreground or _spatial_dirty:
		_foreground = foreground
		_apply_spatial_role()
		_range_clock = 0.0
	_range_clock -= delta
	_blowoff_cooldown = maxf(0.0,_blowoff_cooldown-delta)
	if _range_clock <= 0.0:
		_range_clock = .2
		var camera := get_viewport().get_camera_3d()
		# O arrancadão tem um ouvinte no carro do Dante; a câmera lateral larga pode estar a centenas
		# de metros. Mantém só estes dois mixers de corrida ativos e deixa a atenuação
		# espacial usar esse ouvinte em vez de calar pela distância da câmera.
		_in_range = vehicle.has_meta("desert_drag_physics") or (camera != null and camera.global_position.distance_squared_to(vehicle.global_position) < 85.0*85.0)
	var running := bool(vehicle.get("controlled")) or bool(vehicle.get("traffic")) or bool(vehicle.get("external_input")) or absf(float(vehicle.get("speed"))) > .15
	# Race controller owns physics while staging; revving there is still audible.
	running = running or (not vehicle.is_physics_processing() and float(drivetrain.rpm) > 1000.0)
	var active := (_foreground or _in_range) and running and vehicle.is_visible_in_tree() and float(vehicle.get("health")) > 0.0 and not bool(vehicle.get("engine_disabled"))
	if not active:
		if is_instance_valid(_design_voice): _design_voice.stop()
		for player in _layers: player.stop()
		_tire.stop()
		_shift.stop()
		if is_instance_valid(_recorded_idle): _recorded_idle.stop()
		_external_observing = false
		_audible_rpm = float(drivetrain.rpm)
		_audible_load = 0.0
		_audible_cut = 0.0
		return
	_synchronize_external(delta)
	# A inércia da embreagem de corrida já está no RPM oficial. Adaptadores de rua/ré
	# mantêm a suavização audível sem mudar a dirigibilidade na rua.
	var target_rpm := float(drivetrain.rpm)
	var response := 10.0 if target_rpm > _audible_rpm else 6.0
	var continuous_shift := bool(drivetrain.race_mode)
	var clutch := float(drivetrain.shift_torque_factor) if continuous_shift else (0.0 if float(drivetrain.shift_remaining)>0.0 else 1.0)
	_audible_rpm = target_rpm if continuous_shift else lerpf(_audible_rpm,target_rpm,1.0-exp(-maxf(delta,0.0)*response))
	var pedal := float(drivetrain.throttle)
	if not continuous_shift:
		# Na rua o DesertHandling afina o pedal nos últimos 8% do teto de velocidade, e a carga do
		# som caía a ~0 com o acelerador cheio (motor trocava para a camada de desaceleração, ~5 dB
		# mais baixa que a arrancada). O som segue o pedal real do jogador; a corrida segue o câmbio.
		var raw: Variant = vehicle.get("throttle_input")
		if raw != null and not bool(vehicle.get("brake_input")) and float(raw) > 0.0:
			pedal = maxf(pedal, clampf(float(raw), 0.0, 1.0))
	var target_load := pedal*(lerpf(.18,1.0,clutch) if continuous_shift else 1.0)
	_audible_load = lerpf(_audible_load,target_load,1.0-exp(-maxf(delta,0.0)*(20.0 if continuous_shift else 7.0)))
	# Cada valor nominal é ciclos completos de quatro tempos por segundo: RPM / 120.
	# Alinha as duas faixas a essa MESMA taxa; senão o crossfade toca duas
	# notas incompatíveis e gera batimento/chiados quando o motor acelera.
	var nominal: Array = PROFILE.NOMINAL.get(_family, PROFILE.NOMINAL.street)
	var cycles := maxf(1.0,_audible_rpm/120.0)
	var low := 0
	while low < 5 and cycles > float(nominal[low+1]): low += 1
	var fraction := clampf(log(cycles/float(nominal[low]))/log(float(nominal[low+1])/float(nominal[low])),0.0,1.0)
	var power := _audible_load
	var cut := -8.0*(1.0-clutch)
	if drivetrain.limiter: cut -= 4.0
	_audible_cut = lerpf(_audible_cut,cut,1.0-exp(-maxf(delta,0.0)*18.0))
	var exhaust := float(drivetrain.spec.get("exhaust",0.0))
	# A injeção aumenta a carga do motor. Não é uma purga externa de freio a ar.
	var nitro_load := 1.5 if drivetrain.nitro_active else 0.0
	var role_gain := _race_gain()
	# O pneu do jogador em drift forte pede espaço: o motor cede até 2,5 dB (meta de
	# VehicleTireEffects, 0..1, já com envelope). A patinada (_tire) não entra no ducking.
	var tire_duck := -2.5*clampf(float(vehicle.get_meta("tire_skid_duck",0.0)),0.0,1.0) if _foreground else 0.0
	var tire_gain := role_gain
	role_gain += tire_duck
	if _mix_designed_engine(delta,-16.0+power*4.0+_audible_cut+exhaust*2.0+nitro_load+role_gain):
		for player in _layers: player.stop()
		if is_instance_valid(_recorded_idle): _recorded_idle.stop()
		_shift.stop()
		_last_shift = int(drivetrain.shift_serial)
		_last_throttle = float(drivetrain.throttle)
		_loop_level(_tire,float(drivetrain.wheelspin),WHEELSPIN_DB+tire_gain,delta)
		return
	# Gravações reais de marcha lenta dão o caráter em baixa para estas duas famílias.
	# Não estica uma gravação de lenta pela faixa de giro inteira: some com ela
	# antes de 2000 RPM, deixando os bancos de carga alinhados ao RPM no comando.
	var idle_weight := 0.0
	if is_instance_valid(_recorded_idle):
		idle_weight = (1.0-smoothstep(1050.0,2000.0,_audible_rpm))*(1.0-power*.4)
		_recorded_idle.pitch_scale = clampf(_audible_rpm/(750.0 if _family == "diesel" else 900.0),.85,1.6)
		_loop_level(_recorded_idle,idle_weight,-14.0+role_gain,delta)
	# O banco pode ainda estar em leitura (EngineBankCache não espera): tenta de novo até ficar
	# pronto. A camada nova entra em -80 dB e sobe pelo lerp abaixo, sem estalo.
	if _bank.size() != 7 and not _family.is_empty(): _bank = BANKS.bank(_family)
	var synthesized_gain := linear_to_db(1.0-idle_weight*.82)
	for i in 2:
		var index := low+i
		# Faixas vizinhas alternam players. Mantém a faixa compartilhada tocando em
		# cada fronteira em vez de reiniciar as duas amostras em volume audível.
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
		player.volume_db = lerpf(player.volume_db,-19.0+linear_to_db(weight)+power*4.0+_audible_cut+exhaust*2.0+nitro_load+synthesized_gain+role_gain,1.0-exp(-delta*25.0))
		player.pitch_scale = clampf(cycles/float(nominal[index]),.35,3.0)
	if int(drivetrain.shift_serial) != _last_shift:
		_last_shift = int(drivetrain.shift_serial)
		_play_shift()
	elif _last_throttle > .65 and float(drivetrain.throttle) < .25 and float(drivetrain.turbo_pressure) > .5:
		_play_shift()
	_last_throttle = float(drivetrain.throttle)
	_loop_level(_tire,float(drivetrain.wheelspin),WHEELSPIN_DB+tire_gain,delta)

func _mix_designed_engine(delta: float, level: float) -> bool:
	var archetype := str(vehicle.get("archetype"))
	var profile := DESIGN_CATALOG.profile(archetype)
	if not DESIGN_BANKS.enabled() or not DESIGN_BANKS.is_ready(profile):
		if is_instance_valid(_design_voice): _design_voice.stop()
		return false
	var created := not is_instance_valid(_design_voice)
	if created:
		_design_voice = DESIGN_VOICE.new()
		_design_voice.name = "EngineDesign"
		_design_voice.spatial_range = 85.0
		_design_voice.spatial_unit_size = 12.0
		add_child(_design_voice)
	if not _design_voice.configure(archetype): return false
	if created: _apply_design_role()
	_design_voice.update_mix(_audible_rpm, _audible_load, delta, level, vehicle.global_position,
		_foreground, true, int(drivetrain.shift_serial) != _last_shift)
	return true

func has_wheelspin_voice() -> bool:
	# Só reivindica o som longitudinal do pneu enquanto ele está de fato sendo mixado.
	# Frenagem/curva continuam com o VehicleTireEffects.
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
		# Seguir rota define a velocidade direto e não preenche throttle_input.
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
	# Motores aspirados não têm admissão pressurizada para aliviar. Um diesel de série também
	# não fecha borboleta de gasolina nas trocas. A queda de RPM/carga
	# já vem da transmissão oficial.
	if float(drivetrain.spec.boost_gain) <= .01 or _family == "diesel" or float(drivetrain.turbo_pressure) < .25: return
	_blowoff_cooldown = .22
	_shift.volume_db = -23.0+_race_gain()
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
	if AudioServer.get_bus_index("Vehicles") >= 0: p.bus = "Vehicles"
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
