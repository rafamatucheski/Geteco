class_name DemoTrafficVehicle
extends CharacterBody2D

const VEHICLE_ATLAS: Texture2D = preload("res://assets/art/vehicle-atlas.png")
const VEHICLE_DOOR_VISUAL := preload("res://VehicleDoorVisual.gd")
const MAX_LANE_ADVANCE_PER_FRAME := 14.0

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
@export var drift_factor: float = 0.9

var visual: Sprite2D
var collision: CollisionShape2D
var camera: Camera2D
var pedestrian_hitbox: Area2D

var is_driven_by_player := false
var _driver: CharacterBody2D
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
var alarm_timer: float = 0.0
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
	preload("res://VehicleMotionSafety.gd").configure(self)
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
	var hit_shape := RectangleShape2D.new()
	hit_shape.size = Vector2(target_length * 1.05, maxf(34.0, crop.size.x * uniform_scale * 0.95))
	var pedestrian_collision := pedestrian_hitbox.get_node("Collision") as CollisionShape2D
	pedestrian_collision.shape = hit_shape
	pedestrian_hitbox.collision_mask = 5
	
	# Câmera dinâmica (desativada por padrão em carros de tráfego ambiente)
	var dyn_cam = load("res://DynamicCamera.gd")
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
		var dyn_cam = load("res://DynamicCamera.gd")
		if dyn_cam:
			camera.set_script(dyn_cam)
	return camera

func _ensure_smoke_emitter() -> CPUParticles2D:
	if smoke_emitter == null:
		smoke_emitter = CPUParticles2D.new()
		smoke_emitter.emitting = false
		smoke_emitter.amount = 30
		smoke_emitter.lifetime = 1.0
		smoke_emitter.gravity = Vector2(0, -98)
		smoke_emitter.texture = _soft_damage_particle()
		smoke_emitter.scale_amount_min = 10.0 / 32.0
		smoke_emitter.scale_amount_max = 22.0 / 32.0
		smoke_emitter.color = Color(0.2, 0.2, 0.2, 0.8)
		add_child(smoke_emitter)
	return smoke_emitter

func _ensure_collision_particles() -> CPUParticles2D:
	if collision_particles == null:
		collision_particles = CPUParticles2D.new()
		collision_particles.emitting = false
		collision_particles.one_shot = true
		collision_particles.amount = 20
		collision_particles.lifetime = 0.6
		collision_particles.initial_velocity_min = 80.0
		collision_particles.initial_velocity_max = 250.0
		collision_particles.gravity = Vector2(0, 200)
		collision_particles.scale_amount_min = 2.0
		collision_particles.scale_amount_max = 5.0
		collision_particles.color = Color(0.85, 0.85, 0.85, 1.0)
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
		add_child(alarm_audio)
	return alarm_audio

func _ensure_engine_audio() -> AudioStreamPlayer2D:
	if engine_audio == null:
		engine_audio = AudioStreamPlayer2D.new()
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
	headlight.visible = active
	if second_headlight:
		second_headlight.visible = active

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
	headlight.position = Vector2(target_length * 0.45, 0.0)
	headlight.texture = HeadlightTextureGenerator.get_conical_headlight_texture()
	headlight.offset = Vector2(170.0, 0.0) # Projeta 340px para a frente do carro
	headlight.visible = (is_night_or_storm or is_driven_by_player) and not is_broken and (is_driven_by_player or _is_near_screen(260.0))
	add_child(headlight)

func honk_horn():
	if is_broken: return
	_ensure_horn_audio()
	if horn_audio and not horn_audio.playing:
		horn_audio.pitch_scale = randf_range(0.92, 1.08)
		horn_audio.play()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
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
			smoke_emitter.color = Color(0.1, 0.1, 0.1, 0.95)
			smoke_emitter.amount = 60
	if health == 0 and not is_broken:
		is_broken = true
		max_speed = 0.0
		if engine_audio: engine_audio.stop()
		_engine_sound.stop()
		_start_combustion_countdown()
		_dispatch_fire_truck()

var is_exploding: bool = false
var is_exploded: bool = false

func _start_combustion_countdown() -> void:
	if is_exploding or is_exploded: return
	is_exploding = true
	_ensure_flame_particles()
	if flame_particles: flame_particles.emitting = true
	_ensure_smoke_emitter()
	if smoke_emitter:
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.1, 0.1, 0.1, 0.95)
		smoke_emitter.amount = 65
	# O jogador NÃO é ejetado sumariamente aqui: ele tem 3.2s para reagir e pular com F/Enter!
		
	await get_tree().create_timer(3.2).timeout
	if not is_exploded and health <= 0:
		_explode()

func _explode() -> void:
	if is_exploded: return
	is_exploded = true
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	if headlight: headlight.visible = false
	
	# Se o jogador ainda estiver no veículo na detonação final, ele é ejetado e toma o dano da explosão
	if is_driven_by_player:
		var driver_ref = _driver
		exit_vehicle()
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
	
	# 2. Bola de fogo densa e expansiva
	var fireball := CPUParticles2D.new()
	fireball.global_position = global_position
	fireball.emitting = true
	fireball.one_shot = true
	fireball.explosiveness = 0.98
	fireball.amount = 75
	fireball.lifetime = 1.3
	fireball.spread = 180.0
	fireball.initial_velocity_min = 160.0
	fireball.initial_velocity_max = 420.0
	fireball.gravity = Vector2(0, 120)
	fireball.scale_amount_min = 6.0
	fireball.scale_amount_max = 16.0
	fireball.color = Color(1.0, 0.48, 0.08, 0.95)
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
	shrapnel.scale_amount_min = 3.0
	shrapnel.scale_amount_max = 6.0
	shrapnel.color = Color(1.0, 0.85, 0.3)
	get_parent().add_child(shrapnel)
	
	# 4. Clarão de Luz Instantâneo
	var flash_light := PointLight2D.new()
	flash_light.color = Color(1.0, 0.85, 0.5)
	flash_light.energy = 4.5
	var f_grad = Gradient.new()
	f_grad.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var f_tex = GradientTexture2D.new()
	f_tex.gradient = f_grad
	f_tex.width = 420
	f_tex.height = 420
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
	if visual:
		visual.modulate = Color(0.12, 0.12, 0.12)
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.position = Vector2.ZERO
		visual.skew = 0.0
	
	# 7. Screen Shake
	if is_driven_by_player:
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
	_fire_truck_dispatched = false
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	if smoke_emitter:
		smoke_emitter.color = Color(0.9, 0.9, 0.9, 0.5)
		smoke_emitter.amount = 35
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.8)
	tween.tween_callback(func():
		var parent = get_parent()
		if parent is PathFollow2D:
			parent.queue_free()
		else:
			queue_free()
	)

func _start_decay():
	await get_tree().create_timer(14.0).timeout
	if is_broken:
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 2.0)
		tween.tween_callback(func():
			var parent = get_parent()
			if parent is PathFollow2D:
				parent.queue_free()
			else:
				queue_free()
		)

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

func _apply_crash_deformation(impact_normal: Vector2, impact_force: float, hit_world_pos: Vector2 = Vector2.ZERO) -> void:
	if visual == null or impact_force < 80.0 or not hit_world_pos.is_finite(): return
	ensure_presentation()
	var now := Time.get_ticks_msec()
	if now - _last_crash_visual_ms < 500: return
	_last_crash_visual_ms = now
	# The native vehicle receives a bounded dent in its own mesh. Flat decals
	# cannot follow its projected sides and must never be layered on top.
	if is_3d_vehicle and is_instance_valid(body_model):
		var ppm := 74.0 / 4.46
		var hit := to_local(hit_world_pos) / ppm
		var inward := global_transform.basis_xform_inv(impact_normal)
		body_model.apply_impact(Vector3(hit.y,0.81,-hit.x),Vector3(inward.y,0,-inward.x),impact_force/ppm)
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_ensure_dents_container()
		_spawn_dent_decal(to_local(hit_world_pos),global_transform.basis_xform_inv(impact_normal),clampf(impact_force/420.0,0,1))
	visual.modulate = visual.modulate.lerp(Color(0.80,0.80,0.81),0.08)
	var crumple_player := AudioStreamPlayer2D.new()
	crumple_player.stream = ProceduralAudio.get_metal_crumple_stream()
	crumple_player.volume_db = -15.0
	crumple_player.bus = &"SFX"
	crumple_player.max_distance = 500.0
	add_child(crumple_player)
	crumple_player.play()
	crumple_player.finished.connect(crumple_player.queue_free)

func _spawn_dent_decal(local_pos: Vector2, dir: Vector2, strength: float) -> void:
	if dents_container == null or is_3d_vehicle: return
	var footprint := Vector2(54,24)
	if collision and collision.shape is RectangleShape2D: footprint = collision.shape.size
	preload("res://VehicleSurfaceWear2D.gd").add_scrape(dents_container,local_pos,dir,footprint,strength)

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
	var spec: Dictionary = VehicleCatalog.get_vehicle_spec(archetype_id)
	if spec.is_empty(): return
	
	vehicle_id = archetype_id
	display_name = spec.get("label", "Veículo")
	target_length = float(spec.get("target_length", 76.0))
	vehicle_mass = float(spec.get("mass", 1.0))
	max_speed = float(spec.get("max_speed", 490.0))
	acceleration = float(spec.get("acceleration", 880.0))
	braking = float(spec.get("braking", 1150.0))
	turn_speed = float(spec.get("turn_speed", 3.1))
	drift_factor = float(spec.get("drift_factor", 0.88))
	max_health = int(spec.get("durability", 100))
	health = max_health
	
	is_police_vehicle = String(spec.get("roof_prop", "")) == "police_lightbar"
	# Cor e Textura Especial
	if spec.has("model_class") and String(spec["model_class"]) != "":
		if defer_presentation and body_viewport == null:
			_pending_spec = spec.duplicate(true)
			_pending_color = VehicleCatalog.get_random_color(archetype_id) if custom_color == Color.TRANSPARENT else custom_color
			visual.modulate = _pending_color
			# O tamanho físico independe do momento em que a câmera solicita detalhe.
			var length := float(spec.get("target_length", 82.0))
			var width := float(spec.get("target_width", 34.0))
			var shape := RectangleShape2D.new()
			shape.size = Vector2(length * 0.82, maxf(28.0, width * 0.88))
			collision.shape = shape
			var hit := pedestrian_hitbox.get_node("Collision") as CollisionShape2D
			(hit.shape as RectangleShape2D).size = Vector2(length * 1.02, maxf(34.0, width * 1.02))
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
			crop = ModernTrafficFactory.VEHICLE_CROPS[posmod(c_idx, ModernTrafficFactory.VEHICLE_CROPS.size())]
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

func _setup_3d_model(spec: Dictionary, custom_color: Color = Color.TRANSPARENT) -> void:
	is_3d_vehicle = true
	var model_path: String = String(spec.get("model_class", ""))
	var model_res = load(model_path)
	if not model_res:
		return

	var t_len: float = float(spec.get("target_length", 82.0))
	var t_wid: float = float(spec.get("target_width", 34.0))
	var ppm: float = 74.0 / 4.46
	var cam_size: float = maxf(6.0, (t_len / ppm) * 1.25)
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
		preload("res://VehicleMeshBatcher.gd").batch_model(body_model)
		body_model.rotation.y = -PI * 0.5

		var view := Camera3D.new()
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

	if visual:
		visual.texture = body_viewport.get_texture()
		visual.region_enabled = false
		visual.centered = true
		uniform_scale = ppm * cam_size / float(v_size)
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.rotation = 0.0
		visual.modulate = Color.WHITE

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(t_len * 0.82, maxf(28.0, t_wid * 0.88))
	if collision: collision.shape = rect_shape
	if pedestrian_hitbox and pedestrian_hitbox.has_node("Collision"):
		var p_col = pedestrian_hitbox.get_node("Collision") as CollisionShape2D
		if p_col and p_col.shape is RectangleShape2D:
			(p_col.shape as RectangleShape2D).size = Vector2(t_len * 1.02, maxf(34.0, t_wid * 1.02))

var _body_render_clock := 0.0
var _body_render_visible := false
var body_render_requests := 0
var _last_render_heading := INF
var _last_render_steer := INF

func _update_3d_orientation(delta: float) -> void:
	if not is_3d_vehicle or body_model == null:
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
	if not is_driven_by_player and is_night_or_storm and not is_broken:
		if headlight and not headlight.visible: headlight.visible = true
		if second_headlight and not second_headlight.visible: second_headlight.visible = true
	if second_headlight != null and _lamp_mounts.size() >= 2:
		var view := body_viewport.get_camera_3d()
		if view:
			for i in 2:
				var light: PointLight2D = headlight if i == 0 else second_headlight
				var pixel := view.unproject_position(body_model.to_global(_lamp_mounts[i]))
				light.global_position = visual.to_global(pixel-Vector2(body_viewport.size)*0.5)
		second_headlight.visible = headlight.visible
	var signed_speed := velocity.dot(global_transform.x) if is_driven_by_player else (_lane_motion_speed if is_moving_on_lane else 0.0)
	var ppm := 74.0 / 4.46
	# Nem a faixa nem o jogador ao volante deste carro passam por um ângulo de
	# esterço: os dois giram `rotation` direto. O ângulo das rodas dianteiras sai
	# então da guinada real da carroceria, pelo modelo de bicicleta invertido.
	wheel_rig.update(delta, signed_speed / ppm, global_rotation)
	var interval := 1.0 / (60.0 if is_driven_by_player else 30.0)
	var steer_moved := absf(wheel_rig.steering_angle - _last_render_steer) > 0.004
	var moving_pose := absf(signed_speed)>0.1 or steer_moved or not is_equal_approx(_last_render_heading,global_rotation)
	if not _body_render_visible or (moving_pose and _body_render_clock >= interval):
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
	health = max_health
	is_broken = false
	damage_deformation_scale = Vector2(1.0, 1.0)
	damage_deformation_offset = Vector2.ZERO
	damage_skew = 0.0
	if visual:
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.position = Vector2.ZERO
		visual.skew = 0.0
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

func configure_as_parked() -> void:
	## A parked catalog vehicle keeps the current art, damage and enter/drive
	## systems, but has no imaginary driver and never searches for a PathFollow.
	_detached_from_lane = true
	is_driven_by_player = false
	speed = 0.0
	velocity = Vector2.ZERO
	set_process(false)
	if camera:
		camera.enabled = false
		camera.set_process(false)
		camera.set_physics_process(false)
	add_to_group("parked_vehicle")

var _entry_input_released := true
var _drive_input_armed := true
var _siren_key_down := false

func enter_vehicle(player_body: CharacterBody2D) -> void:
	ensure_presentation()
	if is_broken or is_driven_by_player or player_body == null:
		return
		
	# Ejeção dinâmica do motorista anterior se o carro estava em trânsito
	var was_occupied: bool = not _detached_from_lane
	if was_occupied:
		var driver_scene = load("res://CarjackedDriver.tscn")
		if driver_scene:
			var ejected_driver = driver_scene.instantiate() as CarjackedDriver
			var scene_target = get_tree().current_scene if get_tree().current_scene else get_parent()
			if scene_target:
				scene_target.add_child(ejected_driver)
				var ejection_pos = global_position - transform.y * 36.0 + transform.x * -12.0
				ejected_driver.setup(self, ejection_pos)

	_driver = player_body
	var approach := player_body.global_position
	var entry_side := -1.0 if to_local(approach).y <= 0 else 1.0
	var camera_view := preload("res://DynamicCamera.gd").capture_view(get_viewport())
	is_driven_by_player = true
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
	
	_animate_car_door(entry_side, 0.95 if entry_side > 0 else 0.6)
	
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
	preload("res://DynamicCamera.gd").handoff(camera, camera_view)

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
	if is_police_vehicle and not was_stolen_from_police:
		was_stolen_from_police = true
		_trigger_police_theft()

	_boarding = preload("res://VehicleBoarding.gd").new()
	add_child(_boarding)
	_boarding.begin(self, player_body, approach, entry_side)

func _trigger_police_theft() -> void:
	# 1. Alarme sonoro contínuo
	is_alarm_active = true
	alarm_timer = 20.0
	_ensure_alarm_audio()
	if alarm_audio:
		alarm_audio.play()
	
	# 2. Chama a polícia no WantedManager (+2 estrelas e despacho de reforço)
	var wanted = get_node_or_null("/root/WantedManager")
	if wanted and wanted.has_method("report_police_car_theft"):
		wanted.report_police_car_theft()
	elif wanted and wanted.has_method("report_crime"):
		wanted.report_crime(20)
		
	# 3. Notifica o ponto de prontidão da viatura
	if standby_source and is_instance_valid(standby_source) and standby_source.has_method("notify_stolen"):
		standby_source.notify_stolen()
		
	# 4. Notificação visual de urgência
	_show_theft_hud_notice("🚨 ALARME DISPARADO! VIATURA DA PM ROUBADA! 🚨")

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
	if not is_driven_by_player:
		return
	if is_instance_valid(_boarding): _boarding.cancel()
	var camera_view := preload("res://DynamicCamera.gd").capture_view(get_viewport())
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

	var exit_position := _get_safe_exit_position()
	_animate_car_door(-1.0 if to_local(exit_position).y <= 0 else 1.0)

	if is_instance_valid(_driver):
		remove_collision_exception_with(_driver)
		_driver.remove_collision_exception_with(self)
		_driver.global_position = exit_position
		_driver.velocity = Vector2.ZERO
		for col in _driver.find_children("", "CollisionShape2D", true, false):
			col.set_deferred("disabled", false)
		_driver.show()
		_driver.set_physics_process(true)
		var player_camera := _driver.get_node_or_null("Camera") as Camera2D
		if player_camera != null:
			preload("res://DynamicCamera.gd").handoff(player_camera, camera_view)
	_driver = null

func _physics_process(delta: float) -> void:
	preload("res://VehicleMotionSafety.gd").sanitize(self)
	has_nitro = false
	is_boosting = false
	if is_instance_valid(_boarding) and _boarding.active:
		velocity = Vector2.ZERO
		return
	if is_3d_vehicle and not is_processing():
		_update_3d_orientation(delta)

	# Sempre permite ao jogador sair com F/Enter mesmo que o carro esteja em chamas ou quebrado
	if is_driven_by_player:
		if is_instance_valid(_driver): _driver.global_position = global_position
		var exit_pressed := Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER) or Input.is_action_pressed("interact")
		if not exit_pressed: _entry_input_released = true
		if _entry_input_released and exit_pressed:
			exit_vehicle()
			return

	if is_broken:
		velocity = velocity.move_toward(Vector2.ZERO, braking * delta)
		if _detached_from_lane:
			preload("res://VehicleMotionSafety.gd").move(self)
		return
	if not is_driven_by_player:
		if _detached_from_lane:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
			preload("res://VehicleMotionSafety.gd").move(self)
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
			alarm_timer -= delta
			if alarm_timer <= 0.0:
				is_alarm_active = false
				if alarm_audio and alarm_audio.playing:
					alarm_audio.stop()
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

	# Atualização do alarme ativo da viatura
	if is_alarm_active:
		alarm_timer -= delta
		if alarm_timer <= 0.0:
			is_alarm_active = false
			if alarm_audio and alarm_audio.playing:
				alarm_audio.stop()
				
	if is_alarm_active or is_siren_on:
		_update_police_strobes(delta)
	else:
		_turn_off_police_strobes()
	
	# Troca de rádio
	if Input.is_key_pressed(KEY_R) or (InputMap.has_action("radio_next") and Input.is_action_just_pressed("radio_next")):
		if not radio_tracks.is_empty():
			radio_index = (radio_index + 1) % radio_tracks.size()
			radio_audio.stream = radio_tracks[radio_index]
			radio_audio.play()

	# === Hit-stop ===
	if _hit_stop_frames > 0:
		_hit_stop_frames -= 1
		return

	var throttle := Input.get_axis("ui_down", "ui_up")
	var steering := Input.get_axis("ui_left", "ui_right")
	if not _drive_input_armed:
		_drive_input_armed = is_zero_approx(throttle) and is_zero_approx(steering)
		throttle = 0.0
		steering = 0.0
	
	# Derrapagem e Drift
	var lateral_velocity = velocity.project(transform.y)
	if lateral_velocity.length() > 90.0:
		_ensure_skid_line()
		if not is_skidding:
			is_skidding = true
			skid_line.clear_points()
		if skid_line.get_point_count() == 0 or skid_line.get_point_position(skid_line.get_point_count() - 1).distance_to(global_position) > 6.0:
			skid_line.add_point(global_position)
		if skid_line.get_point_count() > 30:
			skid_line.remove_point(0)
	else:
		is_skidding = false
		if skid_line and skid_line.get_point_count() > 0 and bloody_tires_timer <= 0.0:
			skid_line.clear_points()
			
	_update_skid_audio()

	var handbrake := Input.is_key_pressed(KEY_SPACE) or (InputMap.has_action("handbrake") and Input.is_action_pressed("handbrake"))
	velocity = preload("res://VehicleMotionSafety.gd").grip(velocity, global_rotation, drift_factor, delta, 0.0, handbrake)
	if handbrake: velocity = velocity.move_toward(Vector2.ZERO, braking*0.45*delta)
	var longitudinal := velocity.dot(transform.x)
	rotation += steering * turn_speed * clampf(longitudinal/150.0,-1.0,1.0) * delta
	var forward := transform.x
	if not is_zero_approx(throttle):
		if (throttle > 0.0 and velocity.dot(forward) < -8.0) or (throttle < 0.0 and velocity.dot(forward) > 8.0):
			velocity = velocity.move_toward(Vector2.ZERO, braking * delta)
		else:
			velocity = (velocity + forward * throttle * acceleration * _engine_sound.drive_force(velocity.length(), max_speed) * delta).limit_length(_engine_sound.road_top_speed(max_speed))
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	var prev_velocity = velocity
	preload("res://VehicleMotionSafety.gd").move(self)
	
	# Same cached family/RPM controller as personal cars; large vehicles keep diesel timbre.
	if engine_audio and not is_broken:
		_engine_sound.update(engine_audio, velocity.length(), _engine_sound.road_top_speed(max_speed), throttle, delta, active_archetype_id)
	elif engine_audio:
		engine_audio.stop()
		_engine_sound.stop()

	# Colisões e impactos
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var body = col.get_collider()
		var normal_impact = maxf(0.0, -prev_velocity.dot(col.get_normal()))
		var impact_speed = maxf(prev_velocity.length() - velocity.length(), normal_impact)
		
		# Atropelar pessoas no slide collision!
		if is_instance_valid(body) and body != self:
			if not (is_driven_by_player and body.is_in_group("player")) and body != _driver and not body.is_in_group("ambient_traffic") and not body.is_in_group("vehicle"):
				if prev_velocity.length() > 30.0:
					if body.has_method("get_run_over"):
						body.get_run_over(prev_velocity, is_driven_by_player)
						if is_driven_by_player:
							_activate_bloody_tires()
					elif body.has_method("take_damage"):
						body.take_damage(100, is_driven_by_player)
		
		# Se colidiu com outro carro, deforma o outro carro também!
		if is_instance_valid(body) and body != self and impact_speed > 35.0:
			if body.has_method("_apply_crash_deformation"):
				body._apply_crash_deformation(-col.get_normal(), impact_speed, col.get_position())
		
		if impact_speed > 35.0:
			_apply_crash_deformation(col.get_normal(), impact_speed, col.get_position())
			if is_driven_by_player:
				_do_screen_shake(clampf(impact_speed / 500.0, 0.05, 0.4))
				_hit_stop_frames = 3 if impact_speed > 250 else 2
			_ensure_collision_particles()
			collision_particles.global_position = col.get_position()
			collision_particles.restart()
			
			var crash_player = AudioStreamPlayer2D.new()
			crash_player.stream = ProceduralAudio.get_crash_stream()
			crash_player.pitch_scale = randf_range(0.85, 1.15)
			crash_player.volume_db = clampf(lerp(-18.0, -6.0, impact_speed / 500.0), -22.0, -4.0)
			crash_player.max_distance = 600.0
			add_child(crash_player)
			crash_player.play()
			crash_player.finished.connect(crash_player.queue_free)
			
		if impact_speed > 160.0 and Time.get_ticks_msec()-_last_collision_damage_ms > 650:
			_last_collision_damage_ms = Time.get_ticks_msec()
			take_damage(int(impact_speed * 0.06))

	# Gerencia marcas de pneu sangrentas
	if bloody_tires_timer > 0.0:
		bloody_tires_timer -= delta
		if velocity.length() > 40.0:
			_ensure_skid_line()
			skid_line.add_point(global_position)
			if skid_line.get_point_count() > 60:
				skid_line.remove_point(0)
		if bloody_tires_timer <= 0.0 and skid_line:
			skid_line.default_color = Color(0.1, 0.1, 0.1, 0.5)

func _activate_bloody_tires() -> void:
	bloody_tires_timer = 4.0
	if skid_line:
		skid_line.default_color = Color(0.72, 0.05, 0.05, 0.85)
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
var is_moving_on_lane: bool = false
var _lane_motion_speed := 0.0
var _lane_motion_initialized := false
var _junction_traffic_controller: Node = null
var _last_lane_motion_contract: Dictionary = {}
var _remote_lane_elapsed := 0.0
var remote_lane_steps := 0

func _process(delta: float) -> void:
	if is_3d_vehicle:
		_update_3d_orientation(delta)
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
		if headlight.visible != light_active:
			headlight.visible = light_active
			if second_headlight: second_headlight.visible = light_active
	if smoke_emitter and smoke_emitter.emitting != (health < 50 and on_screen):
		smoke_emitter.emitting = health < 50 and on_screen
	_remote_lane_elapsed += delta
	var interval := minf(0.1, MAX_LANE_ADVANCE_PER_FRAME * 0.8 / maxf(speed, 1.0))
	if not on_screen and _remote_lane_elapsed < interval:
		return
	var motion_delta := _remote_lane_elapsed
	_remote_lane_elapsed = 0.0
	if not on_screen: remote_lane_steps += 1
	advance_on_lane(motion_delta)

func advance_on_lane(delta: float) -> void:
	is_moving_on_lane = false
	var lane_follow := get_parent() as PathFollow2D
	if lane_follow == null:
		return
	var path := lane_follow.get_parent() as Path2D
	if path == null or path.curve == null:
		return
	var controller := _get_junction_traffic_controller()
	# The two regional lane ends are close enough for the city graph to infer
	# a U-turn. They are a continuous border, so the world owns this handoff.
	if bool(path.get_meta("continuous_border_end",false)) and lane_follow.progress > path.curve.get_baked_length()-180:
		controller = null
	if bool(path.get_meta("continuous_border_start",false)) and lane_follow.progress < 180:
		controller = null
	if controller != null and controller.has_method("complete_lane_transition"):
		if bool(controller.call("complete_lane_transition", self, path, lane_follow)):
			return
	if not _lane_motion_initialized:
		_lane_motion_speed = speed
		_lane_motion_initialized = true

	var safety_zone_motion := _traffic_control_zone_motion(path, lane_follow)
	var must_clear_rail_crossing := bool(safety_zone_motion.get("must_clear_rail_crossing", false))
	var obstruction := _get_lane_obstruction(lane_follow, must_clear_rail_crossing)
	var hard_blocked: bool = obstruction.hard
	var yield_blocked: bool = obstruction.yield
	var target_lane_speed := speed
	var maximum_advance := INF
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

	var end_motion := _open_lane_end_motion(path, lane_follow, controller)
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
	if actual_advance > 0.001:
		var next_offset := lane_follow.progress+actual_advance
		if lane_follow.loop: next_offset = fposmod(next_offset,path.curve.get_baked_length())
		var next_point := path.to_global(path.curve.sample_baked(next_offset, lane_follow.cubic_interp))
		var motion := next_point-global_position
		# Sweep the entire hull against vehicles before advancing the PathFollow.
		# Keep the existing kinematic test for map walls and walking actors.
		var sweep := PhysicsShapeQueryParameters2D.new()
		sweep.shape = collision.shape
		sweep.transform = collision.global_transform
		sweep.motion = motion
		sweep.margin = 0.1
		sweep.collision_mask = collision_mask & 2
		sweep.exclude = [get_rid()]
		var fractions := get_world_2d().direct_space_state.cast_motion(sweep)
		var contact := KinematicCollision2D.new()
		if fractions[0] < 1.0 or test_move(global_transform,motion,contact):
			# Recovery can point backwards at contact. Its absolute length must
			# never become forward lane progress, or queues creep through bodies.
			actual_advance *= fractions[0] if fractions[0] < 1.0 else 0.0
			_lane_motion_speed = 0.0
			hard_blocked = true
			target_lane_speed = 0.0
	if actual_advance > 0.001:
		lane_follow.progress += actual_advance
		is_moving_on_lane = true
	if controller != null and controller.has_method("complete_lane_transition"):
		controller.call("complete_lane_transition", self, path, lane_follow)

	var blocked := not is_moving_on_lane and target_lane_speed <= 0.1
	if blocked:
		block_wait_timer += delta
		if hard_blocked and block_wait_timer > 0.6 and randf() < 0.04:
			honk_horn()
	else:
		block_wait_timer = maxf(0.0, block_wait_timer - delta * 2.0)
	if visual:
		visual.position = visual.position.lerp(Vector2.ZERO, 8.0 * delta)

func _get_lane_obstruction(lane_follow: PathFollow2D, must_clear_rail_crossing: bool = false) -> Dictionary:
	# PathFollow traffic already has exact same-lane spacing below. Ray casts are
	# reserved for living actors and deterministic intersection yielding; parked
	# cars, kerbs and railway fences beside an authored route must not freeze it.
	var current_path := lane_follow.get_parent() as Path2D
	var hard_blocked := false
	var yield_blocked := false
	for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
		var ray := get_node_or_null(ray_name) as RayCast2D
		if ray == null or not ray.is_colliding():
			continue
		var collider := ray.get_collider() as Node
		if collider == null or collider == self:
			continue
		if collider.is_in_group("player") or collider.name == "Player":
			hard_blocked = true
			continue
		if collider.is_in_group("pedestrian"):
			# A vehicle already committed between closed railway gates must leave
			# the track instead of yielding in the conflict zone. Players remain
			# hard blockers; this exception is only for ambient pedestrian AI.
			if not must_clear_rail_crossing:
				hard_blocked = true
			continue
		if not collider.is_in_group("vehicle"):
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
	return {"hard": hard_blocked, "yield": yield_blocked}

func _lane_spacing_motion(lane_follow: PathFollow2D) -> Dictionary:
	var path := lane_follow.get_parent() as Path2D
	if path == null or path.curve == null:
		return {"target_speed": INF, "allowed_advance": INF}
	var route_length := path.curve.get_baked_length()
	if route_length <= 1.0:
		return {"target_speed": 0.0, "allowed_advance": 0.0}
	var lane_loops := bool(path.get_meta("traffic_lane_loop", lane_follow.loop)) and lane_follow.loop
	var target_speed_limit := INF
	var advance_limit := INF
	for sibling in path.get_children():
		if sibling == lane_follow or not sibling is PathFollow2D:
			continue
		var other_follow := sibling as PathFollow2D
		if other_follow.get_child_count() == 0 or not other_follow.get_child(0) is DemoTrafficVehicle:
			continue
		var other := other_follow.get_child(0) as DemoTrafficVehicle
		if other.is_driven_by_player:
			continue
		var center_gap := other_follow.progress - lane_follow.progress
		if lane_loops:
			center_gap = fposmod(center_gap, route_length)
		elif center_gap <= 0.0:
			continue
		if center_gap <= 0.5:
			continue
		var combined_half_lengths := (target_length + other.target_length) * 0.5
		var bumper_gap := center_gap - combined_half_lengths
		var minimum_clearance := maxf(14.0, maxf(target_length, other.target_length) * 0.18)
		var desired_clearance := minimum_clearance + _lane_motion_speed * 0.85
		advance_limit = minf(advance_limit, maxf(0.0, bumper_gap - minimum_clearance))
		if bumper_gap < desired_clearance:
			var follow_ratio := clampf(
				(bumper_gap - minimum_clearance) / maxf(1.0, desired_clearance - minimum_clearance),
				0.0,
				1.0
			)
			var other_speed: float = 0.0 if other.is_broken else other._lane_motion_speed
			target_speed_limit = minf(target_speed_limit, other_speed * follow_ratio)
	return {"target_speed": target_speed_limit, "allowed_advance": advance_limit}


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
		var data = zone.call("get_crossing_data")
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
			cur_speed = speed
		else:
			cur_speed = 0.0
			
		if cur_speed > 25.0: # Atropelamento responsivo com impacto
			var impact_vel = velocity if velocity.length() > 10.0 else global_transform.x * maxf(120.0, cur_speed)
			if body.has_method("get_run_over"):
				body.get_run_over(impact_vel, is_driven_by_player)
				if is_driven_by_player:
					_activate_bloody_tires()
			elif body.has_method("take_damage"):
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
