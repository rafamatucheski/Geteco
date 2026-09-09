extends CharacterBody2D

const VEHICLE_DOOR_VISUAL := preload("res://VehicleDoorVisual.gd")

@export var max_speed = 600.0
@export var acceleration = 1200.0
@export var braking = 1500.0
@export var friction = 600.0
@export var turn_speed = 3.5
@export var drift_factor = 0.9

# Variável que diz se o jogador está dirigindo ESTE carro
@export var is_driven_by_player = false

var skid_line: Line2D
var is_skidding: bool = false
var lateral_speed: float = 0.0 # px/s de derrapada — lido por DriftChallengeZone
var target_length: float = 74.0
var uniform_scale: float = 1.0
var headlight: PointLight2D
var bloody_tires_timer: float = 0.0

var health: int = 100
var is_broken: bool = false
var smoke_emitter: CPUParticles2D
var flame_particles: CPUParticles2D
var sprite: Sprite2D

# Juice / Game Feel
var _hit_stop_frames: int = 0
var _entry_input_released := true
var _drive_input_armed := true
var collision_particles: CPUParticles2D

# Upgrades & Tuning (Fast & Furious Style)
var has_nitro: bool = false
var nitro_amount: float = 0.0
var nitro_max: float = 0.0
var is_boosting: bool = false
var nitro_emitter: CPUParticles2D
var nitro_audio: AudioStreamPlayer2D

# Chuva, freio de mão (derrapagem) e respingo de poça
var water_spray_emitter: CPUParticles2D
var _weather_manager_cache: Node = null

# Efeitos de Escapamento e Purga de Nitro
var nos_purge_l: CPUParticles2D
var nos_purge_r: CPUParticles2D
var backfire_emitter: CPUParticles2D
var _prev_throttle: float = 0.0

# Pneus e Blindagem Anti-Furo (Kevlar)
var has_puncture_proof_tires: bool = false
var has_punctured_tires: bool = false
var rim_sparks: CPUParticles2D
var flat_smoke: CPUParticles2D

var has_neon: bool = false
var neon_color: Color = Color("#00cec9")
var neon_underglow_poly: Polygon2D

# Áudio
var _engine_sound := preload("res://audio/VehicleEngineSound.gd").new()
var engine_audio: AudioStreamPlayer2D
var skid_audio: AudioStreamPlayer2D
var radio_audio: AudioStreamPlayer2D
var horn_audio: AudioStreamPlayer2D
var radio_tracks: Array = []
var radio_index: int = 0

@onready var camera = $Camera
@onready var interact_area = $InteractArea

func _ready():
	preload("res://VehicleMotionSafety.gd").configure(self)
	collision_mask |= 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	add_to_group("vehicle")
	
	# Prepara a linha de derrapagem (Skidmarks)
	skid_line = Line2D.new()
	skid_line.width = 4.0
	skid_line.default_color = Color(0.1, 0.1, 0.1, 0.5)
	skid_line.top_level = true # Para não herdar a rotação do carro
	add_child(skid_line)
	
	# Esconde os quadrados e sprites antigos (como o car.png vermelho provisório)
	for child in get_children():
		if child is ColorRect or (child is Sprite2D and child != sprite):
			child.hide()
			
	# Cria o sprite bonito usando o Atlas do Codex (Carro Esportivo Muscle do Dante)
	sprite = Sprite2D.new()
	var tex = AtlasTexture.new()
	tex.atlas = load("res://assets/art/vehicle-atlas.png")
	tex.region = Rect2(58, 48, 234, 475) # Esportivo Cupê Vermelho/Vinho
	sprite.texture = tex
	
	# Métrica do Codex
	target_length = 74.0
	uniform_scale = target_length / max(1.0, tex.region.size.y)
	sprite.scale = Vector2(uniform_scale, uniform_scale)
	sprite.rotation = PI/2 # Vira pra direita
	sprite.modulate = Color(0.9, 0.25, 0.25) # Vermelho esportivo do Dante
	add_child(sprite)
	
	# Ajusta a colisão dinamicamente para o mesmo tamanho
	var new_shape = RectangleShape2D.new()
	new_shape.size = Vector2(target_length * 0.78, max(24.0, tex.region.size.x * uniform_scale * 0.72))
	var collision_node = get_node_or_null("Collision")
	if collision_node: collision_node.shape = new_shape
	
	# Bumper Hitbox para atropelamento responsivo
	var bumper := Area2D.new()
	bumper.name = "BumperHitbox"
	bumper.collision_layer = 0
	bumper.collision_mask = 5
	var b_shape := CollisionShape2D.new()
	var b_rect := RectangleShape2D.new()
	b_rect.size = Vector2(target_length * 0.95, maxf(28.0, tex.region.size.x * uniform_scale * 0.85))
	b_shape.shape = b_rect
	bumper.add_child(b_shape)
	bumper.body_entered.connect(_on_bumper_hitbox_entered)
	add_child(bumper)
	
	# Criando emissor de fumaça para danos
	smoke_emitter = CPUParticles2D.new()
	smoke_emitter.emitting = false
	smoke_emitter.amount = 30
	smoke_emitter.lifetime = 1.0
	smoke_emitter.gravity = Vector2(0, -98)
	smoke_emitter.scale_amount_min = 12.0 / 64.0
	smoke_emitter.scale_amount_max = 32.0 / 64.0
	smoke_emitter.color = Color(0.5, 0.5, 0.5, 0.8)
	smoke_emitter.texture = _make_soft_particle_texture()
	add_child(smoke_emitter)
	
	# Emissor de fogo
	flame_particles = CPUParticles2D.new()
	flame_particles.emitting = false
	flame_particles.amount = 40
	flame_particles.lifetime = 0.5
	flame_particles.gravity = Vector2(0, -140)
	flame_particles.initial_velocity_min = 40.0
	flame_particles.initial_velocity_max = 90.0
	flame_particles.scale_amount_min = 8.0 / 64.0
	flame_particles.scale_amount_max = 24.0 / 64.0
	flame_particles.color = Color(1.0, 0.45, 0.1, 0.95)
	flame_particles.texture = _make_soft_particle_texture()
	add_child(flame_particles)
	
	# Faíscas
	collision_particles = CPUParticles2D.new()
	collision_particles.emitting = false
	collision_particles.one_shot = true
	collision_particles.amount = 16
	collision_particles.lifetime = 0.5
	collision_particles.initial_velocity_min = 60.0
	collision_particles.initial_velocity_max = 120.0
	collision_particles.scale_amount_min = 2.0 / 64.0
	collision_particles.scale_amount_max = 5.0 / 64.0
	collision_particles.color = Color(0.8, 0.8, 0.8, 1.0)
	collision_particles.texture = _make_soft_particle_texture()
	add_child(collision_particles)
	
	# Motor com atenuação suave e volume balanceado
	engine_audio = AudioStreamPlayer2D.new()
	engine_audio.stream = _engine_sound.get_stream("street", active_archetype_id)
	engine_audio.max_distance = 420.0
	engine_audio.attenuation = 2.2
	engine_audio.volume_db = -16.0
	add_child(engine_audio)
	if is_driven_by_player:
		engine_audio.play()
	
	# Derrapagem
	skid_audio = AudioStreamPlayer2D.new()
	skid_audio.stream = ProceduralAudio.get_skid_stream(active_archetype_id)
	skid_audio.max_distance = 500.0
	skid_audio.volume_db = -16.0
	add_child(skid_audio)
	
	# Rádio do Carro
	radio_audio = AudioStreamPlayer2D.new()
	radio_audio.max_distance = 450.0
	radio_audio.volume_db = -18.0
	add_child(radio_audio)
	radio_tracks = ProceduralAudio.get_radio_stations()
	if is_driven_by_player and not radio_tracks.is_empty():
		radio_audio.stream = radio_tracks[radio_index]
		radio_audio.play()
	
	# 6. Nitro (NOS)
	nitro_audio = AudioStreamPlayer2D.new()
	nitro_audio.stream = ProceduralAudio.get_nitro_stream()
	nitro_audio.max_distance = 550.0
	nitro_audio.volume_db = -10.0
	add_child(nitro_audio)
	
	nitro_emitter = CPUParticles2D.new()
	nitro_emitter.emitting = false
	nitro_emitter.amount = 35
	nitro_emitter.lifetime = 0.30
	nitro_emitter.direction = Vector2(-1, 0)
	nitro_emitter.spread = 12.0
	nitro_emitter.gravity = Vector2.ZERO
	nitro_emitter.initial_velocity_min = 100.0
	nitro_emitter.initial_velocity_max = 190.0
	nitro_emitter.scale_amount_min = 4.0 / 64.0
	nitro_emitter.scale_amount_max = 10.0 / 64.0
	nitro_emitter.color = Color("#00cec9")
	nitro_emitter.texture = _make_soft_particle_texture()
	add_child(nitro_emitter)

	# Respingo de água lateral (derrapagem na chuva/poça)
	water_spray_emitter = CPUParticles2D.new()
	water_spray_emitter.emitting = false
	water_spray_emitter.amount = 22
	water_spray_emitter.lifetime = 0.45
	water_spray_emitter.explosiveness = 0.0
	water_spray_emitter.direction = Vector2(0, -1)
	water_spray_emitter.spread = 35.0
	water_spray_emitter.gravity = Vector2(0, 260.0)
	water_spray_emitter.initial_velocity_min = 60.0
	water_spray_emitter.initial_velocity_max = 150.0
	water_spray_emitter.scale_amount_min = 3.0 / 64.0
	water_spray_emitter.scale_amount_max = 7.0 / 64.0
	water_spray_emitter.color = Color(0.75, 0.86, 1.0, 0.65)
	water_spray_emitter.texture = _make_soft_particle_texture()
	add_child(water_spray_emitter)

	# Purga de Nitro Lateral/Capô (NOS Purge estilo Velozes e Furiosos)
	nos_purge_l = CPUParticles2D.new()
	nos_purge_l.emitting = false
	nos_purge_l.one_shot = true
	nos_purge_l.amount = 20
	nos_purge_l.lifetime = 0.4
	nos_purge_l.direction = Vector2(-0.4, -1.0)
	nos_purge_l.spread = 20.0
	nos_purge_l.initial_velocity_min = 80.0
	nos_purge_l.initial_velocity_max = 150.0
	nos_purge_l.color = Color(1.0, 1.0, 1.0, 0.85)
	nos_purge_l.texture = _make_soft_particle_texture()
	nos_purge_l.scale_amount_min = 4.0 / 64.0
	nos_purge_l.scale_amount_max = 10.0 / 64.0
	add_child(nos_purge_l)

	nos_purge_r = CPUParticles2D.new()
	nos_purge_r.emitting = false
	nos_purge_r.one_shot = true
	nos_purge_r.amount = 20
	nos_purge_r.lifetime = 0.4
	nos_purge_r.direction = Vector2(-0.4, 1.0)
	nos_purge_r.spread = 20.0
	nos_purge_r.initial_velocity_min = 80.0
	nos_purge_r.initial_velocity_max = 150.0
	nos_purge_r.color = Color(1.0, 1.0, 1.0, 0.85)
	nos_purge_r.texture = _make_soft_particle_texture()
	nos_purge_r.scale_amount_min = 4.0 / 64.0
	nos_purge_r.scale_amount_max = 10.0 / 64.0
	add_child(nos_purge_r)

	# Backfire de Escapamento (Labaredas e estalos nas reduções)
	backfire_emitter = CPUParticles2D.new()
	backfire_emitter.emitting = false
	backfire_emitter.one_shot = true
	backfire_emitter.amount = 15
	backfire_emitter.lifetime = 0.20
	backfire_emitter.direction = Vector2(-1, 0)
	backfire_emitter.spread = 25.0
	backfire_emitter.initial_velocity_min = 50.0
	backfire_emitter.initial_velocity_max = 110.0
	backfire_emitter.scale_amount_min = 3.0 / 64.0
	backfire_emitter.scale_amount_max = 9.0 / 64.0
	backfire_emitter.color = Color("#f39c12")
	backfire_emitter.texture = _make_soft_particle_texture()
	add_child(backfire_emitter)

	# Faíscas e fumaça de rodas raspando com pneu furado
	rim_sparks = CPUParticles2D.new()
	rim_sparks.emitting = false
	rim_sparks.amount = 25
	rim_sparks.lifetime = 0.35
	rim_sparks.direction = Vector2(-1, 0)
	rim_sparks.spread = 45.0
	rim_sparks.initial_velocity_min = 60.0
	rim_sparks.initial_velocity_max = 140.0
	rim_sparks.color = Color(1.0, 0.8, 0.2, 0.9)
	rim_sparks.texture = _make_soft_particle_texture()
	rim_sparks.scale_amount_min = 2.0 / 64.0
	rim_sparks.scale_amount_max = 4.0 / 64.0
	add_child(rim_sparks)

	flat_smoke = CPUParticles2D.new()
	flat_smoke.emitting = false
	flat_smoke.amount = 20
	flat_smoke.lifetime = 0.5
	flat_smoke.gravity = Vector2(0, -60)
	flat_smoke.color = Color(0.2, 0.2, 0.2, 0.7)
	flat_smoke.texture = _make_soft_particle_texture()
	flat_smoke.scale_amount_min = 8.0 / 64.0
	flat_smoke.scale_amount_max = 18.0 / 64.0
	add_child(flat_smoke)
	
	# Anexa o script de câmera dinâmica à câmera
	var dyn_cam = load("res://DynamicCamera.gd")
	if dyn_cam and camera:
		camera.set_script(dyn_cam)
		camera.set_process(true)
		
	# Apenas a câmera do veículo controlado é ativada
	if is_driven_by_player:
		camera.make_current()

	# Buzina do carro
	horn_audio = AudioStreamPlayer2D.new()
	horn_audio.stream = ProceduralAudio.get_horn_stream(active_archetype_id)
	horn_audio.max_distance = 500.0
	horn_audio.volume_db = -14.0
	add_child(horn_audio)

	_setup_headlight()

var is_night_or_storm: bool = false
var _headlight_override_active := false
var _headlight_override_state := false
var _horn_key_was_pressed := false
var _headlight_key_was_pressed := false

func set_headlights(dark_state: bool) -> void:
	is_night_or_storm = dark_state
	_apply_headlight_state()

func toggle_headlights() -> bool:
	var previous_state := is_headlight_on()
	_headlight_override_active = true
	_headlight_override_state = not previous_state
	_apply_headlight_state()
	return _headlight_override_state

func is_headlight_on() -> bool:
	if headlight == null or is_broken:
		return false
	if _headlight_override_active:
		return _headlight_override_state
	return is_night_or_storm or is_driven_by_player

func honk_horn():
	if is_broken or horn_audio == null:
		return
	if horn_audio.playing:
		horn_audio.stop()
	horn_audio.pitch_scale = randf_range(0.92, 1.08)
	horn_audio.play()

func _clear_headlight_override() -> void:
	_headlight_override_active = false
	_headlight_override_state = false

func _apply_headlight_state() -> void:
	if headlight == null:
		return
	if is_broken:
		headlight.visible = false
		return
	if _headlight_override_active:
		headlight.visible = _headlight_override_state
	else:
		headlight.visible = is_night_or_storm or is_driven_by_player

func _setup_headlight() -> void:
	if headlight:
		return

	headlight = PointLight2D.new()
	headlight.name = "Headlight"
	headlight.color = Color(1.0, 0.98, 0.90, 1.0)
	headlight.energy = 1.35
	headlight.shadow_enabled = false
	headlight.position = Vector2(38.0, 0.0) # Na frente do para-choque
	headlight.texture = HeadlightTextureGenerator.get_conical_headlight_texture()
	headlight.offset = Vector2(170.0, 0.0) # Projeta feixe cônico suave 340px à frente
	
	_apply_headlight_state()
	add_child(headlight)

func _get_weather_manager() -> Node:
	if _weather_manager_cache == null or not is_instance_valid(_weather_manager_cache):
		_weather_manager_cache = get_tree().get_first_node_in_group("day_night_manager")
	return _weather_manager_cache

func _physics_process(delta):
	preload("res://VehicleMotionSafety.gd").sanitize(self)
	has_nitro = false
	is_boosting = false
	if is_instance_valid(_boarding) and _boarding.active:
		velocity = Vector2.ZERO
		return
	var input_dir = 0.0
	var turn_dir = 0.0

	# Só processa os inputs se o jogador estiver no volante
	if is_driven_by_player:
		input_dir = Input.get_axis("ui_down", "ui_up")
		turn_dir = Input.get_axis("ui_left", "ui_right")
		if not _drive_input_armed:
			_drive_input_armed = is_zero_approx(input_dir) and is_zero_approx(turn_dir)
			input_dir = 0.0
			turn_dir = 0.0

		# Espaço = freio de mão / derrapagem manual. Shift = nitro (ver mais abaixo).
		var wants_handbrake := Input.is_key_pressed(KEY_SPACE)
		var weather := _get_weather_manager()
		var rain_intensity: float = float(weather.get_rain_intensity()) if weather and weather.has_method("get_rain_intensity") else 0.0

		# Chuva reduz o grip: derrapa mais fácil e corrige menos a traseira.
		var skid_threshold: float = lerpf(90.0, 50.0, rain_intensity)

		# Puxão de traseira ao puxar o freio de mão em curva, tipo GTA clássico.
		if wants_handbrake and turn_dir != 0.0 and velocity.length() > 60.0:
			velocity += transform.y * sign(turn_dir) * 130.0 * delta * clampf(velocity.length() / max_speed, 0.35, 1.0)

		# Lógica de Drift e Skidmarks
		var lateral_velocity = velocity.project(transform.y)
		lateral_speed = lateral_velocity.length()
		var is_actively_drifting := lateral_speed > skid_threshold or (wants_handbrake and velocity.length() > 60.0)
		if is_actively_drifting:
			if not is_skidding:
				is_skidding = true
				skid_line.clear_points()
			if skid_line.get_point_count() == 0 or skid_line.get_point_position(skid_line.get_point_count() - 1).distance_to(global_position) > 6.0:
				skid_line.add_point(global_position)
			if skid_line.get_point_count() > 30:
				skid_line.remove_point(0)
		else:
			is_skidding = false
			if skid_line.get_point_count() > 0 and bloody_tires_timer <= 0.0:
				skid_line.clear_points()

		velocity = preload("res://VehicleMotionSafety.gd").grip(velocity, global_rotation, drift_factor, delta, rain_intensity, wants_handbrake)
		if wants_handbrake: velocity = velocity.move_toward(Vector2.ZERO, braking*0.45*delta)

		# Respingo de água lateral: só quando derrapando com chuva de verdade caindo.
		if water_spray_emitter:
			var should_spray: bool = is_actively_drifting and rain_intensity > 0.05
			water_spray_emitter.emitting = should_spray
			if should_spray:
				var kick_side: float = -sign(lateral_velocity.dot(transform.y)) if lateral_velocity.length() > 1.0 else -sign(turn_dir)
				water_spray_emitter.direction = (transform.y * kick_side - transform.x * 0.35).normalized()
				water_spray_emitter.amount = int(lerpf(12.0, 26.0, rain_intensity))

		# Sincroniza áudio de derrapagem
		_update_skid_audio()

		# Teclas de validação rápida para veículo
		var horn_pressed := Input.is_key_pressed(KEY_H)
		if horn_pressed and not _horn_key_was_pressed:
			honk_horn()
		_horn_key_was_pressed = horn_pressed

		var headlights_pressed := Input.is_key_pressed(KEY_L)
		if headlights_pressed and not _headlight_key_was_pressed:
			toggle_headlights()
		_headlight_key_was_pressed = headlights_pressed

		# Verifica input para sair
		var exit_pressed := Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER) or (InputMap.has_action("interact") and Input.is_action_pressed("interact"))
		if not exit_pressed:
			_entry_input_released = true
		if _entry_input_released and exit_pressed and not _is_near_building_entrance():
			exit_vehicle()
	else:
		_horn_key_was_pressed = false
		_headlight_key_was_pressed = false
		lateral_speed = 0.0
		if water_spray_emitter and water_spray_emitter.emitting:
			water_spray_emitter.emitting = false
	
	# === Hit-stop: congela física por N frames ===
	if _hit_stop_frames > 0:
		_hit_stop_frames -= 1
		return  # Pula o restante do physics_process por esse frame

	_apply_steering_motion(turn_dir, delta)
	
	var forward_vec = transform.x
	# Backfire pop se soltar o acelerador em alta velocidade
	if _prev_throttle > 0.5 and input_dir <= 0.0 and velocity.length() > 220.0:
		if randf() > 0.4:
			_trigger_backfire()
			
	_prev_throttle = input_dir
	
	if input_dir != 0:
		if (input_dir > 0 and velocity.dot(forward_vec) < -10) or (input_dir < 0 and velocity.dot(forward_vec) > 10):
			velocity = velocity.move_toward(Vector2.ZERO, braking * delta)
		else:
			velocity += forward_vec * input_dir * acceleration * _engine_sound.drive_force(velocity.length(), max_speed) * delta
			velocity = velocity.limit_length(_engine_sound.road_top_speed(max_speed))
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	var prev_velocity = velocity
	preload("res://VehicleMotionSafety.gd").move(self)
	
	# Mantém a posição do Dante perfeitamente sincronizada com o veículo enquanto dirige
	if is_driven_by_player:
		var current_driver := get_tree().get_first_node_in_group("player") as Node2D
		if current_driver and is_instance_valid(current_driver):
			current_driver.global_position = global_position

	# === Motor Dinâmico (Pitch por Velocidade) ===
	if is_driven_by_player:
		if engine_audio and engine_audio.stream:
			if health > 0:
				_engine_sound.update(engine_audio, velocity.length(), _engine_sound.road_top_speed(max_speed), input_dir, delta, active_archetype_id, is_boosting)
			else:
				if engine_audio.playing:
					engine_audio.stop()
		
		# === Rádio (Tecla R ou Input radio_next) ===
		if Input.is_key_pressed(KEY_R) or (InputMap.has_action("radio_next") and Input.is_action_just_pressed("radio_next")):
			_next_radio_track()
	else:
		if engine_audio and engine_audio.playing:
			engine_audio.stop()
		if radio_audio and radio_audio.playing:
			radio_audio.stop()
		if skid_audio and skid_audio.playing:
			skid_audio.stop()
	
	# === Verifica colisões e dispara áudio de impacto ===
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var body = col.get_collider()
		# get_normal() aponta da parede pra fora (pro lado do carro). Só conta
		# como impacto quando a velocidade vai CONTRA essa normal (carro
		# entrando na parede) — não quando ela se afasta (saindo de ré), senão
		# um contato residual de 1-2 frames continua batendo mesmo recuando.
		var closing_speed = maxf(0.0, -prev_velocity.dot(col.get_normal()))
		var impact_speed = maxf(prev_velocity.length() - velocity.length(), closing_speed)
		
		if impact_speed > 35.0:
			# Deforma a lataria (amassa parachoque, capô, portas ou traseira no ponto exato)
			_apply_crash_deformation(col.get_normal(), impact_speed, col.get_position())
			
			# Screen Shake proporcional ao impacto
			_do_screen_shake(clampf(impact_speed / 500.0, 0.05, 0.4))
			
			# Hit-stop: 2 frames em impactos médios, 3 frames em violentos
			_hit_stop_frames = 3 if impact_speed > 250 else 2
			
			# Partículas de metal/vidro
			collision_particles.global_position = col.get_position()
			collision_particles.restart()
			
			# Som de batida dinâmico
			var crash_player = AudioStreamPlayer2D.new()
			crash_player.stream = ProceduralAudio.get_crash_stream(active_archetype_id)
			crash_player.pitch_scale = randf_range(0.85, 1.15)
			crash_player.volume_db = clampf(lerp(-18.0, -6.0, impact_speed / 500.0), -22.0, -4.0)
			crash_player.max_distance = 600.0
			add_child(crash_player)
			crash_player.play()
			crash_player.finished.connect(crash_player.queue_free)
		
		# A car sliding sideways along a curb/wall reports a fresh slide
		# collision EVERY physics frame it stays in contact (that is what
		# move_and_slide is for). Without a cooldown, a single sideways skid
		# could call take_damage() 20-40 times in under a second -- each
		# individually below what feels like "a real crash" -- and zero the
		# car's health almost instantly, reading as an explosion out of
		# nowhere. Only the first frame of a given contact should count as
		# a hit; a short cooldown lets the car keep sliding without being
		# charged damage on every single frame of that same scrape.
		if impact_speed > 160.0 and Time.get_ticks_msec() - _last_collision_damage_ms > COLLISION_DAMAGE_COOLDOWN_MS:
			_last_collision_damage_ms = Time.get_ticks_msec()
			take_damage(int(impact_speed * 0.06))
			
		# Atropelar pessoas no slide collision!
		if prev_velocity.length() > 25.0:
			if is_instance_valid(body) and not body.is_in_group("ambient_traffic") and not body.is_in_group("vehicle"):
				if not (body.is_in_group("player") and is_driven_by_player):
					if body.has_method("get_run_over"):
						body.get_run_over(prev_velocity, true)
						_activate_bloody_tires()
					elif body.has_method("take_damage"):
						body.take_damage(100, true)

	# Gerencia marcas de pneu sangrentas após atropelar alguém
	if bloody_tires_timer > 0.0:
		bloody_tires_timer -= delta
		if velocity.length() > 40.0:
			skid_line.add_point(global_position)
			if skid_line.get_point_count() > 60:
				skid_line.remove_point(0)
		if bloody_tires_timer <= 0.0:
			skid_line.default_color = Color(0.1, 0.1, 0.1, 0.5)

var _door_visual: Node2D = null

func _on_bumper_hitbox_entered(body: Node2D) -> void:
	if body == null or body == self or (body.is_in_group("player") and is_driven_by_player) or body.is_in_group("ambient_traffic") or body.is_in_group("vehicle"):
		return # Nunca atropelar ou causar dano ao próprio motorista ao entrar ou dirigir!
	var cur_speed = velocity.length()
	if cur_speed > 25.0:
		var impact = velocity if cur_speed > 10.0 else transform.x * maxf(120.0, cur_speed)
		if body.has_method("get_run_over"):
			body.get_run_over(impact, true)
			_activate_bloody_tires()
		elif body.has_method("take_damage"):
			body.take_damage(100, true)

func _apply_steering_motion(turn_input: float, delta: float) -> void:
	# Preserve existing handling for ordinary cars; specialized vehicles can
	# supply their own steering geometry without duplicating collision/gameplay.
	if velocity.length() > 10:
		var current_turn: float = turn_input * turn_speed * delta
		if velocity.dot(transform.x) < 0:
			current_turn *= -1
		rotation += current_turn

func _activate_bloody_tires() -> void:
	bloody_tires_timer = 4.0
	if skid_line:
		skid_line.default_color = Color(0.72, 0.05, 0.05, 0.85)
	_do_screen_shake(0.18)

func _get_safe_exit_position() -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var candidates: Array[Vector2] = [
		global_position - transform.y * 45.0, # Porta do motorista (esquerda)
		global_position + transform.y * 45.0, # Porta do passageiro (direita)
		global_position - transform.x * 52.0, # Traseira
		global_position + transform.x * 52.0  # Dianteira
	]
	for pos in candidates:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = pos
		query.collision_mask = 1 # Camada de colisão sólida do cenário
		var result := space_state.intersect_point(query, 1)
		if result.is_empty():
			return pos
	return candidates[0]

func _is_near_building_entrance() -> bool:
	for node in get_tree().get_nodes_in_group("harbor_entrance"):
		if node.has_method("is_actor_in_range") and node.is_actor_in_range(self):
			return true
	for node in get_tree().get_nodes_in_group("harbor_interior_exit"):
		if node.has_method("is_actor_in_range") and node.is_actor_in_range(self):
			return true
	return false

var _boarding: Node

func exit_vehicle():
	if not is_driven_by_player:
		return
	if is_instance_valid(_boarding): _boarding.cancel()
	var camera_view := preload("res://DynamicCamera.gd").capture_view(get_viewport())
	is_driven_by_player = false
	_clear_headlight_override()
	velocity = Vector2.ZERO
	is_boosting = false
	if engine_audio: engine_audio.stop()
	if skid_audio: skid_audio.stop()
	if radio_audio: radio_audio.stop()
	_apply_headlight_state()
	
	var exit_position := _get_safe_exit_position()
	_animate_car_door(-1.0 if to_local(exit_position).y <= 0 else 1.0)
	
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = exit_position
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		for col in player.find_children("", "CollisionShape2D", true, false):
			col.set_deferred("disabled", false)
		player.show()
		player.set_physics_process(true)
		remove_collision_exception_with(player)
		player.remove_collision_exception_with(self)
		var p_cam = player.get_node_or_null("Camera") as Camera2D
		if p_cam:
			preload("res://DynamicCamera.gd").handoff(p_cam, camera_view)

func enter_vehicle(player_body: CharacterBody2D) -> void:
	if is_driven_by_player or player_body == null or health <= 0:
		return
	var approach := player_body.global_position
	var entry_side := -1.0 if to_local(approach).y <= 0 else 1.0
	var camera_view := preload("res://DynamicCamera.gd").capture_view(get_viewport())
	is_driven_by_player = true
	_entry_input_released = false
	_drive_input_armed = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").is_zero_approx()
	_last_collision_damage_ms = Time.get_ticks_msec()
	add_collision_exception_with(player_body)
	player_body.add_collision_exception_with(self)
	_hit_stop_frames = 0
	is_skidding = false
	if skid_line: skid_line.clear_points()
	_clear_headlight_override()
	velocity = Vector2.ZERO
	is_boosting = false
	
	# Desativa colisor físico do jogador para neutralizar impulsos de colisão corpo-carro
	for col in player_body.find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", true)
	player_body.velocity = Vector2.ZERO
	player_body.global_position = global_position
	player_body.reset_physics_interpolation()
	
	# Animação visual da porta abrindo e batendo
	_animate_car_door(entry_side, 0.95 if entry_side > 0 else 0.6)
	
	player_body.hide()
	player_body.set_physics_process(false)
	for hud in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("show_vehicle_name"):
			hud.show_vehicle_name(String(VehicleCatalog.get_vehicle_spec(active_archetype_id).get("label", "Veículo")))
	preload("res://DynamicCamera.gd").handoff(camera, camera_view)
	if engine_audio:
		engine_audio.play()
	if radio_audio and not radio_tracks.is_empty():
		radio_audio.stream = radio_tracks[radio_index]
		radio_audio.play()

	_boarding = preload("res://VehicleBoarding.gd").new()
	add_child(_boarding)
	_boarding.begin(self, player_body, approach, entry_side)

func _animate_car_door(side: float = -1.0, hold_seconds: float = 0.42) -> void:
	if _door_visual == null:
		_door_visual = VEHICLE_DOOR_VISUAL.new()
		_door_visual.name = "ProceduralVehicleDoor"
		_door_visual.configure(Vector2(13.0, -15.0), 32.0)
		add_child(_door_visual)
	var body_color := sprite.modulate if sprite != null else Color("#d94141")
	_door_visual.play(body_color, side, hold_seconds)

func take_damage(amount: int, _is_player_attacker: bool = false):
	health -= amount
	if health < 75:
		sprite.modulate = Color(0.8, 0.8, 0.8) # Levemente arranhado/sujo
	if health < 50:
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.5, 0.5, 0.5, 0.8) # Fumaça branca/cinza
	if health <= 25:
		sprite.modulate = Color(0.5, 0.5, 0.5) # Bem amassado/sujo
		smoke_emitter.color = Color(0.1, 0.1, 0.1, 0.9) # Fumaça preta
		smoke_emitter.amount = 60 # Fumaça densa
	
	if health <= 0:
		health = 0
		is_broken = true
		max_speed = 0.0
		if not is_exploding and not is_exploded:
			_start_combustion_countdown()
		_dispatch_fire_truck()

var is_exploding: bool = false
var is_exploded: bool = false

const COLLISION_DAMAGE_COOLDOWN_MS := 650
var _last_collision_damage_ms: int = -999999

func _start_combustion_countdown() -> void:
	if is_exploding or is_exploded: return
	is_exploding = true
	if flame_particles: flame_particles.emitting = true
	if smoke_emitter:
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.1, 0.1, 0.1, 0.95)
		smoke_emitter.amount = 65
	# O jogador NÃO é expulso automaticamente aqui: ele tem 3.2s para saltar com F/Enter!
		
	# Contagem para a grande explosão (3.2s)
	await get_tree().create_timer(3.2).timeout
	if not is_exploded and health <= 0:
		_explode()

func _explode() -> void:
	if is_exploded: return
	is_exploded = true
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	_apply_headlight_state()
	
	# Se o jogador ainda estiver no veículo na detonação final, ele é ejetado e toma o dano da explosão
	if is_driven_by_player:
		var player_node = get_tree().get_first_node_in_group("player")
		exit_vehicle()
		if is_instance_valid(player_node) and player_node.has_method("take_damage"):
			player_node.take_damage(100) # Dano crítico de explosão
	
	# 1. Som estrondoso de explosão potente
	var p = AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_explosion_stream()
	p.volume_db = 2.0
	p.max_distance = 1200.0
	get_parent().add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)
	
	# 2. Bola de fogo e detonação intensa
	var fireball := CPUParticles2D.new()
	fireball.global_position = global_position
	fireball.emitting = true
	fireball.one_shot = true
	fireball.explosiveness = 0.98
	fireball.amount = 45
	fireball.lifetime = 1.0
	fireball.spread = 180.0
	fireball.initial_velocity_min = 160.0
	fireball.initial_velocity_max = 420.0
	fireball.gravity = Vector2(0, 120)
	fireball.scale_amount_min = 50.0 / 64.0
	fireball.scale_amount_max = 120.0 / 64.0
	fireball.color = Color(1.0, 0.48, 0.08, 0.95)
	fireball.texture = _make_soft_particle_texture()
	get_parent().add_child(fireball)
	
	# 3. Estilhaços metálicos incandescentes
	var shrapnel := CPUParticles2D.new()
	shrapnel.global_position = global_position
	shrapnel.emitting = true
	shrapnel.one_shot = true
	shrapnel.explosiveness = 0.95
	shrapnel.amount = 30
	shrapnel.lifetime = 0.9
	shrapnel.spread = 180.0
	shrapnel.initial_velocity_min = 200.0
	shrapnel.initial_velocity_max = 500.0
	shrapnel.gravity = Vector2(0, 350)
	shrapnel.scale_amount_min = 2.0 / 64.0
	shrapnel.scale_amount_max = 5.0 / 64.0
	shrapnel.color = Color(1.0, 0.85, 0.3)
	shrapnel.texture = _make_soft_particle_texture()
	get_parent().add_child(shrapnel)
	
	# 4. Clarão de Luz Instantâneo
	var flash_light := PointLight2D.new()
	flash_light.color = Color(1.0, 0.85, 0.5)
	flash_light.energy = 1.6 # Reduzido de 4.5: com a textura de particula nova,
	# o valor antigo deixava a tela inteira estourada em branco/laranja.
	var f_grad = Gradient.new()
	f_grad.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var f_tex = GradientTexture2D.new()
	f_tex.gradient = f_grad
	f_tex.width = 260
	f_tex.height = 260
	f_tex.fill = GradientTexture2D.FILL_RADIAL
	f_tex.fill_from = Vector2(0.5, 0.5)
	f_tex.fill_to = Vector2(1.0, 0.5)
	flash_light.texture = f_tex
	flash_light.global_position = global_position
	get_parent().add_child(flash_light)
	var fl_tween = flash_light.create_tween()
	fl_tween.tween_property(flash_light, "energy", 0.0, 0.45)
	fl_tween.tween_callback(flash_light.queue_free)
	
	# 5. Marca de Asfalto Queimado no Solo
	var scorch := Polygon2D.new()
	var sc_pts = PackedVector2Array()
	var sc_count = 14
	for k in sc_count:
		var ang = k * TAU / sc_count
		var rad = randf_range(34.0, 52.0)
		sc_pts.append(Vector2(cos(ang), sin(ang)) * rad)
	scorch.polygon = sc_pts
	scorch.color = Color(0.04, 0.04, 0.05, 0.85)
	scorch.global_position = global_position
	scorch.z_index = -15
	get_parent().add_child(scorch)
	
	# 6. Carcaça queimada estável no solo (sem salto no ar, sem teleporte, sem deformação)
	if sprite:
		sprite.modulate = Color(0.12, 0.12, 0.12)
		sprite.scale = Vector2(uniform_scale, uniform_scale)
		sprite.position = Vector2.ZERO
		sprite.skew = 0.0
	
	# 7. Screen Shake
	_do_screen_shake(0.70)
		
	# 8. Onda de choque
	var blast_radius = 210.0
	for body in get_tree().get_nodes_in_group("damageable"):
		if body != self and is_instance_valid(body):
			var d = global_position.distance_to(body.global_position)
			if d < blast_radius:
				var blast_dir = global_position.direction_to(body.global_position)
				if body.has_method("get_run_over"):
					body.get_run_over(blast_dir * 550.0)
				elif body.has_method("take_damage"):
					body.take_damage(int(lerp(120.0, 35.0, d / blast_radius)))

var _fire_truck_dispatched: bool = false

func _dispatch_fire_truck():
	if _fire_truck_dispatched:
		return
	var depot_director = get_tree().get_first_node_in_group("emergency_depot_director")
	if depot_director and depot_director.has_method("request_dispatch"):
		var dispatched = depot_director.request_dispatch("fire", self, false)
		_fire_truck_dispatched = dispatched != null
		return
	var pool = get_node_or_null("/root/EmergencyPool")
	if pool:
		var fire_truck = pool.get_vehicle("fire")
		if fire_truck:
			push_warning("EmergencyDepotDirector missing: fire dispatch cancelled")
			pool.return_vehicle(fire_truck)

func extinguish_fire() -> void:
	_fire_truck_dispatched = false
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	if smoke_emitter:
		smoke_emitter.color = Color(0.9, 0.9, 0.9, 0.5)
		smoke_emitter.amount = 35

var damage_deformation_scale := Vector2(1.0, 1.0)
var damage_deformation_offset := Vector2.ZERO
var damage_skew := 0.0
var dents_container: Node2D = null

func _ensure_dents_container() -> void:
	if dents_container == null:
		dents_container = Node2D.new()
		dents_container.name = "CrashDents"
		dents_container.z_index = 2
		add_child(dents_container)

var _last_crash_visual_ms := -999999

func _apply_crash_deformation(_impact_normal: Vector2, impact_force: float, _hit_world_pos: Vector2 = Vector2.ZERO) -> void:
	if sprite == null or impact_force < 80.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_crash_visual_ms < 650:
		return
	_last_crash_visual_ms = now
	# Preserve the authored body; generic polygon dents protrude beyond its silhouette.
	sprite.modulate = sprite.modulate.lerp(Color(0.72, 0.72, 0.74), 0.08)
	if not "body_model" in self:
		_ensure_dents_container()
		_spawn_dent_decal(to_local(_hit_world_pos),global_transform.basis_xform_inv(_impact_normal),clampf(impact_force/420.0,0,1))


func _spawn_dent_decal(local_pos: Vector2, dir: Vector2, strength: float) -> void:
	if dents_container == null: return
	var footprint := Vector2(54,24)
	var shape := get_node_or_null("Collision") as CollisionShape2D
	if shape and shape.shape is RectangleShape2D: footprint = shape.shape.size
	preload("res://VehicleSurfaceWear2D.gd").add_scrape(dents_container,local_pos,dir,footprint,strength)

func _flicker_and_damage_headlight() -> void:
	if headlight == null: return
	var tw := create_tween()
	tw.tween_property(headlight, "energy", 0.1, 0.06)
	tw.tween_property(headlight, "energy", 1.2, 0.08)
	tw.tween_property(headlight, "energy", 0.0, 0.10)
	tw.tween_property(headlight, "energy", 0.40, 0.12)

func _clear_all_dents() -> void:
	if dents_container:
		for child in dents_container.get_children():
			child.queue_free()
	if headlight:
		headlight.energy = 1.35

func _spawn_flying_debris(pos: Vector2, normal: Vector2) -> void:
	var debris_emitter := CPUParticles2D.new()
	debris_emitter.global_position = pos
	debris_emitter.emitting = true
	debris_emitter.one_shot = true
	debris_emitter.explosiveness = 0.95
	debris_emitter.amount = 18
	debris_emitter.lifetime = 0.75
	debris_emitter.direction = normal
	debris_emitter.spread = 65.0
	debris_emitter.initial_velocity_min = 90.0
	debris_emitter.initial_velocity_max = 220.0
	debris_emitter.gravity = Vector2(0, 220)
	debris_emitter.scale_amount_min = 2.0 / 64.0
	debris_emitter.scale_amount_max = 4.5 / 64.0
	debris_emitter.color = Color(0.85, 0.85, 0.9, 0.9)
	debris_emitter.texture = _make_soft_particle_texture()
	get_parent().add_child(debris_emitter)
	var t = debris_emitter.create_tween()
	t.tween_interval(1.2)
	t.tween_callback(debris_emitter.queue_free)

static var _cached_soft_particle_texture: GradientTexture2D = null

static func _make_soft_particle_texture() -> GradientTexture2D:
	# Particle scales are multipliers of this 64px texture, NOT pixel sizes.
	# Emitters above specify their world-pixel diameter divided by 64.
	if _cached_soft_particle_texture != null:
		return _cached_soft_particle_texture
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_cached_soft_particle_texture = tex
	return tex

func _do_screen_shake(intensity: float):
	if not camera: return
	var tween = create_tween()
	var steps = 6
	var duration = 0.05
	for i in steps:
		var offset = Vector2(randf_range(-1,1), randf_range(-1,1)) * intensity * 30.0
		tween.tween_property(camera, "offset", offset, duration)
	tween.tween_property(camera, "offset", Vector2.ZERO, duration)

func _update_skid_audio():
	if not skid_audio or not skid_audio.stream: return
	if is_skidding and not skid_audio.playing:
		skid_audio.play()
	elif not is_skidding and skid_audio.playing:
		skid_audio.stop()

func _load_radio_tracks():
	var dir = DirAccess.open("res://audio/radio/") if DirAccess.dir_exists_absolute("res://audio/radio/") else null
	if not dir: return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".mp3") or fname.ends_with(".ogg") or fname.ends_with(".wav"):
			radio_tracks.append("res://audio/radio/" + fname)
		fname = dir.get_next()

func _next_radio_track():
	if radio_tracks.is_empty():
		radio_tracks = ProceduralAudio.get_radio_stations()
	if radio_tracks.is_empty(): return
	radio_index = (radio_index + 1) % radio_tracks.size()
	var track = radio_tracks[radio_index]
	if track is String:
		track = load(track)
	if track is AudioStream:
		radio_audio.stream = track
		radio_audio.play()

@export var vehicle_mass: float = 0.85
@export var max_health: int = 100
var active_archetype_id: String = "sport_coupe"
var active_roof_prop_node: Node2D = null

func apply_archetype(archetype_id: String, custom_color: Color = Color.TRANSPARENT) -> void:
	active_archetype_id = archetype_id
	var spec: Dictionary = VehicleCatalog.get_vehicle_spec(archetype_id)
	if spec.is_empty(): return
	
	max_speed = float(spec.get("max_speed", 600.0))
	acceleration = float(spec.get("acceleration", 1200.0))
	braking = float(spec.get("braking", 1500.0))
	turn_speed = float(spec.get("turn_speed", 3.5))
	drift_factor = float(spec.get("drift_factor", 0.9))
	vehicle_mass = float(spec.get("mass", 0.85))
	max_health = int(spec.get("durability", 100))
	health = max_health
	
	var chosen_color: Color
	if custom_color != Color.TRANSPARENT:
		chosen_color = custom_color
	else:
		chosen_color = VehicleCatalog.get_random_color(archetype_id)
		
	if sprite:
		sprite.modulate = chosen_color
		
	_build_roof_prop(String(spec.get("roof_prop", "none")))
	_refresh_vehicle_sound_sets()


func _refresh_vehicle_sound_sets() -> void:
	if engine_audio:
		var was_engine_playing := engine_audio.playing
		engine_audio.stream = _engine_sound.get_stream("street", active_archetype_id)
		if was_engine_playing:
			engine_audio.play()

	if skid_audio:
		skid_audio.stream = ProceduralAudio.get_skid_stream(active_archetype_id)

	if horn_audio:
		horn_audio.stream = ProceduralAudio.get_horn_stream(active_archetype_id)

func _build_roof_prop(prop_type: String) -> void:
	if active_roof_prop_node and is_instance_valid(active_roof_prop_node):
		active_roof_prop_node.queue_free()
		active_roof_prop_node = null
		
	if prop_type == "none": return
	
	active_roof_prop_node = Node2D.new()
	active_roof_prop_node.name = "RoofProp"
	active_roof_prop_node.z_index = 11
	add_child(active_roof_prop_node)
	
	match prop_type:
		"spoiler":
			var spoiler = Polygon2D.new()
			spoiler.color = Color(0.1, 0.1, 0.12)
			spoiler.polygon = PackedVector2Array([
				Vector2(-target_length * 0.38, -14), Vector2(-target_length * 0.32, -14),
				Vector2(-target_length * 0.32, 14), Vector2(-target_length * 0.38, 14)
			])
			active_roof_prop_node.add_child(spoiler)
		"spare_wheel":
			var wheel = Polygon2D.new()
			wheel.color = Color(0.12, 0.12, 0.14)
			var pts = PackedVector2Array()
			for i in 10:
				var a = i * TAU / 10.0
				pts.append(Vector2(-target_length * 0.42 + cos(a) * 7.0, sin(a) * 7.0))
			wheel.polygon = pts
			active_roof_prop_node.add_child(wheel)
		"surfboard":
			var surf = Polygon2D.new()
			surf.color = Color(0.95, 0.35, 0.2)
			surf.polygon = PackedVector2Array([
				Vector2(-20, -5), Vector2(20, -2), Vector2(24, 0), Vector2(20, 2), Vector2(-20, 5)
			])
			surf.rotation = 0.12
			active_roof_prop_node.add_child(surf)

func repaint_vehicle(new_color: Color = Color.TRANSPARENT) -> void:
	if new_color != Color.TRANSPARENT:
		if sprite: sprite.modulate = new_color
	else:
		if sprite: sprite.modulate = VehicleCatalog.get_random_color(active_archetype_id)

func repair_and_repaint(new_color: Color = Color.TRANSPARENT) -> void:
	repair_vehicle()
	repaint_vehicle(new_color)

func repair_vehicle() -> void:
	health = max_health
	is_broken = false
	is_exploding = false
	is_exploded = false
	damage_deformation_scale = Vector2(1.0, 1.0)
	damage_deformation_offset = Vector2.ZERO
	damage_skew = 0.0
	if sprite:
		sprite.scale = Vector2(uniform_scale, uniform_scale)
		sprite.position = Vector2.ZERO
		sprite.skew = 0.0
	if smoke_emitter:
		smoke_emitter.emitting = false
		smoke_emitter.amount = 30
	if flame_particles:
		flame_particles.emitting = false
	if rim_sparks:
		rim_sparks.emitting = false
	if flat_smoke:
		flat_smoke.emitting = false
	has_punctured_tires = false
	_clear_all_dents()

func puncture_tires() -> void:
	if has_puncture_proof_tires or has_punctured_tires: return
	has_punctured_tires = true
	if rim_sparks: rim_sparks.emitting = true
	if flat_smoke: flat_smoke.emitting = true
	max_speed *= 0.45
	acceleration *= 0.50
	turn_speed *= 0.70
	drift_factor = 0.40

func _trigger_nos_purge() -> void:
	if nos_purge_l: nos_purge_l.restart()
	if nos_purge_r: nos_purge_r.restart()
	var p := AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_nos_purge_stream()
	p.volume_db = -4.0
	p.max_distance = 450.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _trigger_backfire() -> void:
	if backfire_emitter: backfire_emitter.restart()
	var p := AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_exhaust_backfire_stream()
	p.volume_db = -6.0
	p.max_distance = 450.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _setup_neon_underglow() -> void:
	if not has_neon:
		if neon_underglow_poly: neon_underglow_poly.visible = false
		return
		
	if neon_underglow_poly == null:
		neon_underglow_poly = Polygon2D.new()
		neon_underglow_poly.name = "NeonUnderglow"
		neon_underglow_poly.z_index = -1
		var w = target_length * 0.95
		var h = maxf(38.0, target_length * 0.55)
		neon_underglow_poly.polygon = PackedVector2Array([
			Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5),
			Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)
		])
		add_child(neon_underglow_poly)
		
		var tw = create_tween().set_loops()
		tw.tween_property(neon_underglow_poly, "color:a", 0.65, 0.45)
		tw.tween_property(neon_underglow_poly, "color:a", 0.25, 0.45)

	neon_underglow_poly.visible = true
	neon_underglow_poly.color = Color(neon_color.r, neon_color.g, neon_color.b, 0.40)
