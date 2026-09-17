class_name DemoTrafficVehicle
extends CharacterBody2D

signal player_entered(vehicle: CharacterBody2D)

var _handling_yaw_rate: float = 0.0
var _drivetrain = preload("res://cars/VehicleDrivetrain.gd").new()
var _launch = preload("res://cars/VehicleLaunchControl.gd").new()
var _tire_trail = preload("res://cars/VehicleTireTrail.gd").new()

const VEHICLE_ATLAS: Texture2D = preload("res://assets/art/vehicle-atlas.png")
const VEHICLE_DOOR_VISUAL := preload("res://cars/VehicleDoorVisual.gd")
const MAX_LANE_ADVANCE_PER_FRAME := 14.0
## Medido com tests/measure_harbor_performance.gd (bisecção real): tráfego
## ambiente custava ~30-40 FPS o tempo todo dirigindo, porque "na tela" usa
## uma margem generosa (260px) e todo carro nela roda advance_on_lane() --
## raycasts de obstrução, sweep de física, negociação de cruzamento -- a
## taxa cheia, mesmo o carro estando na periferia da tela, longe do jogador.
## Perto do centro da câmera (onde o jogador realmente presta atenção) o
## carro continua a taxa cheia; na tela mas fora desse raio cai pra um nível
## intermediário -- mais devagar que taxa cheia, mais rápido que o 10 Hz já
## usado pra fora da tela. Não muda nada dentro de advance_on_lane() em si.
const NEAR_CENTER_RADIUS_PX := 520.0
const MID_TIER_INTERVAL := 1.0 / 24.0
const TRAFFIC_FLOW := preload("res://cars/traffic/TrafficFlowModel.gd")
const TRAFFIC_SWEEP := preload("res://cars/traffic/TrafficBodySweep.gd")

@export var vehicle_id: String = "vehicle"
@export var display_name: String = "Veículo"
@export var characteristic: String = "Tráfego urbano"
@export var speed: float = 105.0
@export var crop: Rect2 = Rect2(52, 106, 218, 392)
@export var target_length: float = 74.0
@export var max_speed: float = 520.0
@export var acceleration: float = 950.0
@export var braking: float = 1250.0
@export var friction: float = 550.0
@export var turn_speed: float = 3.3
var lateral_speed: float = 0.0
var handbrake_slide: float = 0.0
var _drift_weather: Node
@export var drift_factor: float = 0.9

var visual: Sprite2D
var collision: CollisionShape2D
var camera: Camera2D
var pedestrian_hitbox: Area2D

var is_driven_by_player := false
var is_motorcycle := false
var _rider_fallen := false
var _traffic_horn_cooldown := 0.0
var _waiting_person: WeakRef
var _person_wait := 0.0
var _person_warned := false
var _person_push_time := 0.0
const PERSON_HORN_DELAY := 1.2
const PERSON_WARNING_GRACE := 3.0
var _avoidance_hold := 0.0
var _lane_sweep_blocked := false
var _emergency_yield_active := false
var _siren_maneuver := preload("res://cars/traffic/TrafficSirenManeuver.gd").new()
var _driver: CharacterBody2D
var taxi_passenger := false
var _taxi_service: CanvasLayer
var _detached_from_lane := false
var _abandoned_timer: float = 0.0
var health: int = 100
var is_broken := false
var uniform_scale: float = 1.0

# === Juice & VFX ===
var skid_line: Line2D
var is_skidding: bool = false
var smoke_emitter: CPUParticles2D
var collision_particles: CPUParticles2D
var headlight: PointLight2D
var _hit_stop_frames: int = 0
var _last_collision_damage_ms := -999999
var bloody_tires_timer: float = 0.0
var flame_particles: CPUParticles2D

# === Upgrades & Tuning (Fast & Furious Style) ===
var has_nitro: bool = false
var nitro_amount: float = 0.0
var nitro_max: float = 0.0
var is_boosting: bool = false
var nitro_emitter: CPUParticles2D
var nitro_audio: AudioStreamPlayer2D

var nos_purge_l: CPUParticles2D
var nos_purge_r: CPUParticles2D
var backfire_emitter: CPUParticles2D
var _prev_throttle_val: float = 0.0

var has_puncture_proof_tires: bool = false
var has_punctured_tires: bool = false
var rim_sparks: CPUParticles2D
var flat_smoke: CPUParticles2D

var has_neon: bool = false
var neon_color: Color = Color("#00cec9")
var neon_underglow_poly: Polygon2D

# === Áudio ===
var horn_audio: AudioStreamPlayer2D
var siren_audio: AudioStreamPlayer2D
var engine_audio: AudioStreamPlayer2D
var _engine_sound := preload("res://audio/VehicleEngineSound.gd").new()
var second_headlight: PointLight2D
var _lamp_mounts: Array[Vector3] = []
var skid_audio: AudioStreamPlayer2D
var radio_audio: AudioStreamPlayer2D
var radio_tracks: Array = []
var radio_index: int = 0

# Sistema de Viatura Policial & Alarme Anti-Furto
var is_police_vehicle: bool = false
var is_standby_unit: bool = false
var standby_source: Node = null
var was_stolen_from_police: bool = false
var is_alarm_active: bool = false
var alarm_timer: float:
	get: return _alarm_timeout.time_left if is_instance_valid(_alarm_timeout) else 0.0
var _alarm_timeout: Timer
var has_theft_alarm := false
var _parked_security_configured := false
var _parked_theft_attempted := false
var _police_lock_unlocked := false
var _vehicle_lockpick: CanvasLayer
var is_siren_on: bool = false
var _strobe_timer: float = 0.0
var alarm_audio: AudioStreamPlayer2D

# Suporte a Modelos 3D Procedurais (Frota Fase 2)
var is_3d_vehicle: bool = false
var defer_presentation := false
var _pending_spec: Dictionary = {}
var _pending_color := Color.WHITE

func ensure_presentation() -> void:
	if _pending_spec.is_empty():
		return
	var spec := _pending_spec
	_pending_spec = {}
	_setup_3d_model(spec, _pending_color)
var body_viewport: SubViewport = null
var body_model: Node3D = null
var lightbar_3d := preload("res://emergency/EmergencyLightbar3D.gd").new()
var wheel_rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
var wheels: Array[Node3D] = []
var spinners: Array[Node3D] = []

func _ensure_required_nodes() -> void:
	visual = get_node_or_null("Visual") as Sprite2D
	if visual == null:
		visual = Sprite2D.new()
		visual.name = "Visual"
		add_child(visual)
	collision = get_node_or_null("Collision") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "Collision"
		add_child(collision)
	camera = get_node_or_null("Camera") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera"
		camera.enabled = false
		add_child(camera)
	pedestrian_hitbox = get_node_or_null("PedestrianHitbox") as Area2D
	if pedestrian_hitbox == null:
		pedestrian_hitbox = Area2D.new()
		pedestrian_hitbox.name = "PedestrianHitbox"
		add_child(pedestrian_hitbox)
	if pedestrian_hitbox.get_node_or_null("Collision") == null:
		var hitbox_collision := CollisionShape2D.new()
		hitbox_collision.name = "Collision"
		pedestrian_hitbox.add_child(hitbox_collision)

func _ready() -> void:
	preload("res://cars/VehicleMotionSafety.gd").configure(self)
	collision_mask |= 2
	_ensure_required_nodes()
	health = 100
	is_broken = false
	z_index = 10
	add_to_group("ambient_traffic")
	add_to_group("vehicle")
	pedestrian_hitbox.body_entered.connect(_on_pedestrian_hitbox_body_entered)
	
	# Visual
	var texture := AtlasTexture.new()
	texture.atlas = VEHICLE_ATLAS
	texture.region = crop
	visual.texture = texture
	uniform_scale = target_length / maxf(1.0, crop.size.y)
	visual.scale = Vector2(uniform_scale, uniform_scale)
	visual.rotation = PI * 0.5
	
	# Colisão
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(target_length * 0.78, maxf(24.0, crop.size.x * uniform_scale * 0.72))
	collision.shape = rectangle
	preload("res://systems/ContactShadow.gd").add_vehicle(self, Vector2(target_length * 1.04, maxf(28.0, crop.size.x * uniform_scale * 1.08)))
	var hit_shape := RectangleShape2D.new()
	hit_shape.size = Vector2(target_length * 1.05, maxf(34.0, crop.size.x * uniform_scale * 0.95))
	var pedestrian_collision := pedestrian_hitbox.get_node("Collision") as CollisionShape2D
	pedestrian_collision.shape = hit_shape
	pedestrian_hitbox.collision_mask = 5
	
	# Câmera dinâmica (desativada por padrão em carros de tráfego ambiente)
	var dyn_cam = load("res://systems/DynamicCamera.gd")
	if dyn_cam and camera:
		camera.set_script(dyn_cam)
		camera.enabled = false
		camera.set_process(false)
		camera.set_physics_process(false)
		
	# RayCasts anticolisão IA (detecta veículos, jogador e pedestres à frente)
	var front_ray := RayCast2D.new()
	front_ray.name = "FrontRay"
	front_ray.target_position = Vector2(maxf(95.0, target_length * 1.25), 0.0)
	front_ray.collision_mask = 15 # Camadas 1, 2, 4, 8: Veículos, Dante e Pedestres
	add_child(front_ray)
	
	var front_ray_l := RayCast2D.new()
	front_ray_l.name = "FrontRayL"
	front_ray_l.position = Vector2(target_length * 0.4, -18.0)
	front_ray_l.target_position = Vector2(maxf(80.0, target_length * 1.1), 0.0)
	front_ray_l.collision_mask = 15
	add_child(front_ray_l)
	
	var front_ray_r := RayCast2D.new()
	front_ray_r.name = "FrontRayR"
	front_ray_r.position = Vector2(target_length * 0.4, 18.0)
	front_ray_r.target_position = Vector2(maxf(80.0, target_length * 1.1), 0.0)
	front_ray_r.collision_mask = 15
	add_child(front_ray_r)
	
	# VFX e Audio sao instanciados sob demanda (lazy) para reduzir carga no renderer e audio server
	_setup_headlight()

func _ensure_camera() -> Camera2D:
	if camera == null:
		camera = get_node_or_null("Camera") as Camera2D
		if camera == null:
			camera = Camera2D.new()
			camera.name = "Camera"
			add_child(camera)
		var dyn_cam = load("res://systems/DynamicCamera.gd")
		if dyn_cam:
			camera.set_script(dyn_cam)
	return camera

func _ensure_smoke_emitter() -> CPUParticles2D:
	if smoke_emitter == null:
		smoke_emitter = CPUParticles2D.new()
		smoke_emitter.emitting = false
		smoke_emitter.amount = 20
		smoke_emitter.lifetime = 1.0
		smoke_emitter.gravity = Vector2(0, -98)
		smoke_emitter.texture = _soft_damage_particle()
		smoke_emitter.scale_amount_min = 10.0 / 32.0
		smoke_emitter.scale_amount_max = 22.0 / 32.0
		smoke_emitter.color = Color(0.2, 0.2, 0.2, 0.8)
		preload("res://guns/combat/VehicleDamageParticles.gd").configure(smoke_emitter, false)
		add_child(smoke_emitter)
	return smoke_emitter

func _ensure_collision_particles() -> CPUParticles2D:
	if collision_particles == null:
		collision_particles = CPUParticles2D.new()
		collision_particles.emitting = false
		collision_particles.one_shot = true
		collision_particles.local_coords = false
		collision_particles.amount = 10
		collision_particles.lifetime = 0.24
		collision_particles.initial_velocity_min = 40.0
		collision_particles.initial_velocity_max = 90.0
		collision_particles.gravity = Vector2.ZERO
		collision_particles.scale_amount_min = 1.5 / 64.0
		collision_particles.scale_amount_max = 3.5 / 64.0
		collision_particles.color = Color(1.0, 0.85, 0.35, 1.0)
		collision_particles.texture = preload("res://guns/combat/VehicleDamageParticles.gd").texture()
		add_child(collision_particles)
	return collision_particles

func _ensure_flame_particles() -> CPUParticles2D:
	if flame_particles == null:
		flame_particles = CPUParticles2D.new()
		flame_particles.emitting = false
		flame_particles.amount = 35
		flame_particles.lifetime = 0.5
		flame_particles.gravity = Vector2(0, -140)
		flame_particles.initial_velocity_min = 40.0
		flame_particles.initial_velocity_max = 90.0
		flame_particles.scale_amount_min = 4.0
		flame_particles.scale_amount_max = 8.0
		flame_particles.color = Color(1.0, 0.45, 0.1, 0.95)
		preload("res://guns/combat/VehicleDamageParticles.gd").configure(flame_particles, true)
		add_child(flame_particles)
	return flame_particles

func _ensure_puncture_vfx() -> void:
	if rim_sparks == null:
		rim_sparks = CPUParticles2D.new()
		rim_sparks.emitting = false
		rim_sparks.amount = 25
		rim_sparks.lifetime = 0.35
		rim_sparks.direction = Vector2(-1, 0)
		rim_sparks.spread = 45.0
		rim_sparks.initial_velocity_min = 60.0
		rim_sparks.initial_velocity_max = 140.0
		rim_sparks.color = Color(1.0, 0.8, 0.2, 0.9)
		add_child(rim_sparks)
	if flat_smoke == null:
		flat_smoke = CPUParticles2D.new()
		flat_smoke.emitting = false
		flat_smoke.amount = 20
		flat_smoke.lifetime = 0.5
		flat_smoke.gravity = Vector2(0, -60)
		flat_smoke.color = Color(0.2, 0.2, 0.2, 0.7)
		add_child(flat_smoke)

func _ensure_nos_purge() -> void:
	if nos_purge_l == null:
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
		add_child(nos_purge_l)
	if nos_purge_r == null:
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
		add_child(nos_purge_r)

func _ensure_backfire() -> CPUParticles2D:
	if backfire_emitter == null:
		backfire_emitter = CPUParticles2D.new()
		backfire_emitter.emitting = false
		backfire_emitter.one_shot = true
		backfire_emitter.amount = 15
		backfire_emitter.lifetime = 0.20
		backfire_emitter.direction = Vector2(-1, 0)
		backfire_emitter.spread = 25.0
		backfire_emitter.initial_velocity_min = 50.0
		backfire_emitter.initial_velocity_max = 110.0
		backfire_emitter.scale_amount_min = 3.0
		backfire_emitter.scale_amount_max = 7.0
		backfire_emitter.color = Color("#f39c12")
		add_child(backfire_emitter)
	return backfire_emitter

func _ensure_nitro() -> void:
	if nitro_audio == null:
		nitro_audio = AudioStreamPlayer2D.new()
		nitro_audio.stream = ProceduralAudio.get_nitro_stream()
		nitro_audio.max_distance = 550.0
		nitro_audio.volume_db = -10.0
		add_child(nitro_audio)
	if nitro_emitter == null:
		nitro_emitter = CPUParticles2D.new()
		nitro_emitter.emitting = false
		nitro_emitter.amount = 35
		nitro_emitter.lifetime = 0.30
		nitro_emitter.direction = Vector2(-1, 0)
		nitro_emitter.spread = 12.0
		nitro_emitter.gravity = Vector2.ZERO
		nitro_emitter.initial_velocity_min = 100.0
		nitro_emitter.initial_velocity_max = 190.0
		nitro_emitter.scale_amount_min = 2.5
		nitro_emitter.scale_amount_max = 6.0
		nitro_emitter.color = Color("#00cec9")
		add_child(nitro_emitter)

func _ensure_skid_line() -> Line2D:
	if skid_line == null:
		skid_line = Line2D.new()
		skid_line.width = 4.0
		skid_line.default_color = Color(0.1, 0.1, 0.1, 0.5)
		skid_line.top_level = true
		add_child(skid_line)
	return skid_line

func _ensure_horn_audio() -> AudioStreamPlayer2D:
	if horn_audio == null:
		horn_audio = AudioStreamPlayer2D.new()
		horn_audio.stream = ProceduralAudio.get_horn_stream()
		horn_audio.max_distance = 500.0
		horn_audio.volume_db = -20.0
		add_child(horn_audio)
	return horn_audio

func _ensure_siren_audio() -> AudioStreamPlayer2D:
	if siren_audio == null:
		siren_audio = AudioStreamPlayer2D.new()
		siren_audio.stream = ProceduralAudio.get_siren_stream()
		siren_audio.max_distance = 800.0
		siren_audio.volume_db = -4.0
		add_child(siren_audio)
	return siren_audio

func _ensure_alarm_audio() -> AudioStreamPlayer2D:
	if alarm_audio == null:
		alarm_audio = AudioStreamPlayer2D.new()
		alarm_audio.stream = ProceduralAudio.get_police_alarm_stream()
		alarm_audio.max_distance = 1000.0
		alarm_audio.volume_db = 2.0
		alarm_audio.bus = "SFX"
		add_child(alarm_audio)
	return alarm_audio

func _ensure_engine_audio() -> AudioStreamPlayer2D:
	if engine_audio == null:
		engine_audio = AudioStreamPlayer2D.new()
		engine_audio.bus = &"SFX"
		engine_audio.max_distance = 600.0
		engine_audio.attenuation = 1.8
		engine_audio.volume_db = -16.0
		add_child(engine_audio)
		# Familia e camadas do arquetipo, prontas antes do primeiro quadro ao volante.
		_engine_sound.bind(engine_audio, active_archetype_id)
	return engine_audio

func _ensure_skid_audio() -> AudioStreamPlayer2D:
	if skid_audio == null:
		skid_audio = AudioStreamPlayer2D.new()
		skid_audio.stream = ProceduralAudio.get_skid_stream()
		skid_audio.max_distance = 500.0
		skid_audio.volume_db = -16.0
		add_child(skid_audio)
	return skid_audio

func _ensure_radio_audio() -> AudioStreamPlayer2D:
	if radio_audio == null:
		radio_audio = AudioStreamPlayer2D.new()
		radio_audio.max_distance = 500.0
		radio_audio.volume_db = -18.0
		add_child(radio_audio)
		preload("res://audio/living_city/VehicleRadioReceiver.gd").attach(radio_audio)
		radio_tracks = ProceduralAudio.get_radio_stations()
	return radio_audio

var is_night_or_storm: bool = false

func _is_near_screen(margin: float = 260.0) -> bool:
	if not is_inside_tree():
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	var screen_pos := get_canvas_transform() * global_position
	return vp.get_visible_rect().grow(margin).has_point(screen_pos)

func _update_headlight_state() -> void:
	if headlight == null:
		return
	var on_screen := is_driven_by_player or _is_near_screen(260.0)
	var active := (is_night_or_storm or is_driven_by_player) and not is_broken and on_screen
	headlight.visible = active and (not is_instance_valid(body_model) or not body_model.broken_lamps[0])
	if second_headlight:
		second_headlight.visible = active and (not is_instance_valid(body_model) or not body_model.broken_lamps[1])

func set_headlights(dark_state: bool) -> void:
	is_night_or_storm = dark_state
	_update_headlight_state()

func _setup_headlight() -> void:
	if headlight != null:
		return
	headlight = PointLight2D.new()
	headlight.name = "Headlight"
	headlight.color = Color(1.0, 0.98, 0.90, 1.0)
	headlight.energy = 1.35
	headlight.shadow_enabled = false
	# Ground beams must pass beneath vehicle bodies (drawn at z = 8 or above).
	headlight.range_z_max = 7
	headlight.position = Vector2(target_length * 0.45, 0.0)
	headlight.texture = HeadlightTextureGenerator.get_conical_headlight_texture()
	headlight.offset = Vector2(170.0, 0.0) # Projeta 340px para a frente do carro
	headlight.visible = (is_night_or_storm or is_driven_by_player) and not is_broken and (is_driven_by_player or _is_near_screen(260.0))
	add_child(headlight)

func honk_horn():
	if is_broken: return
	preload("res://cars/traffic/TrafficHorn.gd").report(self)
	_ensure_horn_audio()
	if horn_audio and not horn_audio.playing:
		horn_audio.pitch_scale = randf_range(0.92, 1.08)
		horn_audio.play()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if is_exploded or amount <= 0: return
	health = maxi(0, health - amount)
	if health < 75:
		visual.modulate = visual.modulate.lerp(Color(0.65, 0.65, 0.65), 0.4)
	if health < 50:
		_ensure_smoke_emitter()
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.5, 0.5, 0.5, 0.8)
	if health <= 25:
		visual.modulate = Color(0.3, 0.3, 0.3)
		if smoke_emitter:
			smoke_emitter.color = Color(0.65, 0.65, 0.68, 0.85)
			smoke_emitter.amount = 20
	if health == 0 and not is_broken:
		set_meta("explosion_player_caused", _is_player_attacker)
		is_broken = true
		if max_speed > 0.0: set_meta("speed_before_destruction",max_speed)
		max_speed = 0.0
		if engine_audio: engine_audio.stop()
		_engine_sound.stop()
		_start_combustion_countdown()
		_dispatch_fire_truck()

var is_exploding: bool = false
var is_exploded: bool = false
var _combustion_epoch := 0

func _start_combustion_countdown() -> void:
	if is_exploding or is_exploded: return
	set_meta("service_complete", false)
	_combustion_epoch += 1
	var epoch := _combustion_epoch
	is_exploding = true
	_ensure_flame_particles()
	if flame_particles: flame_particles.emitting = true
	_ensure_smoke_emitter()
	if smoke_emitter:
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.65, 0.65, 0.68, 0.85)
		smoke_emitter.amount = 20
	# O jogador NÃO é ejetado sumariamente aqui: ele tem 3.2s para reagir e pular com F/Enter!
		
	await get_tree().create_timer(3.2).timeout
	if epoch == _combustion_epoch and is_exploding and not is_exploded and health <= 0:
		_explode()

func _explode() -> void:
	if is_exploded: return
	is_exploded = true
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	if headlight: headlight.visible = false
	if second_headlight: second_headlight.visible = false
	
	# Se o jogador ainda estiver no veículo na detonação final, ele é ejetado e toma o dano da explosão
	if is_driven_by_player:
		var driver_ref = _driver
		force_exit_vehicle()
		if is_instance_valid(driver_ref) and driver_ref.has_method("take_damage"):
			driver_ref.take_damage(100) # Dano crítico de explosão
	
	if get_parent() is PathFollow2D:
		_detached_from_lane = true
	
	# 1. Som de explosão estrondoso
	var p = AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_explosion_stream()
	p.volume_db = 2.0
	p.max_distance = 1200.0
	get_parent().add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)
	
	preload("res://guns/combat/ExplosionVisual.gd").spawn(get_parent(), global_position, 180.0, true)
	
	# 6. Carcaça queimada estável no solo (sem salto no ar, sem teleporte, sem deformação)
	if visual:
		visual.modulate = Color(0.12, 0.12, 0.12)
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.position = Vector2.ZERO
		visual.skew = 0.0
	if is_3d_vehicle and is_instance_valid(body_model):
		body_model.char_body()
		visual.modulate = Color.WHITE
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# 7. Screen Shake
	if is_driven_by_player:
		_do_screen_shake(0.70)
		
	# 8. Onda de choque
	preload("res://guns/combat/VehicleBlast.gd").apply(self)
	preload("res://emergency/VehicleResidualFire.gd").start(self)
	_start_decay()

var _fire_truck_dispatched: bool = false

func _dispatch_fire_truck():
	if _fire_truck_dispatched:
		return
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	var dist_player := global_position.distance_to(player.global_position)
	# Ignora pequenos acidentes de fundo longe da visão do jogador
	if not is_driven_by_player and dist_player > 550.0:
		return
		
	var depot_director = get_tree().get_first_node_in_group("emergency_depot_director")
	if depot_director and depot_director.has_method("request_dispatch"):
		var dispatched = depot_director.request_dispatch("fire", self, false)
		_fire_truck_dispatched = dispatched != null
		return

func extinguish_fire() -> void:
	if get_meta("service_complete", false): return
	set_meta("service_complete", true)
	_combustion_epoch += 1
	_fire_truck_dispatched = false
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	if smoke_emitter:
		smoke_emitter.color = Color(0.9, 0.9, 0.9, 0.5)
		smoke_emitter.amount = 20
	# WorldRenewal owns the bounded fade and reuses this fleet slot.

func _start_decay():
	# Also handles wrecks restored from saves and sleeping lanes.
	pass

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

func receive_bullet_impact(direction: Vector2, amount: int) -> void:
	if not is_motorcycle or amount <= 0 or is_exploded or _rider_fallen: return
	var incoming := global_transform.x * maxf(_lane_motion_speed, velocity.length()) + direction.normalized() * clampf(amount * 5.0, 100.0, 280.0)
	if incoming.length() < 100.0: incoming = direction.normalized() * 100.0
	if is_driven_by_player:
		_rider_fallen = true
		_finish_player_bullet_fall.call_deferred(incoming)
	elif not _detached_from_lane:
		receive_vehicle_impact(incoming.length(), incoming.normalized())
	else:
		_rider_fallen = true
		ensure_presentation()
		if is_instance_valid(body_model):
			body_model.set_meta("fallen_motorcycle", true)
			create_tween().tween_property(body_model, "rotation:z", 1.25, 0.35)

func _finish_player_bullet_fall(incoming: Vector2) -> void:
	var rider := _driver
	force_exit_vehicle()
	if is_instance_valid(rider) and rider.has_method("get_run_over"):
		rider.get_run_over(incoming.limit_length(280.0))
	if is_instance_valid(body_model):
		body_model.set_meta("fallen_motorcycle", true)
		create_tween().tween_property(body_model, "rotation:z", 1.25, 0.35)

func receive_vehicle_impact(force: float, direction: Vector2) -> void:
	if not is_motorcycle or _rider_fallen or _detached_from_lane or is_driven_by_player:
		return
	if not is_finite(force) or force < 65.0 or not direction.is_finite(): return
	_rider_fallen = true
	_finish_rider_fall.call_deferred(direction.normalized(), force)

func _finish_rider_fall(direction: Vector2, force: float) -> void:
	if is_driven_by_player or _detached_from_lane:
		_rider_fallen = false
		return
	var scene := get_tree().current_scene
	if scene == null: scene = get_parent().get_parent()
	ensure_presentation()
	var fallen := preload("res://characters/CarjackedDriver.tscn").instantiate() as CarjackedDriver
	scene.add_child(fallen)
	fallen.global_position = global_position
	fallen.global_rotation = global_rotation
	fallen.fall_from_motorcycle(self, direction, force)
	reparent(scene, true)
	# A traffic crash does not arm a parked theft alarm on the dropped bike.
	_parked_security_configured = true
	has_theft_alarm = false
	configure_as_parked()
	set_process(true)
	velocity = direction * clampf(force * 0.12, 8.0, 42.0)
	if is_instance_valid(body_model):
		body_model.set_meta("fallen_motorcycle", true)
		var fall := create_tween()
		fall.tween_property(body_model, "rotation:z", 1.25, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_apply_crash_deformation(-direction, maxf(80.0, force), global_position)

func _apply_crash_deformation(impact_normal: Vector2, impact_force: float, hit_world_pos: Vector2 = Vector2.ZERO, is_post: bool = false) -> void:
	receive_vehicle_impact(impact_force, -impact_normal)
	if visual == null or impact_force < (40.0 if is_post else 80.0) or not hit_world_pos.is_finite(): return
	ensure_presentation()
	var now := Time.get_ticks_msec()
	if now - _last_crash_visual_ms < (350 if is_post else 500): return
	_last_crash_visual_ms = now
	# Poste tem efeito próprio (spawn_post_impact), disparado na colisão.
	if not is_post: preload("res://guns/combat/WeaponEffects.gd").spawn_crash(get_parent(), hit_world_pos, impact_normal, impact_force)
	# The native vehicle receives a bounded dent in its own mesh. Flat decals
	# cannot follow its projected sides and must never be layered on top.
	if is_3d_vehicle and is_instance_valid(body_model):
		var ppm := 74.0 / 4.46
		var hit := to_local(hit_world_pos) / ppm
		var inward := global_transform.basis_xform_inv(impact_normal)
		body_model.apply_impact(Vector3(hit.y,0.81,-hit.x),Vector3(inward.y,0,-inward.x),(impact_force * 0.5 if is_post else impact_force)/ppm)
		_update_headlight_state()
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif not is_post:
		_ensure_dents_container()
		_spawn_dent_decal(to_local(hit_world_pos),global_transform.basis_xform_inv(impact_normal),clampf(impact_force/420.0,0,1))
	visual.modulate = visual.modulate.lerp(Color(0.80,0.80,0.81),0.08)
	var crumple_player := AudioStreamPlayer2D.new()
	crumple_player.stream = ProceduralAudio.get_metal_crumple_stream()
	crumple_player.volume_db = -20.0 if is_post else -15.0
	crumple_player.bus = &"SFX"
	crumple_player.max_distance = 500.0
	add_child(crumple_player)
	crumple_player.play()
	crumple_player.finished.connect(crumple_player.queue_free)

func _spawn_dent_decal(local_pos: Vector2, dir: Vector2, strength: float) -> void:
	if dents_container == null or is_3d_vehicle: return
	var footprint := Vector2(54,24)
	if collision and collision.shape is RectangleShape2D: footprint = collision.shape.size
	preload("res://cars/VehicleSurfaceWear2D.gd").add_scrape(dents_container,local_pos,dir,footprint,strength)

func _clear_all_dents() -> void:
	if is_3d_vehicle and is_instance_valid(body_model):
		body_model.repair()
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if dents_container:
		for child in dents_container.get_children():
			child.queue_free()

func _spawn_flying_debris(pos: Vector2, normal: Vector2) -> void:
	var debris_emitter := CPUParticles2D.new()
	debris_emitter.global_position = pos
	debris_emitter.emitting = true
	debris_emitter.one_shot = true
	debris_emitter.explosiveness = 0.95
	debris_emitter.amount = 16
	debris_emitter.lifetime = 0.75
	debris_emitter.direction = normal
	debris_emitter.spread = 65.0
	debris_emitter.initial_velocity_min = 80.0
	debris_emitter.initial_velocity_max = 200.0
	debris_emitter.gravity = Vector2(0, 220)
	debris_emitter.scale_amount_min = 2.0
	debris_emitter.scale_amount_max = 4.0
	debris_emitter.color = Color(0.85, 0.85, 0.9, 0.9)
	get_parent().add_child(debris_emitter)
	var t = debris_emitter.create_tween()
	t.tween_interval(1.2)
	t.tween_callback(debris_emitter.queue_free)

@export var vehicle_mass: float = 1.0
@export var max_health: int = 100
var active_archetype_id: String = "sedan_classic"
var active_roof_prop_node: Node2D = null

func apply_archetype(archetype_id: String, custom_color: Color = Color.TRANSPARENT) -> void:
	_pending_spec = {}
	active_archetype_id = archetype_id
	if collision: collision.position = Vector2.ZERO
	preload("res://emergency/VehicleWaterCannon.gd").sync_vehicle(self, archetype_id == "rescue_pumper")
	var spec: Dictionary = VehicleCatalog.get_vehicle_spec(archetype_id)
	if spec.is_empty(): return
	is_motorcycle = spec.get("vehicle_kind", "car") == "motorcycle"
	set_meta("vehicle_kind", "motorcycle" if is_motorcycle else "car")
	if is_motorcycle: add_to_group("motorcycle")
	else: remove_from_group("motorcycle")
	
	vehicle_id = archetype_id
	display_name = spec.get("label", "Veículo")
	target_length = float(spec.get("target_length", 76.0))
	preload("res://systems/ContactShadow.gd").add_vehicle(self, Vector2(target_length * 1.04, float(spec.get("target_width",34.0)) * 1.08))
	vehicle_mass = float(spec.get("mass", 1.0))
	max_speed = float(spec.get("max_speed", 490.0))
	acceleration = float(spec.get("acceleration", 880.0))
	braking = float(spec.get("braking", 1150.0))
	turn_speed = float(spec.get("turn_speed", 3.1))
	drift_factor = float(spec.get("drift_factor", 0.88))
	max_health = int(spec.get("durability", 100))
	health = max_health
	for ray_name in ["FrontRayL", "FrontRayR"]:
		var ray := get_node_or_null(ray_name) as RayCast2D
		if ray:
			var half_width := float(spec.get("target_width",34))*.45 if is_motorcycle else 18.0
			ray.position = Vector2(target_length*.4, half_width * (-1 if ray_name == "FrontRayL" else 1))
	if engine_audio:
		engine_audio.stop()
		_engine_sound.stop()
		_engine_sound.bind(engine_audio, active_archetype_id)
	
	is_police_vehicle = String(spec.get("roof_prop", "")) == "police_lightbar"
	# Cor e Textura Especial
	if spec.has("model_class") and String(spec["model_class"]) != "":
		if defer_presentation and body_viewport == null:
			_pending_spec = spec.duplicate(true)
			_pending_color = VehicleCatalog.get_random_color(archetype_id) if custom_color == Color.TRANSPARENT else custom_color
			visual.modulate = _pending_color
			if is_motorcycle:
				visual.texture = preload("res://cars/motorcycles/MotorcycleSilhouette.gd").texture()
				visual.region_enabled = false
				visual.rotation = 0.0
				visual.scale = Vector2.ONE * target_length / 64.0
			else:
				var placeholder := AtlasTexture.new()
				placeholder.atlas = VEHICLE_ATLAS
				placeholder.region = VehicleCatalog.VEHICLE_CROPS[posmod(int(spec.get("crop_index",0)),VehicleCatalog.VEHICLE_CROPS.size())]
				visual.texture = placeholder
				visual.rotation = PI*.5
				visual.scale = Vector2.ONE * target_length / maxf(1.0,placeholder.region.size.y)
			# O tamanho físico independe do momento em que a câmera solicita detalhe.
			var length := float(spec.get("target_length", 82.0))
			var width := float(spec.get("target_width", 34.0))
			var shape := RectangleShape2D.new()
			shape.size = Vector2(length * 0.82, maxf(10.0 if is_motorcycle else 28.0, width * 0.88))
			collision.shape = shape
			var hit := pedestrian_hitbox.get_node("Collision") as CollisionShape2D
			(hit.shape as RectangleShape2D).size = Vector2(length * 1.02, maxf(12.0 if is_motorcycle else 34.0, width * 1.02))
			get_node("/root/PresentationBudget").request(self)
		else:
			_setup_3d_model(spec, custom_color)
	elif spec.has("texture") and String(spec["texture"]) != "":
		visual.texture = load(spec["texture"])
		visual.region_enabled = false
		visual.centered = true
		visual.rotation = PI * 0.5
		uniform_scale = target_length / 480.0
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.modulate = Color.WHITE
		if archetype_id == "police_cruiser":
			is_police_vehicle = true
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = Vector2(target_length * 0.78, 34.0)
		if collision: collision.shape = rect_shape
	else:
		if spec.has("crop_index"):
			var c_idx: int = int(spec["crop_index"])
			crop = VehicleCatalog.VEHICLE_CROPS[posmod(c_idx, VehicleCatalog.VEHICLE_CROPS.size())]
			if visual and visual.texture is AtlasTexture:
				(visual.texture as AtlasTexture).region = crop

		var chosen_color: Color
		if custom_color != Color.TRANSPARENT:
			chosen_color = custom_color
		else:
			chosen_color = VehicleCatalog.get_random_color(archetype_id)
		
		if visual:
			visual.modulate = chosen_color
			uniform_scale = target_length / maxf(1.0, crop.size.y)
			visual.scale = Vector2(uniform_scale, uniform_scale)
		
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = Vector2(target_length * 0.78, maxf(24.0, crop.size.x * uniform_scale * 0.72))
		if collision: collision.shape = rect_shape
	
	# Atualiza adereços no teto/lataria (props)
	_build_roof_prop(String(spec.get("roof_prop", "none")))
	preload("res://world/harbor/ForkliftLift.gd").sync_vehicle(self, archetype_id == "port_forklift")

func _setup_3d_model(spec: Dictionary, custom_color: Color = Color.TRANSPARENT) -> void:
	is_3d_vehicle = true
	var model_path: String = String(spec.get("model_class", ""))
	var model_res = load(model_path)
	if not model_res:
		return
	# Recycled vehicles must rebuild when their authored class changes.
	if body_model != null and body_model.get_script() != model_res:
		body_viewport.free()
		body_viewport = null
		body_model = null
		wheel_rig = preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		wheels = []
		spinners = []
		_lamp_mounts.clear()
		_side_doors.clear()
		_door_3d = null
		if second_headlight: second_headlight.free()
		second_headlight = null
		_body_render_visible = false

	var t_len: float = float(spec.get("target_length", 82.0))
	var t_wid: float = float(spec.get("target_width", 34.0))
	var ppm: float = 74.0 / 4.46
	# Bikes occupied less than half of the car framing. Fit their silhouette
	# into the same render target, preserving world size via uniform_scale.
	var cam_size: float = maxf(3.8 if is_motorcycle else 6.0, (t_len / ppm) * 1.25)
	var v_size := 192
	if t_len > 100.0:
		v_size = 256

	if body_viewport == null:
		body_viewport = SubViewport.new()
		body_viewport.name = "Vehicle3DRender"
		body_viewport.size = Vector2i(v_size, v_size)
		body_viewport.transparent_bg = true
		body_viewport.own_world_3d = true
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(body_viewport)

		body_model = model_res.new() as Node3D
		body_viewport.add_child(body_model)

		# Use actual authored wheel hubs, not approximate dimensions from the catalog.
		wheel_rig.mount(body_model)
		wheels = wheel_rig.pivots
		spinners = wheel_rig.spinners

		var lens := body_model.materials.get("headlight") as Material
		for mesh in body_model.get_children():
			if mesh is MeshInstance3D and mesh.material_override == lens and lens != null:
				_lamp_mounts.append(mesh.position)
		_lamp_mounts.sort_custom(func(a: Vector3,b: Vector3): return a.x < b.x)
		if _lamp_mounts.size() >= 2:
			_lamp_mounts = [_lamp_mounts[0], _lamp_mounts[-1]]
			second_headlight = headlight.duplicate()
			second_headlight.name = "RightHeadlight"
			add_child(second_headlight)
		for light in [headlight,second_headlight]:
			if light != null:
				light.offset = Vector2(100,0)
				light.texture_scale = 0.6
				light.energy = 0.75
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(body_model)
		body_model.rotation.y = -PI * 0.5

		var view := Camera3D.new()
		view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		body_viewport.add_child(view)
		view.position = Vector3(0, 8, 4)
		view.look_at(Vector3(0, 0.45, 0))
		view.projection = Camera3D.PROJECTION_ORTHOGONAL
		view.size = cam_size

		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.7
		body_viewport.add_child(environment)

		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, -30, 0)
		sun.light_energy = 1.0
		body_viewport.add_child(sun)
	else:
		body_viewport.size = Vector2i(v_size, v_size)

	var chosen_color: Color = custom_color
	if chosen_color == Color.TRANSPARENT:
		chosen_color = VehicleCatalog.get_random_color(active_archetype_id)
	if body_model and "paint" in body_model and body_model.paint:
		body_model.paint.albedo_color = chosen_color
	refresh_motorcycle_rider()
	lightbar_3d.bind(body_model)
	if is_police_vehicle and active_roof_prop_node and not lightbar_3d.lamps.is_empty():
		active_roof_prop_node.hide()

	if visual:
		visual.texture = body_viewport.get_texture()
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if is_motorcycle else CanvasItem.TEXTURE_FILTER_PARENT_NODE
		visual.region_enabled = false
		visual.centered = true
		var ground_camera := body_viewport.get_camera_3d()
		ground_camera.force_update_transform()
		visual.offset = Vector2(body_viewport.size) * .5 - ground_camera.unproject_position(Vector3.ZERO)
		uniform_scale = ppm * cam_size / float(v_size)
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.rotation = 0.0
		visual.modulate = Color.WHITE
		preload("res://systems/ContactShadow.gd").add_vehicle(self, Vector2(t_len, t_wid))

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(t_len * 0.82, maxf(10.0 if is_motorcycle else 28.0, t_wid * 0.88))
	if collision: collision.shape = rect_shape
	if pedestrian_hitbox and pedestrian_hitbox.has_node("Collision"):
		var p_col = pedestrian_hitbox.get_node("Collision") as CollisionShape2D
		if p_col and p_col.shape is RectangleShape2D:
			(p_col.shape as RectangleShape2D).size = Vector2(t_len * 1.02, maxf(12.0 if is_motorcycle else 34.0, t_wid * 1.02))
	var lift := get_node_or_null("ForkliftLift")
	if lift and active_archetype_id == "port_forklift": lift.configure_hull()

func refresh_motorcycle_rider() -> void:
	if not is_motorcycle or not is_instance_valid(body_model): return
	if is_driven_by_player: _rider_fallen = false
	var occupied := (is_driven_by_player or not _detached_from_lane) and not has_meta("vehicle_boarding") and not is_exploded
	if is_driven_by_player and is_instance_valid(_driver): body_model.set_dante_rider(_driver)
	body_model.set_rider_state(occupied, is_driven_by_player)
	_body_render_visible = false
	body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

var _body_render_clock := 0.0
var _body_render_visible := false
var body_render_requests := 0
var _last_render_heading := INF
var _last_render_steer := INF

func _update_3d_orientation(delta: float) -> void:
	if not is_3d_vehicle or body_model == null:
		return
	if has_meta("interior_vehicle_presentation"):
		wheel_rig.update(delta,velocity.dot(global_transform.x)/22.0,global_rotation)
		get_meta("interior_vehicle_presentation").sync()
		return
	# Every car has its own 3D world. Submit only visible cars, while leaving
	# lane simulation and physical collisions running outside the camera.
	var screen_position := get_canvas_transform() * global_position
	var visible_now := is_visible_in_tree() and get_viewport().get_visible_rect().grow(140).has_point(screen_position)
	_body_render_clock += delta
	if not visible_now:
		body_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_body_render_visible = false
		if not is_driven_by_player:
			if headlight and headlight.visible: headlight.visible = false
			if second_headlight and second_headlight.visible: second_headlight.visible = false
		return
	body_model.rotation.y = -global_rotation - PI * 0.5
	if visual:
		visual.global_rotation = 0.0
		preload("res://world/harbor/urban_transit/UrbanVehicleDepth.gd").update(self, visual)
	if not is_driven_by_player and is_night_or_storm and not is_broken:
		if headlight and not headlight.visible: headlight.visible = true
		if second_headlight and not second_headlight.visible: second_headlight.visible = true
	if headlight != null and not _lamp_mounts.is_empty():
		var view := body_viewport.get_camera_3d()
		if view:
			for i in mini(2, _lamp_mounts.size()):
				var light: PointLight2D = headlight if i == 0 else second_headlight
				var pixel := view.unproject_position(body_model.to_global(_lamp_mounts[i]))
				light.global_position = visual.to_global(pixel-Vector2(body_viewport.size)*0.5)
		var lamps_active := (is_night_or_storm or is_driven_by_player) and not is_broken and not is_exploded
		headlight.visible = lamps_active and not body_model.broken_lamps[0]
		if second_headlight: second_headlight.visible = lamps_active and not body_model.broken_lamps[1]
	var signed_speed := velocity.dot(global_transform.x) if is_driven_by_player else (_lane_motion_speed if is_moving_on_lane else 0.0)
	var ppm := 74.0 / 4.46
	# Nem a faixa nem o jogador ao volante deste carro passam por um ângulo de
	# esterço: os dois giram `rotation` direto. O ângulo das rodas dianteiras sai
	# então da guinada real da carroceria, pelo modelo de bicicleta invertido.
	wheel_rig.update(delta, signed_speed / ppm, global_rotation)
	var rider_moved := false
	if is_motorcycle:
		rider_moved = body_model.update_riding_pose(delta, signed_speed / ppm, wheel_rig.steering_angle, body_model.rider.visible)
	var interval := 1.0 / (60.0 if is_driven_by_player else 30.0)
	var steer_moved := absf(wheel_rig.steering_angle - _last_render_steer) > 0.004
	var beacon_changed := lightbar_3d.update((is_siren_on or is_alarm_active) and not is_broken and not is_exploded, Time.get_ticks_msec())
	var moving_pose := absf(signed_speed)>0.1 or steer_moved or rider_moved or not is_equal_approx(_last_render_heading,global_rotation)
	if not _body_render_visible or beacon_changed or (moving_pose and _body_render_clock >= interval):
		_body_render_clock = fmod(_body_render_clock, interval)
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		body_render_requests += 1
		_last_render_heading = global_rotation
		_last_render_steer = wheel_rig.steering_angle
	_body_render_visible = true


static var _cached_particle_tex: Texture2D = null
static func _get_smooth_particle_texture() -> Texture2D:
	if _cached_particle_tex != null:
		return _cached_particle_tex
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(0.5, 0.0)
	grad_tex.width = 64
	grad_tex.height = 64
	_cached_particle_tex = grad_tex
	return _cached_particle_tex

func _build_roof_prop(prop_type: String) -> void:
	if active_roof_prop_node and is_instance_valid(active_roof_prop_node):
		active_roof_prop_node.queue_free()
		active_roof_prop_node = null
		
	if prop_type == "none": return
	if prop_type == "taxi_sign" and is_3d_vehicle: return
	if prop_type == "police_lightbar" and is_3d_vehicle and not lightbar_3d.lamps.is_empty(): return
	
	active_roof_prop_node = Node2D.new()
	active_roof_prop_node.name = "RoofProp"
	active_roof_prop_node.z_index = 11
	add_child(active_roof_prop_node)
	
	match prop_type:
		"taxi_sign":
			var sign_rect = Polygon2D.new()
			sign_rect.color = Color(1.0, 0.85, 0.1)
			sign_rect.polygon = PackedVector2Array([
				Vector2(-8, -4), Vector2(8, -4), Vector2(6, 4), Vector2(-6, 4)
			])
			active_roof_prop_node.add_child(sign_rect)
			var light = PointLight2D.new()
			light.color = Color(1.0, 0.9, 0.3, 0.8)
			light.energy = 0.6
			light.texture = _get_smooth_particle_texture()
			light.texture_scale = 0.25
			active_roof_prop_node.add_child(light)
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
		"plow_blade":
			var blade = Polygon2D.new()
			blade.color = Color(0.25, 0.25, 0.28)
			blade.polygon = PackedVector2Array([
				Vector2(target_length * 0.45, -20), Vector2(target_length * 0.52, -10),
				Vector2(target_length * 0.52, 10), Vector2(target_length * 0.45, 20)
			])
			active_roof_prop_node.add_child(blade)
		"surfboard":
			var surf = Polygon2D.new()
			surf.color = Color(0.95, 0.35, 0.2)
			surf.polygon = PackedVector2Array([
				Vector2(-20, -5), Vector2(20, -2), Vector2(24, 0), Vector2(20, 2), Vector2(-20, 5)
			])
			surf.rotation = 0.12
			active_roof_prop_node.add_child(surf)
		"ski_rack":
			var rack = Line2D.new()
			rack.width = 2.5
			rack.default_color = Color(0.2, 0.2, 0.25)
			rack.points = PackedVector2Array([
				Vector2(-14, -10), Vector2(14, -10), Vector2(14, 10), Vector2(-14, 10)
			])
			active_roof_prop_node.add_child(rack)
		"roll_cage":
			var cage = Line2D.new()
			cage.width = 3.0
			cage.default_color = Color(0.85, 0.85, 0.9)
			cage.points = PackedVector2Array([
				Vector2(-12, -11), Vector2(12, -11), Vector2(12, 11), Vector2(-12, 11), Vector2(-12, -11)
			])
			active_roof_prop_node.add_child(cage)
		"exhaust_stacks":
			for side in [-1, 1]:
				var stack = Polygon2D.new()
				stack.color = Color(0.7, 0.72, 0.75)
				stack.polygon = PackedVector2Array([
					Vector2(-6, side * 14), Vector2(2, side * 14), Vector2(2, side * 18), Vector2(-6, side * 18)
				])
				active_roof_prop_node.add_child(stack)
		"police_lightbar":
			# Base metálica do giroflex
			var bar_base = Polygon2D.new()
			bar_base.name = "BarBase"
			bar_base.color = Color(0.12, 0.12, 0.15)
			bar_base.polygon = PackedVector2Array([
				Vector2(-4, -15), Vector2(4, -15), Vector2(4, 15), Vector2(-4, 15)
			])
			active_roof_prop_node.add_child(bar_base)
			
			# Luz Azul (Lado Esquerdo / Motorista)
			var blue_light = Polygon2D.new()
			blue_light.name = "LightBlue"
			blue_light.color = Color(0.15, 0.45, 1.0, 0.95)
			blue_light.polygon = PackedVector2Array([
				Vector2(-3, -14), Vector2(3, -14), Vector2(3, -2), Vector2(-3, -2)
			])
			active_roof_prop_node.add_child(blue_light)
			
			# Luz Vermelha (Lado Direito / Passageiro)
			var red_light = Polygon2D.new()
			red_light.name = "LightRed"
			red_light.color = Color(1.0, 0.15, 0.15, 0.95)
			red_light.polygon = PackedVector2Array([
				Vector2(-3, 2), Vector2(3, 2), Vector2(3, 14), Vector2(-3, 14)
			])
			active_roof_prop_node.add_child(red_light)
			
			# Halo / Brilho Dinâmico
			var halo = PointLight2D.new()
			halo.name = "SirenHalo"
			halo.color = Color(0.2, 0.5, 1.0, 0.9)
			halo.energy = 0.0 # Começa apagado até ligar alarme ou sirene
			halo.texture = _get_smooth_particle_texture()
			halo.texture_scale = 0.65
			active_roof_prop_node.add_child(halo)

func repaint_vehicle(new_color: Color = Color.TRANSPARENT) -> void:
	var color := VehicleCatalog.get_random_color(active_archetype_id) if new_color == Color.TRANSPARENT else new_color
	_pending_color = color
	if is_3d_vehicle and is_instance_valid(body_model) and body_model.get("paint") != null:
		body_model.paint.albedo_color = color
		if visual: visual.modulate = Color.WHITE
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif visual:
		visual.modulate = color

func repair_and_repaint(new_color: Color = Color.TRANSPARENT) -> void:
	repair_vehicle()
	repaint_vehicle(new_color)

func repair_vehicle() -> void:
	_launch.reset()
	_tire_trail.reset()
	remove_meta("service_complete")
	remove_meta("fire_response_assigned")
	_combustion_epoch += 1
	health = max_health
	if max_speed <= 0.0:
		max_speed = float(get_meta("speed_before_destruction",VehicleCatalog.get_vehicle_spec(active_archetype_id).get("max_speed",490.0)))
	is_broken = false
	is_exploded = false
	is_exploding = false
	_fire_truck_dispatched = false
	_clear_all_dents()
	bloody_tires_timer = 0.0
	is_skidding = false
	if skid_line:
		skid_line.clear_points()
		skid_line.default_color = Color(0.1,0.1,0.1,0.5)
	damage_deformation_scale = Vector2(1.0, 1.0)
	damage_deformation_offset = Vector2.ZERO
	damage_skew = 0.0
	if visual:
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.position = Vector2.ZERO
		visual.skew = 0.0
	if smoke_emitter:
		smoke_emitter.emitting = false
		smoke_emitter.amount = 20
	if flame_particles:
		flame_particles.emitting = false
	if rim_sparks:
		rim_sparks.emitting = false
	if flat_smoke:
		flat_smoke.emitting = false
	has_punctured_tires = false
	if visual: visual.modulate = Color.WHITE if is_3d_vehicle else _pending_color
	_update_headlight_state()

func configure_as_parked() -> void:
	## A parked catalog vehicle keeps the current art, damage and enter/drive
	## systems, but has no imaginary driver and never searches for a PathFollow.
	_detached_from_lane = true
	is_driven_by_player = false
	is_moving_on_lane = false
	_lane_motion_speed = 0.0
	speed = 0.0
	velocity = Vector2.ZERO
	set_process(false)
	if camera:
		camera.enabled = false
		camera.set_process(false)
		camera.set_physics_process(false)
	add_to_group("parked_vehicle")
	if not _parked_security_configured:
		# Stable selection across region streaming; applies to cars and motorcycles.
		var security_key := "%s:%s:%s" % [name, position, active_archetype_id]
		has_theft_alarm = is_police_vehicle or posmod(security_key.hash(), 100) < 35
		_parked_security_configured = true
	refresh_motorcycle_rider()
	if engine_audio: engine_audio.stop()
	_engine_sound.stop()

var _entry_input_released := true
var _drive_input_armed := true
var _siren_key_down := false

func enter_vehicle(player_body: CharacterBody2D) -> void:
	_enter_vehicle_with_role(player_body)

func _enter_vehicle_with_role(player_body: CharacterBody2D, as_taxi_passenger := false, steal_taxi := false) -> void:
	if has_meta("forklift_carried"): return
	ensure_presentation()
	if is_broken or is_driven_by_player or player_body == null:
		return
	if not is_visible_in_tree() or player_body.get("is_control_disabled") == true:
		return
	var taxi_occupied: bool = active_archetype_id == "taxi_yellow" and (not _detached_from_lane or (is_instance_valid(_taxi_service) and _taxi_service.driver_available))
	if taxi_occupied and not as_taxi_passenger and not steal_taxi:
		if not is_instance_valid(_taxi_service):
			_taxi_service = preload("res://cars/traffic/TaxiService.gd").new()
			add_child(_taxi_service)
		_taxi_service.offer(self,player_body)
		return
	if as_taxi_passenger and (not taxi_occupied or not is_instance_valid(_taxi_service)): return
	taxi_passenger = as_taxi_passenger
	if is_police_vehicle and _detached_from_lane and not was_stolen_from_police and not _police_lock_unlocked:
		_begin_vehicle_lockpick(player_body)
		return
		
	# Capture security state before ejection/boarding can detach or hide a rider.
	var theft_from_traffic := not _detached_from_lane or velocity.length() > 8.0 or _lane_motion_speed > 8.0
	# Ejeção dinâmica do motorista anterior se o carro estava em trânsito
	var was_occupied: bool = not _detached_from_lane or taxi_occupied
	if get_meta("service_crew_owned", false): was_occupied = false
	if is_motorcycle:
		was_occupied = was_occupied and not _rider_fallen and is_instance_valid(body_model) and is_instance_valid(body_model.rider) and body_model.rider.visible
	if was_occupied and not taxi_passenger:
		var driver_scene = load("res://characters/CarjackedDriver.tscn")
		if driver_scene:
			var ejected_driver = driver_scene.instantiate() as CarjackedDriver
			var scene_target = get_tree().current_scene if get_tree().current_scene else get_parent()
			if scene_target:
				scene_target.add_child(ejected_driver)
				var exit_side := -1.0 if to_local(_get_safe_exit_position()).y <= 0 else 1.0
				_animate_car_door(exit_side)
				var ejection_pos := preload("res://cars/VehicleBoarding.gd").driver_exit_position(self, ejected_driver, exit_side)
				if not ejection_pos.is_finite():
					# Sem vão livre para o motorista sair (ônibus encostado na plataforma,
					# carro contra parede): não o jogamos dentro de um sólido, mas o roubo
					# continua. Cancelar aqui deixava o veículo impossível de roubar.
					ejected_driver.queue_free()
				else:
					ejected_driver.setup(self, ejection_pos)
		if taxi_occupied and is_instance_valid(_taxi_service):
			_taxi_service.driver_available = false
	if active_archetype_id == "taxi_yellow" and is_instance_valid(body_model):
		var cab_driver := body_model.get_node_or_null("TaxiDriver")
		if cab_driver != null: cab_driver.visible = taxi_passenger

	_driver = player_body
	var approach := player_body.global_position
	var entry_side := -1.0 if to_local(approach).y <= 0 else 1.0
	if taxi_passenger: entry_side = 1.0
	var camera_view := preload("res://systems/DynamicCamera.gd").capture_view(get_viewport())
	is_driven_by_player = true
	player_entered.emit(self)
	# A vehicle taken by the player remains parked when they walk away or
	# enter an interior. Only untouched ambient wrecks use abandoned cleanup.
	if not taxi_passenger:
		add_to_group("parked_vehicle")
		_abandoned_timer = 0.0
	_entry_input_released = false
	_drive_input_armed = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").is_zero_approx()
	add_collision_exception_with(player_body)
	player_body.add_collision_exception_with(self)
	_remote_lane_elapsed = 0.0
	_lane_motion_speed = 0.0
	_hit_stop_frames = 0
	is_skidding = false
	is_boosting = false
	if skid_line: skid_line.clear_points()
	velocity = Vector2.ZERO
	speed = 0.0
	
	# Desativa colisões do jogador para evitar impulsos violentos
	for col in player_body.find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", true)
	player_body.velocity = Vector2.ZERO
	player_body.global_position = global_position
	
	_animate_car_door(entry_side, preload("res://cars/VehicleBoarding.gd").duration_for(self, entry_side) - 0.60)
	
	var lane_follow := get_parent() as PathFollow2D
	if lane_follow != null:
		var destination := get_tree().current_scene
		if destination == null:
			destination = lane_follow.get_parent().get_parent().get_parent()
		reparent(destination, true)
		_detached_from_lane = true
	velocity = Vector2.ZERO
	_driver.hide()
	_driver.set_physics_process(false)
	_ensure_camera()
	camera.enabled = true
	camera.set_process(true)
	camera.set_physics_process(true)
	preload("res://systems/DynamicCamera.gd").handoff(camera, camera_view)

	if headlight: headlight.visible = true
	_ensure_engine_audio()
	if engine_audio:
		engine_audio.volume_db = -12.0
		engine_audio.play()
	_ensure_radio_audio()
	if radio_audio and not radio_tracks.is_empty():
		radio_audio.stream = radio_tracks[radio_index]
		radio_audio.play()

	# Alarme e Alerta Policial se o jogador roubar uma viatura da PM
	if was_occupied and not taxi_passenger:
		# Taking the keys from a driver also disarms later re-entry.
		_parked_theft_attempted = true
		stop_theft_alarm()
	if is_police_vehicle and not was_stolen_from_police:
		was_stolen_from_police = true
		_parked_theft_attempted = true
		_trigger_police_theft()
	elif not taxi_passenger and not _parked_theft_attempted:
		_parked_theft_attempted = true
		if has_theft_alarm and not theft_from_traffic and not was_occupied:
			start_theft_alarm()

	_boarding = preload("res://cars/VehicleBoarding.gd").new()
	add_child(_boarding)
	_boarding.begin(self, player_body, approach, entry_side)
	if is_motorcycle and player_body.has_method("ensure_motorcycle_helmet"):
		player_body.ensure_motorcycle_helmet().mount(self)
	refresh_motorcycle_rider()

func _begin_vehicle_lockpick(player_body: CharacterBody2D) -> void:
	if is_instance_valid(_vehicle_lockpick): return
	_vehicle_lockpick = preload("res://ui/VehicleLockpick.gd").new()
	add_child(_vehicle_lockpick)
	_vehicle_lockpick.unlocked.connect(_finish_vehicle_lockpick.bind(true, player_body))
	_vehicle_lockpick.cancelled.connect(_finish_vehicle_lockpick.bind(false, player_body))
	_vehicle_lockpick.begin_for(player_body, self)

func _finish_vehicle_lockpick(success: bool, player_body: CharacterBody2D) -> void:
	_vehicle_lockpick = null
	if success:
		_police_lock_unlocked = true
		stop_theft_alarm()
		enter_vehicle(player_body)
	else:
		start_theft_alarm()
		_show_theft_hud_notice("LOCKPICK FALHOU")

func start_theft_alarm() -> void:
	# The child timer also expires while boarding, broken or traffic physics sleeps.
	# Repeated failures do not extend an already sounding alarm.
	if is_alarm_active: return
	is_alarm_active = true
	if not is_instance_valid(_alarm_timeout):
		_alarm_timeout = Timer.new()
		_alarm_timeout.one_shot = true
		add_child(_alarm_timeout)
		_alarm_timeout.timeout.connect(stop_theft_alarm)
	_alarm_timeout.start(randf_range(10.0, 15.0))
	_ensure_alarm_audio()
	if alarm_audio:
		alarm_audio.play()

func stop_theft_alarm() -> void:
	is_alarm_active = false
	if is_instance_valid(_alarm_timeout): _alarm_timeout.stop()
	if is_instance_valid(alarm_audio): alarm_audio.stop()
	if not is_siren_on: _turn_off_police_strobes()
	_update_headlight_state()

func _trigger_police_theft() -> void:
	# Successful lockpicking starts a one-star pursuit without sounding the alarm.
	var wanted = get_node_or_null("/root/WantedManager")
	if wanted and wanted.has_method("report_police_car_theft"):
		wanted.report_police_car_theft()
	elif wanted and wanted.has_method("report_crime"):
		wanted.report_crime(12)
		
	# 3. Notifica o ponto de prontidão da viatura
	if standby_source and is_instance_valid(standby_source) and standby_source.has_method("notify_stolen"):
		standby_source.notify_stolen()
		

func _show_theft_hud_notice(msg: String) -> void:
	if _driver and _driver.has_method("_show_weapon_notice"):
		_driver._show_weapon_notice(msg)
	var label = Label.new()
	label.text = msg
	label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	label.add_theme_font_size_override("font_size", 20)
	label.position = Vector2(-180, -90)
	label.z_index = 30
	add_child(label)
	var tw = create_tween()
	tw.tween_property(label, "position:y", -140.0, 3.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 3.5).set_delay(1.5)
	tw.tween_callback(label.queue_free)

func toggle_siren() -> void:
	is_siren_on = not is_siren_on
	if is_siren_on:
		_ensure_siren_audio()
		if siren_audio and not siren_audio.playing:
			siren_audio.play()
	else:
		if siren_audio and siren_audio.playing:
			siren_audio.stop()

func _update_police_strobes(delta: float) -> void:
	_strobe_timer += delta * 12.0
	var flash_state := int(_strobe_timer) % 4
	if active_roof_prop_node:
		var blue = active_roof_prop_node.get_node_or_null("LightBlue") as Polygon2D
		var red = active_roof_prop_node.get_node_or_null("LightRed") as Polygon2D
		var halo = active_roof_prop_node.get_node_or_null("SirenHalo") as PointLight2D
		if blue and red:
			if flash_state < 2:
				blue.color = Color(0.2, 0.7, 1.0, 1.0)
				red.color = Color(0.4, 0.05, 0.05, 0.4)
				if halo:
					halo.color = Color(0.2, 0.6, 1.0, 1.0)
					halo.energy = 1.4
					halo.position = Vector2(0, -8)
			else:
				blue.color = Color(0.05, 0.15, 0.4, 0.4)
				red.color = Color(1.0, 0.2, 0.2, 1.0)
				if halo:
					halo.color = Color(1.0, 0.2, 0.2, 1.0)
					halo.energy = 1.4
					halo.position = Vector2(0, 8)
					
	if is_alarm_active and headlight:
		headlight.visible = (int(_strobe_timer * 0.5) % 2 == 0)

func _turn_off_police_strobes() -> void:
	if active_roof_prop_node:
		var blue = active_roof_prop_node.get_node_or_null("LightBlue") as Polygon2D
		var red = active_roof_prop_node.get_node_or_null("LightRed") as Polygon2D
		var halo = active_roof_prop_node.get_node_or_null("SirenHalo") as PointLight2D
		if blue: blue.color = Color(0.15, 0.45, 1.0, 0.95)
		if red: red.color = Color(1.0, 0.15, 0.15, 0.95)
		if halo: halo.energy = 0.0

var _door_visual: Node2D = null
var _door_3d: Node3D
var _side_doors := {}
func _animate_car_door(side: float = -1.0, hold_seconds: float = 0.42) -> void:
	if is_motorcycle: return
	if is_3d_vehicle and is_instance_valid(body_model):
		_door_3d = _side_doors.get(side)
		if not is_instance_valid(_door_3d):
			_door_3d = preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
			body_model.add_child(_door_3d)
			_door_3d.configure(body_model, side)
			_side_doors[side] = _door_3d
		_door_3d.play(hold_seconds)
		_play_3d_door_sound()
		return
	if _door_visual == null:
		_door_visual = VEHICLE_DOOR_VISUAL.new()
		_door_visual.name = "ProceduralVehicleDoor"
		var body_width := maxf(24.0, crop.size.x * uniform_scale * 0.72)
		_door_visual.configure(
			Vector2(target_length * 0.18, -body_width * 0.5 + 1.0),
			target_length * 0.43
		)
		add_child(_door_visual)
	var body_color := visual.modulate if visual != null else Color("#3c6382")
	_door_visual.play(body_color, side, hold_seconds)

func _play_3d_door_sound() -> void:
	var audio := AudioStreamPlayer2D.new()
	audio.stream = ProceduralAudio.get_car_door_open_stream()
	audio.bus = &"SFX"
	audio.max_distance = 500
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _get_safe_exit_position() -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var candidates: Array[Vector2] = [
		global_position - transform.y * 45.0, # Porta do motorista (esquerda)
		global_position + transform.y * 45.0, # Porta do passageiro (direita)
		global_position - transform.x * 52.0, # Traseira
		global_position + transform.x * 52.0  # Dianteira
	]
	if taxi_passenger:
		candidates[0] = global_position + transform.y * 45.0
		candidates[1] = global_position - transform.y * 45.0
	for pos in candidates:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = pos
		query.collision_mask = 1 # Camada de colisão sólida do mapa
		var result := space_state.intersect_point(query, 1)
		if result.is_empty():
			return pos
	return candidates[0]

var _boarding: Node

func exit_vehicle() -> void:
	_launch.reset()
	_tire_trail.reset()
	if not is_driven_by_player: return
	if taxi_passenger and is_instance_valid(_taxi_service): _taxi_service.stop_ride()
	preload("res://cars/VehicleBoarding.gd").start_exit(self, _driver)

func force_exit_vehicle() -> void:
	# Lifecycle cleanup (death/scene travel) cannot leave a pending animation.
	if not is_driven_by_player: return
	if taxi_passenger and is_instance_valid(_taxi_service): _taxi_service.stop_ride()
	if is_instance_valid(_boarding): _boarding.cancel()
	_complete_exit_vehicle(_get_safe_exit_position())

func _complete_exit_vehicle(exit_position: Vector2) -> void:
	if not is_driven_by_player:
		return
	if is_motorcycle and is_instance_valid(_driver) and _driver.has_method("ensure_motorcycle_helmet"):
		_driver.ensure_motorcycle_helmet().dismount()
	preload("res://cars/VehicleBoarding.gd").clear_occupant(self)
	var camera_view := preload("res://systems/DynamicCamera.gd").capture_view(get_viewport())
	is_driven_by_player = false
	velocity = Vector2.ZERO
	speed = 0.0
	if headlight: headlight.visible = false
	if engine_audio:
		engine_audio.stop()
		engine_audio.volume_db = -22.0
	_engine_sound.stop()
	if radio_audio: radio_audio.stop()
	if skid_audio: skid_audio.stop()
	if camera:
		camera.enabled = false
		camera.set_process(false)
		camera.set_physics_process(false)


	if is_instance_valid(_driver):
		remove_collision_exception_with(_driver)
		_driver.remove_collision_exception_with(self)
		_driver.global_position = exit_position
		_driver.velocity = Vector2.ZERO
		_driver.reset_physics_interpolation()
		for col in _driver.find_children("", "CollisionShape2D", true, false):
			col.set_deferred("disabled", false)
		_driver.show()
		_driver.set_physics_process(true)
		var player_camera := _driver.get_node_or_null("Camera") as Camera2D
		if player_camera != null:
			preload("res://systems/DynamicCamera.gd").handoff(player_camera, camera_view)
	_driver = null
	if taxi_passenger and is_instance_valid(_taxi_service): _taxi_service.finish_exit()
	taxi_passenger = false
	refresh_motorcycle_rider()

func _physics_process(delta: float) -> void:
	if not is_driven_by_player or is_broken:
		_launch.reset()
		_tire_trail.reset()
	preload("res://cars/VehicleMotionSafety.gd").sanitize(self)
	has_nitro = false
	is_boosting = false
	if is_instance_valid(_boarding) and _boarding.active:
		velocity = Vector2.ZERO
		return
	if is_3d_vehicle and not is_processing():
		_update_3d_orientation(delta)
	if is_instance_valid(_taxi_service) and _taxi_service.is_modal():
		velocity = Vector2.ZERO
		return

	# Sempre permite ao jogador sair com F/Enter mesmo que o carro esteja em chamas ou quebrado
	if is_driven_by_player:
		if is_instance_valid(_driver): _driver.global_position = global_position
		var exit_pressed := Input.is_action_pressed("exit_vehicle")
		if not exit_pressed: _entry_input_released = true
		if _entry_input_released and exit_pressed:
			exit_vehicle()
			return
	if taxi_passenger and is_instance_valid(_taxi_service):
		_taxi_service.physics_tick(delta)
		return

	if is_broken:
		velocity = velocity.move_toward(Vector2.ZERO, braking * preload("res://cars/VehicleMotionSafety.gd").brake_mass_scale(vehicle_mass) * delta)
		if _detached_from_lane:
			preload("res://cars/VehicleMotionSafety.gd").move(self)
		return
	if not is_driven_by_player:
		handbrake_slide = 0.0
		lateral_speed = 0.0
		if _detached_from_lane:
			velocity = velocity.move_toward(Vector2.ZERO, friction * preload("res://cars/VehicleMotionSafety.gd").coast_mass_scale(vehicle_mass) * delta)
			preload("res://cars/VehicleMotionSafety.gd").move(self)
			if not is_in_group("parked_vehicle") and not is_in_group("player_car"):
				var player_node := get_tree().get_first_node_in_group("player") as Node2D
				var dist := global_position.distance_to(player_node.global_position) if is_instance_valid(player_node) else 9999.0
				if dist > 550.0 and velocity.length_squared() < 10.0:
					_abandoned_timer += delta
					if _abandoned_timer > 18.0:
						queue_free()
				else:
					_abandoned_timer = 0.0
		if is_alarm_active:
			_update_police_strobes(delta)
		elif is_siren_on:
			_update_police_strobes(delta)
		else:
			_turn_off_police_strobes()
		return
	
	# Controle de Sirene da PM quando o jogador está dirigindo (Tecla H ou siren_toggle)
	if is_police_vehicle:
		var siren_pressed := Input.is_key_pressed(KEY_H) or (InputMap.has_action("siren_toggle") and Input.is_action_pressed("siren_toggle"))
		if siren_pressed and not _siren_key_down:
			toggle_siren()
		_siren_key_down = siren_pressed

	if is_alarm_active or is_siren_on:
		_update_police_strobes(delta)
	else:
		_turn_off_police_strobes()
	
	# Troca de rádio
	if InputMap.has_action("radio_next") and Input.is_action_just_pressed("radio_next"):
		if not radio_tracks.is_empty():
			radio_index = (radio_index + 1) % radio_tracks.size()
			radio_audio.stream = radio_tracks[radio_index]
			radio_audio.play()

	# === Hit-stop ===
	if _hit_stop_frames > 0:
		_hit_stop_frames -= 1
		return

	var throttle: float = -get_node("/root/GameInput").movement().y
	var steering: float = get_node("/root/GameInput").movement().x
	if not _drive_input_armed:
		_drive_input_armed = is_zero_approx(throttle) and is_zero_approx(steering)
		throttle = 0.0
		steering = 0.0
	
	var handbrake := Input.is_action_pressed("handbrake")
	_launch.update(delta, velocity.length(), throttle, handbrake, max_speed, not is_broken)
	handbrake_slide = 0.7 if handbrake and velocity.length() > 55.0 else maxf(0.0, handbrake_slide - delta)
	if not is_instance_valid(_drift_weather): _drift_weather = get_tree().get_first_node_in_group("day_night_manager")
	var wetness: float = _drift_weather.get_rain_intensity() if is_instance_valid(_drift_weather) else 0.0
	var lateral_velocity = velocity.project(transform.y)
	lateral_speed = lateral_velocity.length()
	is_skidding = lateral_speed > lerpf(70.0, 45.0, wetness) or (handbrake and velocity.length() > 60.0)
	if skid_line: skid_line.clear_points()


	_drivetrain.update(str(VehicleCatalog.get_vehicle_spec(active_archetype_id).get("drivetrain", "rwd")), velocity.dot(transform.x), throttle, steering, wetness)
	velocity = preload("res://cars/VehicleMotionSafety.gd").grip(velocity, global_rotation, drift_factor + _drivetrain.drift_bias, delta, wetness, handbrake_slide > 0.0, vehicle_mass)
	if handbrake: velocity = velocity.move_toward(Vector2.ZERO, braking*0.10*preload("res://cars/VehicleMotionSafety.gd").brake_mass_scale(vehicle_mass)*delta)
	var longitudinal := velocity.dot(transform.x)
	var slide_steer := lerpf(1.0, 1.65, clampf(handbrake_slide / 0.35, 0.0, 1.0))
	_handling_yaw_rate = preload("res://cars/VehicleMotionSafety.gd").steering_rate(_handling_yaw_rate, steering, longitudinal, turn_speed * _drivetrain.steer_scale * slide_steer, vehicle_mass, delta)
	var proposed_rotation := rotation + _handling_yaw_rate * delta
	var forklift := get_node_or_null("ForkliftLift")
	preload("res://cars/VehicleMotionSafety.gd").rotate_clear(self, forklift.safe_rotation(proposed_rotation) if forklift else proposed_rotation)
	var forward := transform.x
	if not is_zero_approx(throttle):
		if (throttle > 0.0 and velocity.dot(forward) < -8.0) or (throttle < 0.0 and velocity.dot(forward) > 8.0):
			velocity = velocity.move_toward(Vector2.ZERO, braking * preload("res://cars/VehicleMotionSafety.gd").brake_mass_scale(vehicle_mass) * delta)
		elif forklift:
			velocity = (velocity + forward * throttle * acceleration * delta).limit_length(forklift.speed_limit())
		else:
			velocity = (velocity + forward * throttle * acceleration * preload("res://cars/VehicleMotionSafety.gd").drive_mass_scale(vehicle_mass) * _drivetrain.force_scale * _launch.force_scale * _engine_sound.drive_force(velocity.length(), max_speed) * delta).limit_length(_engine_sound.road_top_speed(max_speed))
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * preload("res://cars/VehicleMotionSafety.gd").coast_mass_scale(vehicle_mass) * delta)

	if forklift: velocity = velocity.limit_length(forklift.speed_limit())
	if _launch.holding: velocity = Vector2.ZERO
	is_skidding = is_skidding or _launch.wheelspin > 0.12
	_tire_trail.update(self, delta, is_driven_by_player and not is_broken and is_skidding, 0.38 + _launch.wheelspin * 0.25)
	if is_driven_by_player: _update_skid_audio()
	var prev_velocity = velocity
	preload("res://cars/VehicleMotionSafety.gd").move(self)
	
	# Same cached family/RPM controller as personal cars; large vehicles keep diesel timbre.
	if engine_audio and not is_broken:
		_engine_sound.update(engine_audio, velocity.length(), forklift.speed_limit() if forklift else _engine_sound.road_top_speed(max_speed), throttle, delta, active_archetype_id, false, _launch.charge * _launch.strength)
	elif engine_audio:
		engine_audio.stop()
		_engine_sound.stop()

	# Colisões e impactos
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var body = col.get_collider()
		if preload("res://guns/combat/VehiclePersonImpact.gd").is_person(body):
			preload("res://guns/combat/VehiclePersonImpact.gd").hit(self, body, prev_velocity)
			continue
		var normal_impact = maxf(0.0, -prev_velocity.dot(col.get_normal()))
		var impact_speed = normal_impact
		if impact_speed > (35.0 if active_archetype_id == "port_forklift" else 85.0) and is_instance_valid(body) and body != _driver and not body.is_in_group("ambient_traffic") and not body.is_in_group("vehicle") and body.has_method("take_damage"):
			body.take_damage(100, is_driven_by_player)
		
		# Se colidiu com outro carro, deforma o outro carro também!
		if is_instance_valid(body) and body != self and impact_speed > 35.0:
			if body.has_method("_apply_crash_deformation"):
				body._apply_crash_deformation(-col.get_normal(), impact_speed, col.get_position())
		
		if impact_speed > 35.0:
			var is_post: bool = is_instance_valid(body) and (body.is_in_group("fragile_road_post") or body.is_in_group("street_lamp"))
			_apply_crash_deformation(col.get_normal(), impact_speed, col.get_position(), is_post)
			if is_driven_by_player:
				_do_screen_shake(clampf(impact_speed / 1200.0, 0.02, 0.06) if is_post else clampf(impact_speed / 500.0, 0.05, 0.4))
				_hit_stop_frames = 0 if is_post else (3 if impact_speed > 250 else 2)
			_ensure_collision_particles()
			collision_particles.global_position = col.get_position()
			if is_post:
				collision_particles.direction = col.get_normal()
				collision_particles.spread = 45.0
				collision_particles.color = Color(1.0, 0.85, 0.35, 1.0)
				collision_particles.initial_velocity_min = 35.0
				collision_particles.initial_velocity_max = 75.0
				preload("res://guns/combat/WeaponEffects.gd").spawn_post_impact(get_parent(), col.get_position(), col.get_normal(), impact_speed)
			else:
				collision_particles.direction = col.get_normal()
				collision_particles.spread = 60.0
				collision_particles.color = Color(0.85, 0.85, 0.85, 1.0)
				collision_particles.initial_velocity_min = 50.0
				collision_particles.initial_velocity_max = 100.0
			collision_particles.restart()
			
			preload("res://audio/VehicleCrashAudio.gd").play(self, body, col.get_position(), impact_speed)
			
		if impact_speed > 180.0 and Time.get_ticks_msec()-_last_collision_damage_ms > 650:
			_last_collision_damage_ms = Time.get_ticks_msec()
			take_damage(preload("res://cars/VehicleMotionSafety.gd").collision_damage(impact_speed), is_driven_by_player)

	# Ground-contact residue is rendered separately from braking skid marks.
	bloody_tires_timer = maxf(0.0, bloody_tires_timer - delta)

func _activate_bloody_tires() -> void:
	bloody_tires_timer = 4.0
	preload("res://guns/combat/BloodTransferSystem.gd").splash(self)
	if is_driven_by_player:
		_do_screen_shake(0.18)

func _do_screen_shake(intensity: float):
	if not camera: return
	var tween = create_tween()
	var steps = 6
	var duration = 0.05
	for i in steps:
		var offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity * 30.0
		tween.tween_property(camera, "offset", offset, duration)
	tween.tween_property(camera, "offset", Vector2.ZERO, duration)

func _update_skid_audio():
	if is_skidding:
		_ensure_skid_audio()
		if skid_audio and not skid_audio.playing:
			skid_audio.play()
	elif not is_skidding and skid_audio and skid_audio.playing:
		skid_audio.stop()

var block_wait_timer: float = 0.0
var _clearance_retreat := 0.0
var _clearance_hold := 0.0
var _clearance_requester: WeakRef
var _clearance_last_requester := 0
var _avoidance_probe_timer := 0.0
var is_moving_on_lane: bool = false
var _lane_motion_speed := 0.0
var _lane_motion_initialized := false
var _junction_traffic_controller: Node = null
var _last_lane_motion_contract: Dictionary = {}
var _remote_lane_elapsed := 0.0
var remote_lane_steps := 0

func _process(delta: float) -> void:
	if is_motorcycle and not is_driven_by_player:
		_update_motorcycle_traffic_audio(delta)
	if is_3d_vehicle:
		_update_3d_orientation(delta)
	if is_instance_valid(_taxi_service) and _taxi_service.state != "idle": return
	if is_broken or is_driven_by_player:
		_remote_lane_elapsed = 0.0
		return
	# Keep remote traffic alive at 10 Hz. Nearby cars still use every frame;
	# rendering, player driving and physics contacts have their own cadence.
	# Accumulated delta preserves travel speed and every remote step still
	# applies the same stop-distance, spacing and reservation contracts.
	var on_screen := get_viewport().get_visible_rect().grow(260).has_point(get_canvas_transform() * global_position)
	if not is_driven_by_player and headlight:
		var light_active := on_screen and is_night_or_storm and not is_broken
		headlight.visible = light_active and (not is_instance_valid(body_model) or not body_model.broken_lamps[0])
		if second_headlight:
			second_headlight.visible = light_active and (not is_instance_valid(body_model) or not body_model.broken_lamps[1])
	if smoke_emitter and smoke_emitter.emitting != (health < 50 and on_screen):
		smoke_emitter.emitting = health < 50 and on_screen
	_remote_lane_elapsed += delta
	var interval := minf(0.1, MAX_LANE_ADVANCE_PER_FRAME * 0.8 / maxf(speed, 1.0))
	var near_center := false
	if on_screen:
		var viewport_rect := get_viewport().get_visible_rect()
		near_center = viewport_rect.get_center().distance_to(get_canvas_transform() * global_position) < NEAR_CENTER_RADIUS_PX
	if on_screen and not near_center:
		interval = minf(interval, MID_TIER_INTERVAL)
	if not near_center and not _emergency_yield_active and _remote_lane_elapsed < interval:
		return
	var motion_delta := _remote_lane_elapsed
	_remote_lane_elapsed = 0.0
	if not on_screen: remote_lane_steps += 1
	advance_on_lane(motion_delta)

func _update_motorcycle_traffic_audio(delta: float) -> void:
	var listener := get_viewport().get_camera_2d()
	var audible := listener != null and global_position.distance_squared_to(listener.get_screen_center_position()) < 420.0*420.0
	if not audible or is_broken or _detached_from_lane:
		if engine_audio: engine_audio.stop()
		_engine_sound.stop()
		return
	_ensure_engine_audio()
	_engine_sound.update(engine_audio, _lane_motion_speed, _engine_sound.road_top_speed(max_speed), .35 if is_moving_on_lane else 0.0, delta, active_archetype_id)
	engine_audio.volume_db -= 8.0
	for layer in _engine_sound._layer_players: layer.volume_db -= 8.0
	if is_instance_valid(_engine_sound._road_player): _engine_sound._road_player.volume_db -= 10.0

func advance_on_lane(delta: float) -> void:
	is_moving_on_lane = false
	if _rider_fallen: return
	_traffic_horn_cooldown = maxf(0.0, _traffic_horn_cooldown - delta)
	var lane_follow := get_parent() as PathFollow2D
	if lane_follow == null:
		return
	var path := lane_follow.get_parent() as Path2D
	if path == null or path.curve == null:
		return
	if _siren_maneuver.tick(self,path,lane_follow,delta): return
	if _advance_clearance_retreat(delta, path, lane_follow):
		return
	var controller := _get_junction_traffic_controller()
	if controller != null:
		var graph = controller.get("graph_source")
		if graph is Node and not graph.is_ancestor_of(path) and not controller.is_ancestor_of(path):
			controller = null
	# The two regional lane ends are close enough for the city graph to infer
	# a U-turn. They are a continuous border, so the world owns this handoff.
	if bool(path.get_meta("continuous_border_end",false)) and lane_follow.progress > path.curve.get_baked_length()-180:
		controller = null
	if bool(path.get_meta("continuous_border_start",false)) and lane_follow.progress < 180:
		controller = null
	if not has_meta("taxi_route_end") and controller != null and controller.has_method("complete_lane_transition"):
		if bool(controller.call("complete_lane_transition", self, path, lane_follow)):
			return
	if not _lane_motion_initialized:
		_lane_motion_speed = speed
		_lane_motion_initialized = true

	var safety_zone_motion := _traffic_control_zone_motion(path, lane_follow)
	var must_clear_rail_crossing := bool(safety_zone_motion.get("must_clear_rail_crossing", false))
	var obstruction := _get_lane_obstruction(lane_follow, must_clear_rail_crossing)
	_update_person_wait(obstruction.get("person"), delta)
	if _person_warned and _person_wait >= PERSON_HORN_DELAY + PERSON_WARNING_GRACE:
		obstruction = _get_lane_obstruction(lane_follow, must_clear_rail_crossing)
	var ray_hard_blocked: bool = obstruction.hard
	var observed_pose := global_transform
	# Physical hull contacts (including roadside props) must also trigger
	# recovery; the actor rays intentionally ignore these static obstacles.
	obstruction.hard = bool(obstruction.hard) or _lane_sweep_blocked
	_update_traffic_avoidance(delta, lane_follow, obstruction, safety_zone_motion)
	_lane_sweep_blocked = false
	# Avoidance is synchronous. Only a lateral move refreshes the rays and
	# changes the lane geometry; otherwise reuse the same observation, removing
	# the previous sweep flag exactly as the second query used to do.
	if global_transform != observed_pose:
		obstruction = _get_lane_obstruction(lane_follow, must_clear_rail_crossing)
	else:
		obstruction.hard = ray_hard_blocked
	var hard_blocked: bool = obstruction.hard
	var yield_blocked: bool = obstruction.yield
	var target_lane_speed := speed
	if get_traffic_storage_length() >= 110.0:
		var curve_probe := minf(lane_follow.progress + minf(target_length, 140.0), path.curve.get_baked_length())
		var curve_pose := path.global_transform * path.curve.sample_baked_with_rotation(curve_probe, true)
		var curve_angle := absf(angle_difference(global_rotation, curve_pose.get_rotation()))
		if curve_angle > 0.02:
			target_lane_speed = minf(target_lane_speed, sqrt(45.0 * maxf(1.0, curve_probe - lane_follow.progress) / curve_angle))
	if bool(path.get_meta("mountain_traffic", false)):
		var probe := minf(lane_follow.progress + target_length, path.curve.get_baked_length())
		var ahead := path.curve.sample_baked_with_rotation(probe, true)
		var turn := absf(wrapf(ahead.get_rotation()-lane_follow.rotation,-PI,PI))
		# Antecipar a curva evita entrar no hairpin com a velocidade da reta.
		target_lane_speed = minf(target_lane_speed, sqrt(55.0 * target_length / maxf(turn,0.01)))
	var maximum_advance := INF
	var rescue_clearance := preload("res://emergency/MedicalRescueWorkZone.gd").lane_clearance(self, path, lane_follow, _lane_braking_rate(), maxf(speed, _lane_motion_speed))
	maximum_advance = minf(maximum_advance, rescue_clearance)
	target_lane_speed = minf(target_lane_speed, sqrt(2.0 * _lane_braking_rate() * rescue_clearance))
	# Authored loading bays can hold traffic at an exact offset on its own lane.
	if has_meta("traffic_stop_offset"):
		var stop_distance := maxf(0.0,float(get_meta("traffic_stop_offset"))-lane_follow.progress)
		maximum_advance = minf(maximum_advance, stop_distance)
		target_lane_speed = minf(target_lane_speed,sqrt(2.0*_lane_braking_rate()*stop_distance))
	var spacing := _lane_spacing_motion(lane_follow)
	target_lane_speed = minf(target_lane_speed, float(spacing.target_speed))
	maximum_advance = minf(maximum_advance, float(spacing.allowed_advance))
	target_lane_speed = minf(target_lane_speed, float(safety_zone_motion.target_speed))
	maximum_advance = minf(maximum_advance, float(safety_zone_motion.allowed_advance))

	var requested_advance := maxf(_lane_motion_speed, target_lane_speed) * delta
	var signal_contract := {}
	if controller != null and controller.has_method("evaluate_lane_motion"):
		signal_contract = controller.call(
			"evaluate_lane_motion",
			self,
			path,
			lane_follow,
			requested_advance,
			target_length,
			_lane_motion_speed,
			_lane_braking_rate()
		)
		if bool(signal_contract.get("controlled", false)):
			target_lane_speed = minf(target_lane_speed, float(signal_contract.get("target_speed", INF)))
			maximum_advance = minf(maximum_advance, float(signal_contract.get("allowed_advance", INF)))
	_last_lane_motion_contract = signal_contract

	# The canonical reservation replaces the old lane-name priority while a
	# vehicle owns a junction. Physical actors still remain hard blockers.
	if bool(signal_contract.get("reservation_granted", false)):
		yield_blocked = false
	if hard_blocked or yield_blocked:
		target_lane_speed = 0.0
	if not bool(signal_contract.get("controlled", false)) and _must_stop_at_managed_signal(lane_follow):
		target_lane_speed = 0.0
		maximum_advance = 0.0

	var end_motion := {"target_speed": speed, "allowed_advance": maxf(0.0,float(get_meta("taxi_route_end",0.0))-lane_follow.progress)} if has_meta("taxi_route_end") else _open_lane_end_motion(path, lane_follow, controller)
	target_lane_speed = minf(target_lane_speed, float(end_motion.target_speed))
	maximum_advance = minf(maximum_advance, float(end_motion.allowed_advance))

	var previous_speed := _lane_motion_speed
	# Calmer ambient traffic, preserving stop lines and collision reservations.
	target_lane_speed *= 0.85
	var rate := _lane_acceleration_rate() if target_lane_speed > _lane_motion_speed else _lane_braking_rate()
	_lane_motion_speed = move_toward(_lane_motion_speed, maxf(0.0, target_lane_speed), rate * delta)
	# A render hitch must not turn ordinary lane travel into a visible teleport.
	# Normal 60 FPS motion is far below this cap; it only absorbs long frames.
	var desired_advance := minf(
		maxf(0.0, (previous_speed + _lane_motion_speed) * 0.5 * delta),
		MAX_LANE_ADVANCE_PER_FRAME
	)
	var actual_advance := minf(desired_advance, maximum_advance)
	# A newly intruding car can already be inside this frame's braking travel.
	# Queue spacing still clamps position, but must not erase the collision.
	if maximum_advance < desired_advance and previous_speed >= 80.0:
		var sudden_contact := KinematicCollision2D.new()
		var braking_motion := global_transform.x.normalized() * desired_advance
		if test_move(global_transform, braking_motion, sudden_contact):
			_lane_contact_crash(sudden_contact, global_transform.x.normalized() * previous_speed)
	var person_bypass: Array[PhysicsBody2D] = []
	if actual_advance > 0.001:
		var proposed := _lane_proposed_pose(path, lane_follow, actual_advance)
		var incoming := global_position.direction_to(proposed.origin) * maxf(previous_speed, _lane_motion_speed)
		person_bypass = preload("res://guns/combat/VehiclePersonImpact.gd").prepare_motion(self, incoming, proposed.origin - global_position)
	if actual_advance > 0.001 and not _lane_step_is_clear(path, lane_follow, actual_advance):
		if _person_warned:
			# Long hulls reserve a small corner margin before kinematic contact.
			var bumper_contact := KinematicCollision2D.new()
			if test_move(global_transform, global_transform.x.normalized() * maxf(3.0, actual_advance), bumper_contact):
				_press_blocking_person(bumper_contact, delta)
		actual_advance = 0.0
		_lane_motion_speed = 0.0
		_lane_sweep_blocked = true
		hard_blocked = true
		target_lane_speed = 0.0
	if actual_advance > 0.001:
		var next_offset := lane_follow.progress+actual_advance
		if lane_follow.loop: next_offset = fposmod(next_offset,path.curve.get_baked_length())
		var next_pose := path.global_transform * path.curve.sample_baked_with_rotation(next_offset, lane_follow.cubic_interp)
		var next_point := next_pose.origin + next_pose.y * position.y
		var motion := next_point-global_position
		if bool(path.get_meta("mountain_traffic", false)) and not _mountain_hull_is_clear(path, next_offset):
			actual_advance = 0.0
			motion = Vector2.ZERO
			_lane_motion_speed = 0.0
			hard_blocked = true
			target_lane_speed = 0.0
		# Sweep the entire hull against vehicles before advancing the PathFollow.
		# Keep the existing kinematic test for map walls and walking actors.
		var sweep := PhysicsShapeQueryParameters2D.new()
		sweep.shape = collision.shape
		sweep.transform = collision.global_transform
		sweep.motion = motion
		sweep.margin = 0.1
		sweep.collision_mask = collision_mask & 2
		var sweep_exclusions: Array[RID] = [get_rid()]
		for body in get_traffic_bodies():
			if body != self and body is CollisionObject2D: sweep_exclusions.append(body.get_rid())
		sweep.exclude = sweep_exclusions
		var fractions := get_world_2d().direct_space_state.cast_motion(sweep)
		var contact := KinematicCollision2D.new()
		var body_contact := test_move(global_transform,motion,contact)
		if body_contact:
			_press_blocking_person(contact, delta)
			_lane_contact_crash(contact, motion.normalized() * maxf(previous_speed, _lane_motion_speed))
		if fractions[0] < 1.0 or body_contact:
			_lane_sweep_blocked = true
			# Recovery can point backwards at contact. Its absolute length must
			# never become forward lane progress, or queues creep through bodies.
			actual_advance *= fractions[0] if fractions[0] < 1.0 else 0.0
			_lane_motion_speed = 0.0
			hard_blocked = true
			target_lane_speed = 0.0
	if actual_advance > 0.001:
		lane_follow.progress += actual_advance
		is_moving_on_lane = true
	for person in person_bypass:
		if is_instance_valid(person): remove_collision_exception_with(person)
	if not has_meta("taxi_route_end") and controller != null and controller.has_method("complete_lane_transition"):
		controller.call("complete_lane_transition", self, path, lane_follow)

	# Following converges smoothly to its standstill gap. Sub-pixel creeping
	# must count as waiting, otherwise a blocked junction delays recovery until
	# the asymptote happens to fall below the movement epsilon.
	var blocked := actual_advance <= delta and target_lane_speed <= 1.0
	if blocked:
		block_wait_timer += delta
		if block_wait_timer > 2.0 and bool(signal_contract.get("reservation_granted", false)):
			_request_junction_clearance(path, lane_follow)
		if hard_blocked and obstruction.get("person") == null and block_wait_timer > 0.6 and _traffic_horn_cooldown <= 0.0:
			honk_horn()
			_traffic_horn_cooldown = 2.5 + float(get_instance_id() % 5) * 0.2
	else:
		block_wait_timer = maxf(0.0, block_wait_timer - delta * 2.0)
	if visual:
		visual.position = visual.position.lerp(Vector2.ZERO, 8.0 * delta)

func _press_blocking_person(contact: KinematicCollision2D, delta: float) -> void:
	# At bumper distance there is no room to build speed. Sustained throttle
	# after the warning produces a low-speed knockdown, never cruise damage.
	var person := contact.get_collider() as Node
	if person == null or not _person_patience_expired(person): return
	_person_push_time += delta
	if _person_push_time >= 0.6:
		preload("res://guns/combat/VehiclePersonImpact.gd").hit(self, person, global_transform.x.normalized() * preload("res://guns/combat/VehiclePersonImpact.gd").MIN_SPEED)

func _lane_contact_crash(contact: KinematicCollision2D, incoming: Vector2) -> void:
	var body := contact.get_collider() as Node
	if body == null or preload("res://guns/combat/VehiclePersonImpact.gd").is_person(body): return
	var force := maxf(0.0, -incoming.dot(contact.get_normal()))
	if force < 80.0 or Time.get_ticks_msec() - _last_collision_damage_ms < 650: return
	_last_collision_damage_ms = Time.get_ticks_msec()
	_apply_crash_deformation(contact.get_normal(), force, contact.get_position())
	if body.has_method("_apply_crash_deformation"):
		body._apply_crash_deformation(-contact.get_normal(), force, contact.get_position())
	preload("res://audio/VehicleCrashAudio.gd").play(self, body, contact.get_position(), force)
	if force > 180.0:
		take_damage(preload("res://cars/VehicleMotionSafety.gd").collision_damage(force), false)

func _traffic_sweep_clear(motion: Vector2, displacement: Vector2 = Vector2.ZERO) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.transform.origin += displacement
	query.motion = motion
	query.margin = 0.1
	query.collision_mask = 15
	query.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	return space.cast_motion(query)[0] >= 1.0

func get_traffic_bodies() -> Array:
	return [self]

func get_traffic_storage_length() -> float:
	var sizes := TRAFFIC_FLOW.extent(self, global_transform.x.normalized())
	return sizes.x + sizes.y

func occupies_junction(center: Vector2, radius: float) -> bool:
	return TRAFFIC_FLOW.occupies_junction(self, center, radius)

func _lane_proposed_pose(path: Path2D, follow: PathFollow2D, advance: float) -> Transform2D:
	var offset := follow.progress + advance
	if follow.loop: offset = fposmod(offset, path.curve.get_baked_length())
	return path.global_transform * path.curve.sample_baked_with_rotation(offset, follow.cubic_interp) * transform

func _lane_step_is_clear(path: Path2D, follow: PathFollow2D, advance: float) -> bool:
	var pose := _lane_proposed_pose(path, follow, advance)
	return can_apply_lane_pose(pose)

func can_apply_lane_pose(pose: Transform2D) -> bool:
	# Straight short cars retain the existing translation sweep. Long hulls and
	# rotating cars also need their corner arcs tested before updating the lane.
	if target_length < 110.0 and absf(angle_difference(global_rotation, pose.get_rotation())) < 0.01: return true
	return TRAFFIC_SWEEP.clear(self, [{"body": self, "pose": pose}])

func _clearance_pose(path: Path2D, offset: float, lateral: float) -> Transform2D:
	var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
	pose.origin += pose.y * lateral
	return pose * Transform2D(rotation, Vector2(position.x, 0.0)) * collision.transform

func _clearance_route_clear(path: Path2D, start: float, finish: float, lateral: float) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.collision_mask = 15
	query.exclude = [get_rid()]
	query.margin = 0.1
	var space := get_world_2d().direct_space_state
	var steps := maxi(1, ceili(absf(finish - start) / 2.0))
	for index in range(steps + 1):
		query.transform = _clearance_pose(path, lerpf(start, finish, float(index) / steps), lateral)
		query.motion = Vector2.ZERO
		if not space.intersect_shape(query, 1).is_empty(): return false
		if index < steps:
			var next := _clearance_pose(path, lerpf(start, finish, float(index + 1) / steps), lateral)
			query.motion = next.origin - query.transform.origin
			if space.cast_motion(query)[0] < 1.0: return false
	return true

func _request_junction_clearance(path: Path2D, follow: PathFollow2D) -> void:
	# Only the reservation owner asks for space, so conflicting streams cannot
	# order each other forwards. Probe the actual turn, not its tangent ray.
	if _clearance_hold > 0.0: return
	_clearance_hold = 0.5
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.collision_mask = 2
	query.exclude = [get_rid()]
	query.margin = 3.0
	for distance in range(4, 65, 4):
		query.transform = _clearance_pose(path, minf(follow.progress + distance, path.curve.get_baked_length()), position.y)
		for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
			var other := hit.collider as DemoTrafficVehicle
			if other != null and other != self and other.get_parent().get_parent() != path:
				other._accept_clearance_request(self)

func _accept_clearance_request(requester: DemoTrafficVehicle) -> bool:
	# Reversing a convoy needs a separate articulated manoeuvre planner.
	if get_traffic_bodies().size() > 1: return false
	if is_broken or is_driven_by_player or _detached_from_lane or _lane_motion_speed > 1.0: return false
	if _clearance_retreat > 0.0 or _clearance_requester != null: return false
	if _clearance_last_requester == requester.get_instance_id(): return false
	if bool(_last_lane_motion_contract.get("reservation_granted", false)): return false
	if not bool(requester._last_lane_motion_contract.get("reservation_granted", false)): return false
	var follow := get_parent() as PathFollow2D
	if follow == null: return false
	var path := follow.get_parent() as Path2D
	if path == null or path.curve == null or path.is_in_group("unified_lane_connector") or path.get_meta("mountain_traffic", false): return false
	if is_instance_valid(_taxi_service) and _taxi_service.state != "idle": return false
	var zone := _traffic_control_zone_motion(path, follow)
	if bool(zone.get("must_clear_rail_crossing", false)): return false
	var retreat := minf(48.0, follow.progress)
	if retreat < 8.0 or not _clearance_route_clear(path, follow.progress, follow.progress - retreat, position.y): return false
	_clearance_retreat = retreat
	_clearance_hold = 3.0
	_clearance_requester = weakref(requester)
	_clearance_last_requester = requester.get_instance_id()
	return true

func _advance_clearance_retreat(delta: float, path: Path2D, follow: PathFollow2D) -> bool:
	if _clearance_requester == null:
		_clearance_hold = maxf(0.0, _clearance_hold - delta)
		return false
	var requester := _clearance_requester.get_ref() as DemoTrafficVehicle
	if requester == null or not bool(requester._last_lane_motion_contract.get("reservation_granted", false)):
		_clearance_retreat = 0.0
		_clearance_hold = 0.0
	if _clearance_retreat > 0.0:
		var step := minf(minf(18.0 * delta, MAX_LANE_ADVANCE_PER_FRAME), minf(_clearance_retreat, follow.progress))
		if step > 0.001 and _clearance_route_clear(path, follow.progress, follow.progress - step, position.y):
			follow.progress -= step
			_clearance_retreat -= step
			is_moving_on_lane = true
		else:
			_clearance_retreat = 0.0
	else:
		_clearance_hold = maxf(0.0, _clearance_hold - delta)
	_lane_motion_speed = 0.0
	if _clearance_hold <= 0.0:
		_clearance_requester = null
	return true

func _update_traffic_avoidance(delta: float, follow: PathFollow2D, obstruction: Dictionary, zone: Dictionary) -> void:
	if _emergency_yield_active: return
	if get_traffic_storage_length() >= 110.0: return
	var path := follow.get_parent() as Path2D
	_avoidance_hold = maxf(0.0, _avoidance_hold - delta)
	_avoidance_probe_timer = maxf(0.0, _avoidance_probe_timer - delta)
	# Stay on authored narrow roads and outside junction/rail reservations.
	if path.get_meta("mountain_traffic", false) or bool(zone.get("must_clear_rail_crossing", false)):
		return
	if _get_junction_traffic_controller() != null and bool(_last_lane_motion_contract.get("controlled", false)) and not bool(_last_lane_motion_contract.get("reservation_granted", false)):
		return
	var owns_junction := bool(_last_lane_motion_contract.get("reservation_granted", false))
	if not owns_junction and (follow.progress < target_length or follow.progress > path.curve.get_baked_length() - target_length * 2.0):
		return
	var target_offset := position.y if _avoidance_hold > 0.0 else 0.0
	if obstruction.hard and block_wait_timer > 0.8 and _avoidance_probe_timer <= 0.0:
		_avoidance_probe_timer = 0.4
		# A small in-lane correction, tested over the full vehicle hull. Never
		# jump to another road or squeeze through a pedestrian/vehicle.
		for side in [-1.0, 1.0]:
			var candidate: float = side * (22.0 if is_motorcycle else 16.0)
			var lateral: Vector2 = global_transform.y * (candidate - position.y)
			var finish := minf(path.curve.get_baked_length(), follow.progress + target_length + 40.0)
			if _traffic_sweep_clear(lateral) and _clearance_route_clear(path, follow.progress, finish, candidate):
				target_offset = candidate
				_avoidance_hold = 2.0
				break
	var shift := move_toward(position.y, target_offset, delta * 18.0) - position.y
	if absf(shift) > 0.001 and _traffic_sweep_clear(global_transform.y * shift):
		position.y += shift
		for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
			var ray := get_node_or_null(ray_name) as RayCast2D
			if ray: ray.force_raycast_update()

func _mountain_hull_is_clear(path: Path2D, offset: float) -> bool:
	if not collision.shape is RectangleShape2D: return true
	var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
	var half: Vector2 = collision.shape.size*0.5 + Vector2.ONE*2.0
	var hull := PackedVector2Array()
	for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
		hull.append(pose * (collision.transform * corner))
	# PathFollow é atualizado em idle. O servidor físico ainda pode estar no
	# tick anterior; comparar as poses vivas impede atravessar outra carroceria.
	for other in get_tree().get_nodes_in_group("vehicle"):
		if other == self or not other is Node2D or other.global_position.distance_to(pose.origin) > 180: continue
		var shape := other.get_node_or_null("Collision") as CollisionShape2D
		if shape == null or shape.disabled or not shape.shape is RectangleShape2D: continue
		var other_half: Vector2 = shape.shape.size*0.5
		var other_hull := PackedVector2Array()
		for corner in [Vector2(-other_half.x,-other_half.y),Vector2(other_half.x,-other_half.y),other_half,Vector2(-other_half.x,other_half.y)]:
			other_hull.append(shape.global_transform * corner)
		if not Geometry2D.intersect_polygons(hull,other_hull).is_empty(): return false
	return true

func _get_lane_obstruction(lane_follow: PathFollow2D, must_clear_rail_crossing: bool = false) -> Dictionary:
	# PathFollow traffic already has exact same-lane spacing below. Ray casts are
	# reserved for living actors and deterministic intersection yielding; parked
	# cars, kerbs and railway fences beside an authored route must not freeze it.
	var current_path := lane_follow.get_parent() as Path2D
	var hard_blocked := false
	var yield_blocked := false
	var person: Node = null
	for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
		var ray := get_node_or_null(ray_name) as RayCast2D
		if ray == null or not ray.is_colliding():
			continue
		var collider := ray.get_collider() as Node
		if collider == null or collider == self:
			continue
		if collider.is_in_group("player") or collider.name == "Player":
			if person == null or global_position.distance_squared_to(collider.global_position) < global_position.distance_squared_to(person.global_position): person = collider
			hard_blocked = hard_blocked or not _person_patience_expired(collider)
			continue
		if collider.is_in_group("pedestrian"):
			if person == null or global_position.distance_squared_to(collider.global_position) < global_position.distance_squared_to(person.global_position): person = collider
			# A vehicle already committed between closed railway gates must leave
			# the track instead of yielding in the conflict zone. Players remain
			# hard blockers; this exception is only for ambient pedestrian AI.
			if _lane_pedestrian_blocks(lane_follow, collider, must_clear_rail_crossing):
				hard_blocked = true
			continue
		if not collider.is_in_group("vehicle"):
			continue
		# A responder waiting on its driveway must let the lane empty before
		# merging. The swept hull below still prevents physical overlap.
		if collider.is_in_group("emergency_vehicle") and collider.get_meta("depot_departure_pending", false):
			continue
		# A terminal coach still on its driveway yields to this lane; its swept
		# collision query waits for a real gap before crossing the sidewalk.
		if collider.is_in_group("harbor_terminal_coach") and collider.get_meta("terminal_yielding_to_lane", false):
			continue
		if collider.is_in_group("harbor_terminal_coach"):
			# A long tangent ray can see a queued coach beyond the junction.
			# Approach it along the real lane until braking is needed, so a car
			# holding the junction can clear its turn before joining that queue.
			hard_blocked = hard_blocked or _lane_terminal_coach_blocks(lane_follow, collider)
			continue
		if collider.get("is_driven_by_player") == true or collider.get("_detached_from_lane") == true or collider.get("is_broken") == true:
			hard_blocked = true
			continue
		var other_follow := collider.get_parent() as PathFollow2D
		if other_follow == null:
			hard_blocked = true
			continue
		var other_path := other_follow.get_parent() as Path2D
		if other_path == null or other_path == current_path:
			continue
		# A stable lane-name priority lets one stream clear the crossing instead
		# of two side rays making both streams wait forever.
		if String(current_path.name) > String(other_path.name):
			yield_blocked = true
	return {"hard": hard_blocked, "yield": yield_blocked, "person": person}

func _person_patience_expired(person: Node) -> bool:
	return _waiting_person != null and _waiting_person.get_ref() == person and _person_warned and _person_wait >= PERSON_HORN_DELAY + PERSON_WARNING_GRACE and not person.get_meta("medical_vehicle_protected", false) and preload("res://guns/combat/VehiclePersonImpact.gd").is_person(person)

func _update_person_wait(person: Node, delta: float) -> void:
	if person == null or _waiting_person == null or _waiting_person.get_ref() != person:
		_waiting_person = weakref(person) if person != null else null
		_person_wait = 0.0
		_person_warned = false
		_person_push_time = 0.0
	if person == null: return
	if _lane_motion_speed < 5.0 or _person_wait > 0.0:
		_person_wait += delta
	if _person_wait >= PERSON_HORN_DELAY and not _person_warned:
		honk_horn()
		_person_warned = true
		_traffic_horn_cooldown = PERSON_WARNING_GRACE

func _lane_terminal_coach_blocks(follow: PathFollow2D, coach: Node) -> bool:
	var path := follow.get_parent() as Path2D
	if path == null or path.curve == null or collision.shape == null:
		return true
	var braking_distance := _lane_motion_speed * _lane_motion_speed / (2.0 * _lane_braking_rate())
	var finish := minf(path.curve.get_baked_length(), follow.progress + braking_distance + 14.0)
	var samples := maxi(1, ceili((finish - follow.progress) / 4.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.collision_mask = 2
	query.margin = 2.0
	query.exclude = [get_rid()]
	for index in range(samples + 1):
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(lerpf(follow.progress, finish, float(index) / samples), true)
		query.transform = pose * transform * collision.transform
		for hit in get_world_2d().direct_space_state.intersect_shape(query):
			if hit.collider == coach: return true
	return false

func _lane_pedestrian_blocks(follow: PathFollow2D, pedestrian: Node, must_clear_rail_crossing: bool) -> bool:
	if _person_patience_expired(pedestrian): return false
	if must_clear_rail_crossing:
		return false
	if bool(follow.get_parent().get_meta("curved_pedestrian_corridor", false)):
		return preload("res://cars/traffic/LanePedestrianCorridor.gd").blocks(self, follow, pedestrian)
	return true

func _lane_spacing_motion(lane_follow: PathFollow2D) -> Dictionary:
	return TRAFFIC_FLOW.lane_motion(self, lane_follow, _lane_motion_speed, _lane_braking_rate())


func _lane_acceleration_rate() -> float:
	return minf(acceleration, maxf(80.0, speed * 1.8))


func _lane_braking_rate() -> float:
	return minf(braking, maxf(120.0, speed * 2.8))


static var _control_index_frame := -1
static var _control_index_tree := 0
static var _control_index_nodes: Array[Node] = []
static var _control_index_roads: Dictionary = {}
static var _custom_control_zones: Array[Node] = []

func _road_control_zones(road_id: String) -> Array:
	var tree := get_tree()
	var nodes := tree.get_nodes_in_group("traffic_control_zone")
	var frame := Engine.get_process_frames()
	# Share discovery across the whole fleet. Stop permissions remain live;
	# only membership is indexed. A scene/zone replacement invalidates even
	# within the current frame, before another vehicle can use the old nodes.
	if _control_index_frame != frame or _control_index_tree != tree.get_instance_id() or nodes != _control_index_nodes:
		_control_index_frame = frame
		_control_index_tree = tree.get_instance_id()
		_control_index_nodes = nodes
		_control_index_roads.clear()
		_custom_control_zones.clear()
		for zone in nodes:
			if zone is RoadCrossingArea2D or zone is RailLevelCrossing2D:
				var key := String(zone.road_id)
				if not _control_index_roads.has(key): _control_index_roads[key] = []
				_control_index_roads[key].append(zone)
			else:
				_custom_control_zones.append(zone)
	var result: Array = _control_index_roads.get(road_id, [])
	if _custom_control_zones.is_empty(): return result
	return result + _custom_control_zones

func _traffic_control_zone_motion(path: Path2D, lane_follow: PathFollow2D) -> Dictionary:
	var unrestricted := {
		"target_speed": INF,
		"allowed_advance": INF,
		"zone_id": &"",
		"must_clear_rail_crossing": false,
	}
	if path == null or path.curve == null or not path.is_in_group("unified_traffic_lane"):
		return unrestricted
	var road_id := String(path.get_meta("traffic_road_id", ""))
	if road_id.is_empty():
		return unrestricted
	var route_length := path.curve.get_baked_length()
	var lane_loops := bool(path.get_meta("traffic_lane_loop", lane_follow.loop)) and lane_follow.loop
	var nearest_stop_distance := INF
	var nearest_zone_id: StringName = &""
	var must_clear_rail_crossing := false
	for zone in _road_control_zones(road_id):
		# Reject unrelated authored roads before constructing a full crossing
		# snapshot (which also evaluates signals, occupants and railway gates).
		# Keep the dictionary contract for third-party/custom control zones.
		if zone is RoadCrossingArea2D or zone is RailLevelCrossing2D:
			if String(zone.road_id) != road_id:
				continue
		if not zone.has_method("get_crossing_data") or not zone.has_method("should_stop_vehicle"):
			continue
		var data = zone.get_traffic_geometry() if zone is RoadCrossingArea2D else zone.call("get_crossing_data")
		if not data is Dictionary or String((data as Dictionary).get("road_id", "")) != road_id:
			continue
		# Railway crossings expose a position-aware contract: an approaching car
		# must stop, while one which already passed its entry gate must keep its
		# escape lane and clear the track. Ordinary pedestrian crossings retain
		# their simpler global stop contract.
		var global_stop_required := bool(zone.call("should_stop_vehicle", self))
		var stop_required := global_stop_required
		if zone.has_method("should_stop_vehicle_at"):
			stop_required = bool(zone.call("should_stop_vehicle_at", global_position, self))
		if not stop_required:
			if (
				global_stop_required
				and not ((data as Dictionary).get("gate_geometry", {}) as Dictionary).is_empty()
				and _inside_rail_escape_envelope(data as Dictionary)
			):
				must_clear_rail_crossing = true
			continue
		var world_position: Vector2 = (data as Dictionary).get("position", Vector2.ZERO)
		var curve_offset := _control_zone_curve_offset(path, zone, world_position)
		var distance_to_center := curve_offset - lane_follow.progress
		if lane_loops and distance_to_center < -0.5:
			distance_to_center += route_length
		elif not lane_loops and distance_to_center < -target_length * 0.5:
			continue
		# Once the vehicle center has entered a crossing it must clear it; stopping
		# on a zebra crossing or railway track is less safe than completing exit.
		if distance_to_center <= 0.0:
			continue
		# Railway gates sit before the track conflict center. Stopping relative to
		# the center lets a car cross the entry gate before braking, after which
		# the escape policy correctly tells it to clear the tracks. Honour the
		# authored gate offset so an approaching car stops before committing.
		var gate_geometry: Dictionary = (data as Dictionary).get("gate_geometry", {})
		var control_offset := float(gate_geometry.get("gate_offset", 0.0))
		var stop_distance := distance_to_center - control_offset - target_length * 0.5 - 18.0
		if stop_distance < nearest_stop_distance:
			nearest_stop_distance = maxf(0.0, stop_distance)
			nearest_zone_id = StringName((data as Dictionary).get("id", (data as Dictionary).get("crossing_id", &"")))
	# Clearing an occupied railway conflict zone outranks pedestrian yielding.
	# The physical/player obstruction contract remains intact in the caller.
	if must_clear_rail_crossing:
		unrestricted.must_clear_rail_crossing = true
		return unrestricted
	if nearest_stop_distance == INF:
		return unrestricted
	return {
		"target_speed": sqrt(2.0 * _lane_braking_rate() * nearest_stop_distance),
		"allowed_advance": nearest_stop_distance,
		"zone_id": nearest_zone_id,
		"must_clear_rail_crossing": false,
	}


func _control_zone_curve_offset(path: Path2D, zone: Node, world_position: Vector2) -> float:
	# Project static crossings onto a lane once, shared by all its vehicles.
	# Long avenues contain thousands of baked curve segments; scanning each
	# one for every car on every frame dominated traffic CPU time.
	var cache: Dictionary = path.get_meta("traffic_control_projections", {})
	var curve_id := path.curve.get_instance_id()
	if int(cache.get("curve_id", 0)) != curve_id:
		var entries := {}
		cache = {"curve_id": curve_id, "transform": path.global_transform, "entries": entries}
		path.curve.changed.connect(func(): entries.clear())
		path.set_meta("traffic_control_projections", cache)
	if cache.transform != path.global_transform:
		cache.entries.clear()
		cache.transform = path.global_transform
	var key := zone.get_instance_id()
	var entry: Dictionary = cache.entries.get(key, {})
	if entry.is_empty() or entry.position != world_position:
		entry = {"position": world_position, "offset": path.curve.get_closest_offset(path.to_local(world_position))}
		cache.entries[key] = entry
	return float(entry.offset)

func _inside_rail_escape_envelope(data: Dictionary) -> bool:
	var center: Vector2 = data.get("position", Vector2.ZERO)
	var tangent: Vector2 = data.get("road_tangent", Vector2.RIGHT)
	if tangent.is_zero_approx():
		tangent = Vector2.RIGHT
	tangent = tangent.normalized()
	var relative := global_position - center
	var along := relative.dot(tangent)
	var lateral := absf(relative.dot(tangent.orthogonal()))
	var gate_geometry: Dictionary = data.get("gate_geometry", {})
	var gate_distance := float(gate_geometry.get("gate_offset", 0.0))
	var longitudinal_limit := gate_distance + target_length * 0.5 + 18.0
	var lateral_limit := float(data.get("road_width", 96.0)) * 0.5 + 8.0
	return absf(along) <= longitudinal_limit and lateral <= lateral_limit


func _open_lane_end_motion(path: Path2D, lane_follow: PathFollow2D, controller: Node) -> Dictionary:
	var lane_loops := bool(path.get_meta("traffic_lane_loop", lane_follow.loop)) and lane_follow.loop
	if lane_loops or bool(path.get_meta("traffic_turn_connector", false)):
		return {"target_speed": INF, "allowed_advance": INF}
	if controller != null and controller.has_method("has_lane_transition"):
		if bool(controller.call("has_lane_transition", path)):
			return {"target_speed": INF, "allowed_advance": INF}
	var remaining := maxf(0.0, path.curve.get_baked_length() - lane_follow.progress)
	return {
		"target_speed": sqrt(2.0 * _lane_braking_rate() * remaining),
		"allowed_advance": remaining,
	}


func _get_junction_traffic_controller() -> Node:
	if is_instance_valid(_junction_traffic_controller):
		return _junction_traffic_controller
	for candidate in get_tree().get_nodes_in_group("junction_traffic_controller"):
		if candidate.has_method("evaluate_lane_motion"):
			_junction_traffic_controller = candidate
			return candidate
	return null

func _must_stop_at_managed_signal(lane_follow: PathFollow2D) -> bool:
	var path := lane_follow.get_parent() as Path2D
	if path == null:
		return false
	var intersection_id := StringName(path.get_meta("traffic_intersection_id", &""))
	if intersection_id.is_empty():
		return false
	var manager := get_node_or_null("/root/TrafficLightManager")
	if manager == null or not manager.has_method("should_stop_vehicle"):
		return false
	var forward := global_transform.x.normalized()
	var axis := String(path.get_meta("traffic_intersection_axis", "AUTO"))
	if axis == "AUTO":
		axis = "EW" if absf(forward.x) >= absf(forward.y) else "NS"
	var front_probe := global_position + forward * target_length * 0.42
	return manager.should_stop_vehicle(
		intersection_id,
		front_probe,
		axis,
		forward,
		maxf(72.0, speed * 0.72)
	)

func _on_pedestrian_hitbox_body_entered(body: Node) -> void:
	if body == null or body == self or body == _driver or (is_driven_by_player and body.is_in_group("player")):
		return # Nunca atropelar ou causar dano ao próprio motorista ao entrar ou dirigir!
	if not is_broken and not body.is_in_group("ambient_traffic") and not body.is_in_group("vehicle"):
		var cur_speed := 0.0
		if is_driven_by_player or _detached_from_lane:
			cur_speed = velocity.length()
		elif is_moving_on_lane:
			cur_speed = _lane_motion_speed
		else:
			cur_speed = 0.0
			
		var impact_vel = velocity if velocity.length() > 10.0 else global_transform.x * cur_speed
		preload("res://guns/combat/VehiclePersonImpact.gd").hit(self, body, impact_vel)
		if not preload("res://guns/combat/VehiclePersonImpact.gd").is_person(body) and cur_speed > (35.0 if active_archetype_id == "port_forklift" else 85.0) and body.has_method("take_damage"):
			body.take_damage(100, is_driven_by_player)


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

func puncture_tires() -> void:
	if has_puncture_proof_tires or has_punctured_tires: return
	has_punctured_tires = true
	_ensure_puncture_vfx()
	if rim_sparks: rim_sparks.emitting = true
	if flat_smoke: flat_smoke.emitting = true
	max_speed *= 0.45
	acceleration *= 0.50
	turn_speed *= 0.70
	drift_factor = 0.40

func _trigger_nos_purge() -> void:
	_ensure_nos_purge()
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
	_ensure_backfire()
	if backfire_emitter: backfire_emitter.restart()
	var p := AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_exhaust_backfire_stream()
	p.volume_db = -6.0
	p.max_distance = 450.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _trigger_side_exhaust_burn(_delta: float) -> void:
	for body in get_tree().get_nodes_in_group("damageable"):
		if is_instance_valid(body) and body != self and body != _driver:
			var d = global_position.distance_to(body.global_position)
			if d < 55.0:
				var local_pos = transform.basis_xform_inv(body.global_position - global_position)
				if absf(local_pos.y) > 14.0 and absf(local_pos.x) < 28.0:
					if body.has_method("take_damage"):
						body.take_damage(2)

static var _damage_particle: Texture2D
static func _soft_damage_particle() -> Texture2D:
	if _damage_particle != null: return _damage_particle
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var radius := Vector2(x-15.5,y-15.5).length()/15.5
			image.set_pixel(x,y,Color(1,1,1,pow(maxf(0,1-radius),2)))
	_damage_particle = ImageTexture.create_from_image(image)
	return _damage_particle
