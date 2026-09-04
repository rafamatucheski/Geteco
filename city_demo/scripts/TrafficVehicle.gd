class_name DemoTrafficVehicle
extends CharacterBody2D

const VEHICLE_ATLAS: Texture2D = preload("res://city_demo/art/vehicle-atlas.png")
const VEHICLE_DOOR_VISUAL := preload("res://VehicleDoorVisual.gd")

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

@onready var visual: Sprite2D = $Visual
@onready var collision: CollisionShape2D = $Collision
@onready var camera: Camera2D = $Camera
@onready var pedestrian_hitbox: Area2D = $PedestrianHitbox

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
var bloody_tires_timer: float = 0.0
var flame_particles: CPUParticles2D

# === Upgrades & Tuning (Fast & Furious Style) ===
var has_nitro: bool = true
var nitro_amount: float = 100.0
var nitro_max: float = 100.0
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

func _ready() -> void:
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
	$PedestrianHitbox/Collision.shape = hit_shape
	$PedestrianHitbox.collision_mask = 5
	
	# Câmera dinâmica
	var dyn_cam = load("res://DynamicCamera.gd")
	if dyn_cam and camera:
		camera.set_script(dyn_cam)
		camera.set_process(true)
		
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
	
	# === VFX: Marcas de Derrapagem ===
	skid_line = Line2D.new()
	skid_line.width = 4.0
	skid_line.default_color = Color(0.1, 0.1, 0.1, 0.5)
	skid_line.top_level = true
	add_child(skid_line)
	
	# === VFX: Fumaça de Dano ===
	smoke_emitter = CPUParticles2D.new()
	smoke_emitter.emitting = false
	smoke_emitter.amount = 30
	smoke_emitter.lifetime = 1.0
	smoke_emitter.gravity = Vector2(0, -98)
	smoke_emitter.scale_amount_min = 4.0
	smoke_emitter.scale_amount_max = 10.0
	smoke_emitter.color = Color(0.2, 0.2, 0.2, 0.8)
	add_child(smoke_emitter)
	
	# === VFX: Faíscas de Batida ===
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
	
	# === VFX: Chamas / Fogo ===
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
	
	# === Setup de Áudio ===
	# 1. Buzina
	horn_audio = AudioStreamPlayer2D.new()
	horn_audio.stream = ProceduralAudio.get_horn_stream()
	horn_audio.max_distance = 500.0
	horn_audio.volume_db = -20.0
	add_child(horn_audio)
	
	# 2. Sirene (Hook reservado)
	siren_audio = AudioStreamPlayer2D.new()
	siren_audio.stream = ProceduralAudio.get_siren_stream()
	siren_audio.max_distance = 800.0
	siren_audio.volume_db = -4.0
	add_child(siren_audio)
	
	alarm_audio = AudioStreamPlayer2D.new()
	alarm_audio.stream = ProceduralAudio.get_police_alarm_stream()
	alarm_audio.max_distance = 1000.0
	alarm_audio.volume_db = 2.0
	add_child(alarm_audio)
	
	# 3. Motor (toca apenas quando o jogador assume o volante)
	engine_audio = AudioStreamPlayer2D.new()
	engine_audio.stream = ProceduralAudio.get_engine_stream()
	engine_audio.max_distance = 600.0
	engine_audio.attenuation = 1.8
	engine_audio.volume_db = -16.0
	add_child(engine_audio)
	
	# 4. Derrapagem
	skid_audio = AudioStreamPlayer2D.new()
	skid_audio.stream = ProceduralAudio.get_skid_stream()
	skid_audio.max_distance = 500.0
	skid_audio.volume_db = -16.0
	add_child(skid_audio)
	
	# 5. Rádio
	radio_audio = AudioStreamPlayer2D.new()
	radio_audio.max_distance = 500.0
	radio_audio.volume_db = -18.0
	add_child(radio_audio)
	radio_tracks = ProceduralAudio.get_radio_stations()
	
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
	nitro_emitter.scale_amount_min = 2.5
	nitro_emitter.scale_amount_max = 6.0
	nitro_emitter.color = Color("#00cec9") # Chamas azuis de Nitro NOS
	add_child(nitro_emitter)
	
	# Purga de Nitro Lateral/Capô (NOS Purge)
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

	# Backfire de Escapamento
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

	# Faíscas e fumaça de pneu furado
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

	flat_smoke = CPUParticles2D.new()
	flat_smoke.emitting = false
	flat_smoke.amount = 20
	flat_smoke.lifetime = 0.5
	flat_smoke.gravity = Vector2(0, -60)
	flat_smoke.color = Color(0.2, 0.2, 0.2, 0.7)
	add_child(flat_smoke)
	
	_setup_headlight()

var is_night_or_storm: bool = false

func set_headlights(dark_state: bool) -> void:
	is_night_or_storm = dark_state
	if headlight:
		headlight.visible = (is_night_or_storm or is_driven_by_player) and not is_broken

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
	headlight.visible = (is_night_or_storm or is_driven_by_player) and not is_broken
	add_child(headlight)

func honk_horn():
	if is_broken: return
	if horn_audio and not horn_audio.playing:
		horn_audio.pitch_scale = randf_range(0.92, 1.08)
		horn_audio.play()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	health = maxi(0, health - amount)
	if health < 75:
		visual.modulate = visual.modulate.lerp(Color(0.65, 0.65, 0.65), 0.4)
	if health < 50:
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.5, 0.5, 0.5, 0.8)
	if health <= 25:
		visual.modulate = Color(0.3, 0.3, 0.3)
		smoke_emitter.color = Color(0.1, 0.1, 0.1, 0.95)
		smoke_emitter.amount = 60
	if health == 0 and not is_broken:
		is_broken = true
		max_speed = 0.0
		if engine_audio: engine_audio.stop()
		_start_combustion_countdown()
		_dispatch_fire_truck()

var is_exploding: bool = false
var is_exploded: bool = false

func _start_combustion_countdown() -> void:
	if is_exploding or is_exploded: return
	is_exploding = true
	if flame_particles: flame_particles.emitting = true
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

func _apply_crash_deformation(impact_normal: Vector2, impact_force: float, hit_world_pos: Vector2 = Vector2.ZERO) -> void:
	if visual == null: return
	_ensure_dents_container()
	
	var local_norm = transform.basis_xform_inv(impact_normal)
	var factor = clampf(impact_force / 420.0, 0.05, 0.28)
	
	# O carro NUNCA estica nem diminui: preserva proporção e escala rígidas
	visual.scale = Vector2(uniform_scale, uniform_scale)
	visual.position = Vector2.ZERO
	visual.skew = 0.0
	
	# Escurecimento sutil (marcas de arranhão e fuligem na lataria)
	visual.modulate = visual.modulate.lerp(Color(0.60, 0.60, 0.62), 0.06 * (factor / 0.28))
	
	if hit_world_pos != Vector2.ZERO and dents_container:
		var local_hit: Vector2 = to_local(hit_world_pos)
		local_hit.x = clampf(local_hit.x, -36.0, 36.0)
		local_hit.y = clampf(local_hit.y, -16.0, 16.0)
		_spawn_dent_decal(local_hit, -local_norm, factor)
		
	var crumple_player = AudioStreamPlayer2D.new()
	crumple_player.stream = ProceduralAudio.get_metal_crumple_stream()
	crumple_player.volume_db = -10.0
	crumple_player.pitch_scale = randf_range(0.85, 1.15)
	crumple_player.max_distance = 500.0
	add_child(crumple_player)
	crumple_player.play()
	crumple_player.finished.connect(crumple_player.queue_free)
	
	_spawn_flying_debris(global_position, impact_normal)

func _spawn_dent_decal(local_pos: Vector2, dir: Vector2, strength: float) -> void:
	if dents_container == null: return
	if dents_container.get_child_count() > 8:
		dents_container.get_child(0).queue_free()
		
	var dent := Polygon2D.new()
	var w: float = randf_range(8.0, 16.0) * (1.0 + strength)
	var h: float = randf_range(4.0, 10.0) * (1.0 + strength)
	dent.polygon = PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.3),
		Vector2(0, -h * 0.6),
		Vector2(w * 0.5, -h * 0.2),
		Vector2(w * 0.4, h * 0.4),
		Vector2(-w * 0.3, h * 0.5)
	])
	dent.color = Color(0.12, 0.12, 0.16, 0.85)
	dent.position = local_pos
	dent.rotation = dir.angle() + randf_range(-0.3, 0.3)
	
	var scratch := Line2D.new()
	scratch.points = PackedVector2Array([
		Vector2(-w * 0.4, randf_range(-2, 2)),
		Vector2(w * 0.4, randf_range(-2, 2))
	])
	scratch.width = 1.8
	scratch.default_color = Color(0.85, 0.85, 0.90, 0.85)
	dent.add_child(scratch)
	
	dents_container.add_child(dent)

func _clear_all_dents() -> void:
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
	
	# Cor e Textura Especial
	if spec.has("texture") and String(spec["texture"]) != "":
		visual.texture = load(spec["texture"])
		visual.region_enabled = false
		visual.centered = true
		visual.rotation = PI * 0.5
		uniform_scale = target_length / 480.0
		visual.scale = Vector2(uniform_scale, uniform_scale)
		visual.modulate = Color.WHITE
		if archetype_id == "police_cruiser":
			is_police_vehicle = true
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
		
	# Atualiza dimensões do colisor
	var rect_shape := RectangleShape2D.new()
	var col_width = 34.0 if spec.has("texture") else maxf(24.0, crop.size.x * uniform_scale * 0.72)
	rect_shape.size = Vector2(target_length * 0.78, col_width)
	if collision: collision.shape = rect_shape
	
	# Atualiza adereços no teto/lataria (props)
	_build_roof_prop(String(spec.get("roof_prop", "none")))

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
	if new_color != Color.TRANSPARENT:
		if visual: visual.modulate = new_color
	else:
		if visual: visual.modulate = VehicleCatalog.get_random_color(active_archetype_id)

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

func enter_vehicle(player_body: CharacterBody2D) -> void:
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
	is_driven_by_player = true
	velocity = Vector2.ZERO
	speed = 0.0
	
	# Desativa colisões do jogador para evitar impulsos violentos
	for col in player_body.find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", true)
	player_body.velocity = Vector2.ZERO
	player_body.global_position = global_position
	
	_animate_car_door()
	
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
	camera.enabled = true
	camera.set_process(true)
	camera.set_physics_process(true)
	camera.make_current()

	if headlight: headlight.visible = true
	if engine_audio:
		engine_audio.volume_db = -12.0
		engine_audio.play()
	if radio_audio and not radio_tracks.is_empty():
		radio_audio.stream = radio_tracks[radio_index]
		radio_audio.play()

	# Alarme e Alerta Policial se o jogador roubar uma viatura da PM
	if is_police_vehicle and not was_stolen_from_police:
		was_stolen_from_police = true
		_trigger_police_theft()

func _trigger_police_theft() -> void:
	# 1. Alarme sonoro contínuo
	is_alarm_active = true
	alarm_timer = 20.0
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
func _animate_car_door() -> void:
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
	_door_visual.play(body_color)

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

func exit_vehicle() -> void:
	if not is_driven_by_player:
		return
	is_driven_by_player = false
	velocity = Vector2.ZERO
	speed = 0.0
	if headlight: headlight.visible = false
	if engine_audio:
		engine_audio.volume_db = -22.0
	if radio_audio: radio_audio.stop()
	if skid_audio: skid_audio.stop()

	_animate_car_door()

	if is_instance_valid(_driver):
		_driver.global_position = _get_safe_exit_position()
		_driver.velocity = Vector2.ZERO
		for col in _driver.find_children("", "CollisionShape2D", true, false):
			col.set_deferred("disabled", false)
		_driver.show()
		_driver.set_physics_process(true)
		var player_camera := _driver.get_node_or_null("Camera") as Camera2D
		if player_camera != null:
			player_camera.make_current()
	_driver = null

func _physics_process(delta: float) -> void:
	# Sempre permite ao jogador sair com F/Enter mesmo que o carro esteja em chamas ou quebrado
	if is_driven_by_player:
		if Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER) or (InputMap.has_action("interact") and Input.is_action_just_pressed("interact")):
			exit_vehicle()
			return

	if is_broken:
		velocity = velocity.move_toward(Vector2.ZERO, braking * delta)
		if _detached_from_lane:
			move_and_slide()
		return
	if not is_driven_by_player:
		if _detached_from_lane:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
			move_and_slide()
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
		if Input.is_key_pressed(KEY_H) or (InputMap.has_action("siren_toggle") and Input.is_action_just_pressed("siren_toggle")):
			toggle_siren()

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
	
	# Derrapagem e Drift
	var lateral_velocity = velocity.project(transform.y)
	if lateral_velocity.length() > 90.0:
		if not is_skidding:
			is_skidding = true
			skid_line.clear_points()
		if skid_line.get_point_count() == 0 or skid_line.get_point_position(skid_line.get_point_count() - 1).distance_to(global_position) > 6.0:
			skid_line.add_point(global_position)
		if skid_line.get_point_count() > 30:
			skid_line.remove_point(0)
		velocity = velocity.lerp(velocity.project(transform.x), 1.0 - drift_factor)
	else:
		is_skidding = false
		if skid_line.get_point_count() > 0 and bloody_tires_timer <= 0.0:
			skid_line.clear_points()
			
	_update_skid_audio()

	if velocity.length() > 8.0:
		var current_turn := steering * turn_speed * delta
		if velocity.dot(transform.x) < 0.0:
			current_turn *= -1.0
		rotation += current_turn
	var forward := transform.x
	var wants_nitro := (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE) or (InputMap.has_action("handbrake") and Input.is_action_pressed("handbrake"))) and throttle > 0.0
	
	if has_nitro and wants_nitro and nitro_amount > 0.0:
		if not is_boosting:
			is_boosting = true
			if nitro_emitter: nitro_emitter.emitting = true
			if not nitro_audio.playing: nitro_audio.play()
			_do_screen_shake(0.08)
			
		nitro_amount = maxf(0.0, nitro_amount - 28.0 * delta)
		var nitro_accel: float = acceleration * 1.65
		var nitro_max_spd: float = max_speed * 1.35
		velocity = (velocity + forward * throttle * nitro_accel * delta).limit_length(nitro_max_spd)
		
		# Habilidade Especial do Carro do Don Hector (Cobra V8): Lança-chamas lateral de escapamento
		if String(active_archetype_id) == "cobra_v8":
			_trigger_side_exhaust_burn(delta)
	else:
		if is_boosting:
			is_boosting = false
			if nitro_emitter: nitro_emitter.emitting = false
			if nitro_audio.playing: nitro_audio.stop()
			
			# Válvula de Alívio Turbo Blow-off (Tchuu-stututu)
			var blowoff_p := AudioStreamPlayer2D.new()
			blowoff_p.stream = ProceduralAudio.get_turbo_blowoff_stream()
			blowoff_p.volume_db = -8.0
			blowoff_p.max_distance = 500.0
			add_child(blowoff_p)
			blowoff_p.play()
			blowoff_p.finished.connect(blowoff_p.queue_free)
			
		nitro_amount = minf(nitro_max, nitro_amount + 6.0 * delta)
		
		if not is_zero_approx(throttle):
			if (throttle > 0.0 and velocity.dot(forward) < -8.0) or (throttle < 0.0 and velocity.dot(forward) > 8.0):
				velocity = velocity.move_toward(Vector2.ZERO, braking * delta)
			else:
				velocity = (velocity + forward * throttle * acceleration * delta).limit_length(max_speed)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	var prev_velocity = velocity
	move_and_slide()
	
	# Pitch dinâmico do motor
	if engine_audio and engine_audio.stream:
		if not is_broken:
			var speed_ratio = clampf(velocity.length() / maxf(1.0, max_speed), 0.0, 1.0)
			engine_audio.pitch_scale = lerp(0.82, 1.65, speed_ratio)
			if is_driven_by_player:
				engine_audio.volume_db = lerp(-17.0, -11.0, speed_ratio)
				engine_audio.max_distance = 600.0
			else:
				engine_audio.volume_db = lerp(-22.0, -16.0, speed_ratio)
				engine_audio.max_distance = 450.0
			if not engine_audio.playing:
				engine_audio.play()
		else:
			if engine_audio.playing:
				engine_audio.stop()
			
	# Colisões e impactos
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var body = col.get_collider()
		var normal_impact = absf(prev_velocity.dot(col.get_normal()))
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
			
		if impact_speed > 160.0:
			take_damage(int(impact_speed * 0.06))

	# Gerencia marcas de pneu sangrentas
	if bloody_tires_timer > 0.0:
		bloody_tires_timer -= delta
		if velocity.length() > 40.0:
			skid_line.add_point(global_position)
			if skid_line.get_point_count() > 60:
				skid_line.remove_point(0)
		if bloody_tires_timer <= 0.0:
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
	if not skid_audio or not skid_audio.stream: return
	if is_skidding and not skid_audio.playing:
		skid_audio.play()
	elif not is_skidding and skid_audio.playing:
		skid_audio.stop()

var block_wait_timer: float = 0.0
var is_moving_on_lane: bool = false
var _lane_motion_speed := 0.0
var _lane_motion_initialized := false
var _junction_traffic_controller: Node = null
var _last_lane_motion_contract: Dictionary = {}

func _process(delta: float) -> void:
	if is_broken or is_driven_by_player:
		return
	advance_on_lane(delta)

func advance_on_lane(delta: float) -> void:
	is_moving_on_lane = false
	var lane_follow := get_parent() as PathFollow2D
	if lane_follow == null:
		return
	var path := lane_follow.get_parent() as Path2D
	if path == null or path.curve == null:
		return
	var controller := _get_junction_traffic_controller()
	if controller != null and controller.has_method("complete_lane_transition"):
		if bool(controller.call("complete_lane_transition", self, path, lane_follow)):
			return
	if not _lane_motion_initialized:
		_lane_motion_speed = speed
		_lane_motion_initialized = true

	var obstruction := _get_lane_obstruction(lane_follow)
	var hard_blocked: bool = obstruction.hard
	var yield_blocked: bool = obstruction.yield
	var target_lane_speed := speed
	var maximum_advance := INF
	var spacing := _lane_spacing_motion(lane_follow)
	target_lane_speed = minf(target_lane_speed, float(spacing.target_speed))
	maximum_advance = minf(maximum_advance, float(spacing.allowed_advance))
	var safety_zone_motion := _traffic_control_zone_motion(path, lane_follow)
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
	var rate := _lane_acceleration_rate() if target_lane_speed > _lane_motion_speed else _lane_braking_rate()
	_lane_motion_speed = move_toward(_lane_motion_speed, maxf(0.0, target_lane_speed), rate * delta)
	var desired_advance := maxf(0.0, (previous_speed + _lane_motion_speed) * 0.5 * delta)
	var actual_advance := minf(desired_advance, maximum_advance)
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

func _get_lane_obstruction(lane_follow: PathFollow2D) -> Dictionary:
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
		if collider.is_in_group("player") or collider.is_in_group("pedestrian") or collider.name == "Player":
			hard_blocked = true
			continue
		if not collider.is_in_group("vehicle") or collider.is_in_group("parked_vehicle"):
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


func _traffic_control_zone_motion(path: Path2D, lane_follow: PathFollow2D) -> Dictionary:
	var unrestricted := {"target_speed": INF, "allowed_advance": INF, "zone_id": &""}
	if path == null or path.curve == null or not path.is_in_group("unified_traffic_lane"):
		return unrestricted
	var road_id := String(path.get_meta("traffic_road_id", ""))
	if road_id.is_empty():
		return unrestricted
	var route_length := path.curve.get_baked_length()
	var lane_loops := bool(path.get_meta("traffic_lane_loop", lane_follow.loop)) and lane_follow.loop
	var nearest_stop_distance := INF
	var nearest_zone_id: StringName = &""
	for zone in get_tree().get_nodes_in_group("traffic_control_zone"):
		if not zone.has_method("get_crossing_data") or not zone.has_method("should_stop_vehicle"):
			continue
		var data = zone.call("get_crossing_data")
		if not data is Dictionary or String((data as Dictionary).get("road_id", "")) != road_id:
			continue
		# Railway crossings expose a position-aware contract: an approaching car
		# must stop, while one which already passed its entry gate must keep its
		# escape lane and clear the track. Ordinary pedestrian crossings retain
		# their simpler global stop contract.
		var stop_required := bool(zone.call("should_stop_vehicle", self))
		if zone.has_method("should_stop_vehicle_at"):
			stop_required = bool(zone.call("should_stop_vehicle_at", global_position, self))
		if not stop_required:
			continue
		var world_position: Vector2 = (data as Dictionary).get("position", Vector2.ZERO)
		var curve_offset := path.curve.get_closest_offset(path.to_local(world_position))
		var distance_to_center := curve_offset - lane_follow.progress
		if lane_loops and distance_to_center < -0.5:
			distance_to_center += route_length
		elif not lane_loops and distance_to_center < -target_length * 0.5:
			continue
		# Once the vehicle center has entered a crossing it must clear it; stopping
		# on a zebra crossing or railway track is less safe than completing exit.
		if distance_to_center <= 0.0:
			continue
		var stop_distance := distance_to_center - target_length * 0.5 - 18.0
		if stop_distance < nearest_stop_distance:
			nearest_stop_distance = maxf(0.0, stop_distance)
			nearest_zone_id = StringName((data as Dictionary).get("id", (data as Dictionary).get("crossing_id", &"")))
	if nearest_stop_distance == INF:
		return unrestricted
	return {
		"target_speed": sqrt(2.0 * _lane_braking_rate() * nearest_stop_distance),
		"allowed_advance": nearest_stop_distance,
		"zone_id": nearest_zone_id,
	}


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


func _trigger_side_exhaust_burn(_delta: float) -> void:
	for body in get_tree().get_nodes_in_group("damageable"):
		if is_instance_valid(body) and body != self and body != _driver:
			var d = global_position.distance_to(body.global_position)
			if d < 55.0:
				var local_pos = transform.basis_xform_inv(body.global_position - global_position)
				if absf(local_pos.y) > 14.0 and absf(local_pos.x) < 28.0:
					if body.has_method("take_damage"):
						body.take_damage(2)
