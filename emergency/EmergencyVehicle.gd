extends CharacterBody2D

const CREW_TRANSITION := preload("res://emergency/EmergencyCrewTransition.gd")
const CREW_DOOR_SCRIPT := preload("res://cars/VehicleDoorVisual.gd")
const LANE_ROUTER := preload("res://geodata/roads/EmergencyLaneRouter.gd")
var _lane_router := LANE_ROUTER.new()
var _hospital_arrival := preload("res://emergency/HospitalArrival.gd").new()
var _ambulance_approach := preload("res://emergency/AmbulanceApproach.gd").new()
var _traffic_passage := preload("res://emergency/AmbulanceTrafficPassage.gd").new()
var _depot_driveway := preload("res://emergency/DepotDriveway.gd").new()
var service_targets: Array[Node2D] = []
var _coroner_stage := ""
var _coroner_wait := 0.0

func enter_vehicle(actor: CharacterBody2D) -> void:
	preload("res://emergency/EmergencyVehicleTheft.gd").enter(self,actor)

func add_service_target(subject: Node2D) -> void:
	if is_instance_valid(subject) and not service_targets.has(subject):
		service_targets.append(subject)

func _advance_service_target() -> bool:
	service_targets = service_targets.filter(func(t): return is_instance_valid(t) and not t.is_queued_for_deletion() and not t.get_meta("service_complete", false) and t != target)
	if service_targets.is_empty(): return false
	target = service_targets.pop_front()
	is_acting = false
	is_returning_to_base = false
	deployed_firefighters = 0
	returned_firefighters = 0
	deployed_morticians = 0
	returned_morticians = 0
	scene_timeout = 0.0
	_lane_router.reset()
	return true

@export_enum("POLICE", "AMBULANCE", "FIRE", "CORONER") var type: int = 0

# Real vehicle contact complements anticipation/braking; floating motion never
# inherits the velocity of a PathFollow platform from another vehicle.
const EMERGENCY_COLLISION_MASK := 1 | 2 | 4

## Sem NavigationAgent2D, cada viatura mira o mesmo intercept_pos do alvo de
## forma independente -- convergindo todas no mesmo ponto/faixa, elas travam
## umas nas outras (cada uma tenta dar ré pra sair, sem coordenar com a
## vizinha, e a "ré" de uma empurra a próxima pro mesmo lugar). Esta repulsão
## dá um leve desvio de direção quando outra viatura policial está por perto,
## sem tocar no roteamento de faixa em si -- viaturas se espalham ao convergir
## em vez de empilhar.
const POLICE_SEPARATION_RADIUS := 85.0
const POLICE_SEPARATION_STRENGTH := 1.35

func _police_separation_dir() -> Vector2:
	if type != 0: return Vector2.ZERO
	var pool := get_node_or_null("/root/EmergencyPool")
	if pool == null or not pool.has_method("get_active_police"): return Vector2.ZERO
	var push := Vector2.ZERO
	for other in pool.get_active_police():
		if other == self or not is_instance_valid(other) or other.get("is_broken"): continue
		var offset: Vector2 = global_position - other.global_position
		var dist := offset.length()
		if dist >= POLICE_SEPARATION_RADIUS: continue
		if dist < 1.0:
			offset = Vector2.from_angle(randf() * TAU)
			dist = 1.0
		push += offset.normalized() * ((POLICE_SEPARATION_RADIUS - dist) / POLICE_SEPARATION_RADIUS)
	return push

var target: Node2D = null
var current_speed: float = 0.0
var _ram_damage_cooldown := 0.0
var max_target_speed: float = 240.0
var acceleration: float = 140.0
var health: int = 100
var is_broken := false
var is_acting := false
var officer_deployed := false
var police_variant := "patrol"
# Body identity survives dispatch tiers, pooling and theft.
var police_archetype := "police_cruiser"
var police_response_level := 1
var police_dispatch_serial := 0
var _police_crew: Array[Node2D] = []
var _police_available_seats := 2
var _police_crew_on_foot := false
var _police_recall_requested := false
var _police_boarded_ids := {}
var _vehicle_combat := preload("res://police/PoliceVehicleCombat.gd").new()

func configure_police_response(level: int, serial: int, elite_unit := false) -> void:
	police_response_level = clampi(level, 1, 6)
	police_dispatch_serial = serial
	if police_variant != "motorcycle":
		police_variant = ("tactical" if elite_unit else "patrol") if level >= 4 else ("interceptor" if level == 3 else "patrol")
	max_target_speed = 255.0 if police_variant in ["motorcycle", "interceptor"] else 235.0
	acceleration = 195.0 if police_variant == "motorcycle" else 165.0
	health = 70 if police_variant == "motorcycle" else (165 if police_variant == "tactical" else 115)
	if is_instance_valid(body_model):
		body_model.paint.albedo_color = Color("23364a") if police_variant == "tactical" else (Color("8eabc0") if police_variant == "interceptor" else Color("e5e9ed"))
		if body_viewport: body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func has_emergency_priority() -> bool:
	if not visible or is_broken or is_acting: return false
	return is_instance_valid(siren_audio) and siren_audio.playing

func _police_stop_radius() -> float:
	if is_instance_valid(target) and target.has_meta("police_stop_distance"):
		return float(target.get_meta("police_stop_distance"))
	return 140.0 + float(police_dispatch_serial % 3) * 36.0

signal returning_to_depot(vehicle: Node, depot_id: String)
signal arrived_at_depot(vehicle: Node, depot_id: String)

# Controle de Bombeiros e Retorno à Central
var deployed_firefighters: int = 0
var returned_firefighters: int = 0
var is_returning_to_base := false
var home_depot_id := ""
var home_return_position := Vector2.ZERO
var home_parking_position := Vector2.ZERO
var source_standby_id := ""
var _return_notified := false

var deployed_paramedics := 0
var returned_paramedics := 0

var deployed_morticians := 0
var returned_morticians := 0

# CORONER only: after picking up a body, a second leg to the cemetery
# before actually returning to base. See on_mortician_embarked() and the
# is_heading_to_cemetery branch in _physics_process().
var is_heading_to_cemetery := false
var _cemetery_target_position := Vector2.ZERO
var _coroner_carrying_body := false
## True while is_heading_to_cemetery is being reused for the short hop from
## the grave plot back out to the cemetery gate (road-adjacent), as opposed
## to the initial hop in from the incident to the grave plot itself.
var _cemetery_leaving := false

# A responder is only counted as returned after its boarding animation closes.
# This makes vehicles wait for their crew instead of leaving while people pop
# out of existence beside them.
var deployed_officers := 0
var returned_officers := 0
var _tactical_doors: Dictionary = {}
var visual_3d: Node
var is_3d_vehicle := true
var body_model: Node3D
var body_viewport: SubViewport

var visual: Sprite2D
var lights: ColorRect

var engine_audio: AudioStreamPlayer2D
var siren_audio: AudioStreamPlayer2D
var collision_particles: CPUParticles2D
var smoke_emitter: CPUParticles2D
var flame_particles: CPUParticles2D

func _ready():
	preload("res://cars/VehicleMotionSafety.gd").configure(self)
	z_as_relative = false
	z_index = 8
	_ensure_required_nodes()
	add_to_group("emergency_vehicle")
	add_to_group("vehicle")
	collision_layer = 2
	collision_mask = EMERGENCY_COLLISION_MASK
	var target_length = 74.0
	var uniform_scale = 1.0
	
	if type == 0: # POLICE (Interceptor)
		visual.texture = load("res://assets/art/police_car.png")
		visual.region_enabled = false
		target_length = 82.0
		uniform_scale = target_length / 480.0
		visual.modulate = Color.WHITE
		max_target_speed = 240.0
		acceleration = 160.0
	elif type == 1: # AMBULANCE (Resgate)
		visual.texture = load("res://assets/art/ambulance.png")
		visual.region_enabled = false
		target_length = 88.0
		uniform_scale = target_length / 520.0
		visual.modulate = Color.WHITE
		max_target_speed = 210.0
		acceleration = 130.0
	elif type == 2: # FIRE (Caminhão de Bombeiro - Pesado e Progressivo)
		visual.texture = load("res://assets/art/firetruck.png")
		visual.region_enabled = false
		target_length = 102.0
		uniform_scale = target_length / 580.0
		visual.modulate = Color.WHITE
		max_target_speed = 175.0
		acceleration = 100.0
	elif type == 3: # CORONER (Rabecão do IML / Necrotério)
		visual.texture = load("res://assets/art/ambulance.png")
		visual.region_enabled = false
		target_length = 88.0
		uniform_scale = target_length / 520.0
		visual.modulate = Color(0.15, 0.16, 0.19) # Chumbo/Preto funerário sóbrio
		max_target_speed = 195.0
		acceleration = 125.0
		
	visual.scale = Vector2(uniform_scale, uniform_scale)
	visual.rotation = PI * 0.5
	
	var collision = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var rect = RectangleShape2D.new()
	rect.size = Vector2(target_length * 0.85, 34.0)
	collision.shape = rect
	add_child(collision)
	
	# Giroflex visual
	var tween = create_tween().set_loops()
	if type == 2:
		tween.tween_callback(func(): lights.color = Color(1.0, 0.1, 0.1, 0.95)).set_delay(0.14)
		tween.tween_callback(func(): lights.color = Color(1.0, 1.0, 1.0, 0.95)).set_delay(0.14)
	elif type == 3:
		# Giroflex de advertência âmbar/púrpura do IML
		tween.tween_callback(func(): lights.color = Color(1.0, 0.70, 0.10, 0.95)).set_delay(0.20)
		tween.tween_callback(func(): lights.color = Color(0.70, 0.25, 0.95, 0.95)).set_delay(0.20)
	else:
		tween.tween_callback(func(): lights.color = Color(1.0, 0.0, 0.0, 0.9)).set_delay(0.16)
		tween.tween_callback(func(): lights.color = Color(0.0, 0.25, 1.0, 0.9)).set_delay(0.16)
	
	# Sirene (Volume balanceado e agradável)
	siren_audio = AudioStreamPlayer2D.new()
	siren_audio.stream = ProceduralAudio.get_siren_stream()
	siren_audio.max_distance = 1200.0
	siren_audio.volume_db = -10.0
	siren_audio.autoplay = false
	siren_audio.bus = "SFX"
	add_child(siren_audio)
	
	# Motor (Volume balanceado)
	engine_audio = AudioStreamPlayer2D.new()
	engine_audio.stream = ProceduralAudio.get_engine_stream()
	engine_audio.max_distance = 500.0
	engine_audio.volume_db = -26.0
	engine_audio.bus = "SFX"
	add_child(engine_audio)
	if visible and process_mode != Node.PROCESS_MODE_DISABLED:
		engine_audio.play()
	
	# Textura suave para partículas de fumaça e fogo (sem blocos quadrados)
	var particle_texture = _get_smooth_particle_texture()

	# Fumaça de dano volumétrica suave
	smoke_emitter = CPUParticles2D.new()
	smoke_emitter.texture = particle_texture
	smoke_emitter.emitting = false
	smoke_emitter.amount = 20
	smoke_emitter.lifetime = 0.9
	smoke_emitter.gravity = Vector2(0, -98)
	smoke_emitter.scale_amount_min = 0.5
	smoke_emitter.scale_amount_max = 1.6
	smoke_emitter.color = Color(0.25, 0.25, 0.28, 0.65)
	preload("res://guns/combat/VehicleDamageParticles.gd").configure(smoke_emitter, false)
	add_child(smoke_emitter)
	
	# Faíscas
	collision_particles = CPUParticles2D.new()
	collision_particles.emitting = false
	collision_particles.one_shot = true
	collision_particles.amount = 16
	collision_particles.lifetime = 0.5
	collision_particles.initial_velocity_min = 70.0
	collision_particles.initial_velocity_max = 140.0
	collision_particles.color = Color(1, 0.8, 0.2)
	collision_particles.texture = _get_smooth_particle_texture()
	add_child(collision_particles)
	
	_setup_headlight()
	# Unidades no pool só precisam do modelo quando forem despachadas.
	if visible:
		ensure_presentation()

func ensure_presentation() -> void:
	if visual_3d != null:
		return
	visual_3d = preload("res://emergency/EmergencyVehicleVisual3D.gd").new()
	add_child(visual_3d)
	visual_3d.configure(self, type)
	body_model = visual_3d.model
	body_viewport = visual_3d.viewport
	lights.self_modulate.a = 0.0

func _ensure_required_nodes() -> void:
	visual = get_node_or_null("Visual") as Sprite2D
	if visual == null:
		visual = Sprite2D.new()
		visual.name = "Visual"
		add_child(visual)
	lights = get_node_or_null("Lights") as ColorRect
	if lights == null:
		lights = ColorRect.new()
		lights.name = "Lights"
		lights.position = Vector2(-5.0, -2.0)
		lights.size = Vector2(10.0, 4.0)
		add_child(lights)

var headlight: PointLight2D
var is_night_or_storm: bool = false

static var _cached_particle_tex: Texture2D = null
static func _get_smooth_particle_texture() -> Texture2D:
	if _cached_particle_tex != null:
		return _cached_particle_tex
	var grad = Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_cached_particle_tex = tex
	return tex

func set_headlights(dark_state: bool) -> void:
	is_night_or_storm = dark_state
	if headlight:
		headlight.visible = is_night_or_storm and not is_broken and visible

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
	headlight.position = Vector2(36.0, 0.0)
	headlight.texture = HeadlightTextureGenerator.get_conical_headlight_texture()
	headlight.offset = Vector2(170.0, 0.0)
	headlight.visible = is_night_or_storm
	add_child(headlight)

	# Fogo / Chamas de Combustão Suaves
	flame_particles = CPUParticles2D.new()
	flame_particles.texture = _get_smooth_particle_texture()
	flame_particles.emitting = false
	flame_particles.amount = 25
	flame_particles.lifetime = 0.65
	flame_particles.gravity = Vector2(0, -90)
	flame_particles.scale_amount_min = 0.6
	flame_particles.scale_amount_max = 1.8
	flame_particles.color = Color(1.0, 0.50, 0.15, 0.90)
	preload("res://guns/combat/VehicleDamageParticles.gd").configure(flame_particles, true)
	add_child(flame_particles)

func activate():
	var residual := get_node_or_null("ResidualFire")
	if is_instance_valid(residual): residual.finish()
	for key in ["fire_residual_burning", "service_complete", "fire_water_progress", "fire_response_assigned", "fire_retry_after_ms"]:
		remove_meta(key)
	remove_meta("hospital_available")
	remove_meta("hospital_unloading")
	remove_meta("medical_waiting_admission")
	if has_meta("medical_sequence"):
		var sequence: Node = get_meta("medical_sequence")
		if is_instance_valid(sequence):
			sequence._abort()
			remove_child(sequence)
		remove_meta("medical_sequence")
	remove_meta("medical_phase")
	remove_meta("medical_abort_reason")
	remove_meta("medical_abort_phase")
	# A geometria define colisão e portas: finalizar antes de sair do depósito.
	ensure_presentation()
	_clear_tactical_doors()
	modulate = Color.WHITE
	if visual: visual.show()
	_lane_router.reset()
	_response_crew.clear()
	_ambulance_approach.reset()
	_traffic_passage.reset()
	_hospital_arrival.reset()
	for key in ["hospital_arrived", "hospital_dock_waiting", "hospital_parking_wait"]: remove_meta(key)
	for key in ["ambulance_parking_goal", "ambulance_parking_exceptional", "ambulance_walk_route"]:
		remove_meta(key)
	_police_crew.clear()
	_police_available_seats = 1 if police_variant == "motorcycle" else 2
	_police_crew_on_foot = false
	_police_recall_requested = false
	_police_boarded_ids.clear()
	_vehicle_combat = preload("res://police/PoliceVehicleCombat.gd").new()
	service_targets.clear()
	_coroner_stage = ""
	_coroner_wait = 0.0
	remove_meta("coroner_cargo")
	if has_meta("service_incident_key"): remove_meta("service_incident_key")
	_target_stopped_time = 0.0
	is_reversing = false
	reverse_timer = 0.0
	reverse_cooldown = 0.0
	reverse_attempts = 0
	stuck_timer = 0.0
	stuck_despawn_timer = 0.0
	last_tracked_pos = global_position
	_ram_damage_cooldown = 0.0
	remove_meta("spike_drop_timer")
	set_meta("police_player_pursuit", false)
	set_meta("ambient_response", false)
	set_meta("harbor_director_id", 0)
	if has_meta("depot_road_gate"):
		remove_meta("depot_road_gate")
	set_meta("depot_departure_pending", false)
	if has_meta("depot_departure_waypoints"):
		remove_meta("depot_departure_waypoints")
	_depot_driveway.cursor = 1
	home_depot_id = ""
	home_return_position = Vector2.ZERO
	home_parking_position = Vector2.ZERO
	current_speed = 0.0
	velocity = Vector2.ZERO
	is_broken = false
	is_acting = false
	is_exploding = false
	is_exploded = false
	is_returning_to_base = false
	_return_notified = false
	officer_deployed = false
	deployed_firefighters = 0
	returned_firefighters = 0
	deployed_paramedics = 0
	returned_paramedics = 0
	deployed_officers = 0
	returned_officers = 0
	deployed_morticians = 0
	returned_morticians = 0
	is_heading_to_cemetery = false
	_cemetery_target_position = Vector2.ZERO
	_coroner_carrying_body = false
	_cemetery_leaving = false
	health = 100
	damage_deformation_scale = Vector2(1.0, 1.0)
	damage_deformation_offset = Vector2.ZERO
	damage_skew = 0.0
	_clear_all_dents()
	if visual:
		visual.modulate = Color.WHITE
		visual.position = Vector2.ZERO
		visual.rotation = PI * 0.5
		visual.skew = 0.0
	if flame_particles: flame_particles.emitting = false
	if smoke_emitter:
		smoke_emitter.emitting = false
		smoke_emitter.amount = 20
		smoke_emitter.color = Color(0.2, 0.2, 0.2, 0.8)
	if siren_audio:
		siren_audio.volume_db = -10.0
		siren_audio.stop()
	if engine_audio:
		engine_audio.volume_db = -26.0
		engine_audio.play()
	show()
	set_physics_process(true)
	set_process(true)
	var vehicle_collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if vehicle_collision:
		vehicle_collision.set_deferred("disabled", false)
	set_deferred("collision_layer", 2)
	set_deferred("collision_mask", EMERGENCY_COLLISION_MASK)

func configure_depot_assignment(depot_id: String, return_position: Vector2, parking_position: Vector2, standby_id := "") -> void:
	set_meta("harbor_director_id", 0)
	home_depot_id = depot_id
	home_return_position = return_position
	home_parking_position = parking_position
	source_standby_id = standby_id
	_return_notified = false

func _service_key() -> String:
	match type:
		1: return "ambulance"
		2: return "fire"
		3: return "coroner"
		_: return "police"

func _notify_return_started() -> void:
	if _return_notified:
		return
	_return_notified = true
	returning_to_depot.emit(self, home_depot_id)
	var director := get_tree().get_first_node_in_group("emergency_depot_director")
	if director and director.has_method("begin_vehicle_return"):
		director.begin_vehicle_return(self)

func _deactivate():
	_clear_tactical_doors()
	_lane_router.reset()
	is_acting = false
	is_returning_to_base = false
	current_speed = 0.0
	velocity = Vector2.ZERO
	target = null
	if siren_audio: siren_audio.stop()
	if engine_audio: engine_audio.stop()
	var pool = get_node_or_null("/root/EmergencyPool")
	if pool:
		pool.return_vehicle(self)
	else:
		queue_free()

var is_exploding: bool = false
var is_exploded: bool = false

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	health = maxi(0, health - amount)
	if health < 50:
		smoke_emitter.emitting = true
	if health <= 25:
		smoke_emitter.color = Color(0.65, 0.65, 0.68, 0.85)
		smoke_emitter.amount = 20
	if health == 0 and not is_broken:
		set_meta("explosion_player_caused", _is_player_attacker)
		_clear_tactical_doors()
		is_broken = true
		current_speed = 0.0
		velocity = Vector2.ZERO
		if siren_audio: siren_audio.stop()
		if engine_audio: engine_audio.stop()
		_start_combustion_countdown()

func _start_combustion_countdown() -> void:
	if is_exploding or is_exploded: return
	is_exploding = true
	if flame_particles: flame_particles.emitting = true
	if smoke_emitter:
		smoke_emitter.emitting = true
		smoke_emitter.color = Color(0.65, 0.65, 0.68, 0.85)
		smoke_emitter.amount = 20
		
	await get_tree().create_timer(3.0).timeout
	if not is_exploded and health <= 0:
		_explode()

func _explode() -> void:
	if is_exploded: return
	is_exploded = true
	is_exploding = false
	if flame_particles: flame_particles.emitting = false
	if headlight: headlight.visible = false
	if siren_audio: siren_audio.stop()
	if engine_audio: engine_audio.stop()
	
	# 1. Som de explosão estrondoso
	var p = AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_explosion_stream()
	p.volume_db = 2.0
	p.max_distance = 1200.0
	get_parent().add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)
	
	preload("res://guns/combat/ExplosionVisual.gd").spawn(get_parent(), global_position, 200.0, true)
	# 6. Carcaça queimada estável no solo (sem salto no ar, sem teleporte, sem deformação)
	if visual:
		visual.modulate = Color(0.12, 0.12, 0.12)
		visual.position = Vector2.ZERO
		visual.skew = 0.0
		
	# 7. Onda de choque: danifica outros carros e arremessa pedestres
	preload("res://guns/combat/VehicleBlast.gd").apply(self)
	preload("res://emergency/VehicleResidualFire.gd").start(self)
					
	# WorldRenewal returns the wreck to the pool even in sleeping regions.

var scene_timeout: float = 0.0
var stuck_despawn_timer: float = 0.0
var last_tracked_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var is_reversing: bool = false
var reverse_timer: float = 0.0
var reverse_cooldown: float = 0.0
var reverse_attempts: int = 0
var _target_stopped_time := 0.0
var _response_crew: Array[Node2D] = []
var _missing_crew_time := 0.0

func has_police_response_crew() -> bool:
	if not _police_crew_on_foot or returned_officers > 0: return true
	for officer in _police_crew:
		if is_instance_valid(officer) and not officer.is_queued_for_deletion() and not officer.is_dead:
			return true
	return false

func _all_surviving_police_boarded() -> bool:
	if returned_officers <= 0: return false
	for officer in _police_crew:
		if is_instance_valid(officer) and not officer.is_dead and not _police_boarded_ids.has(officer.get_instance_id()):
			return false
	return true

func _physics_process(delta: float) -> void:
	# Occupancy outranks pursuit, return orders, reversing and stuck recovery.
	# Only a completed boarding cycle may release this latch; time/death cannot.
	if type == 0 and _police_crew_on_foot:
		_police_recall_requested = _police_recall_requested or is_returning_to_base
		is_returning_to_base = false
		is_acting = true
		is_reversing = false
		reverse_timer = 0.0
		current_speed = 0.0
		velocity = Vector2.ZERO
		stuck_despawn_timer = 0.0
	preload("res://cars/VehicleMotionSafety.gd").sanitize(self)
	_ram_damage_cooldown = maxf(0.0, _ram_damage_cooldown - delta)
	reverse_cooldown = maxf(0.0, reverse_cooldown - delta)
	if type == 0 and not is_returning_to_base:
		var wanted := get_node_or_null("/root/WantedManager")
		if wanted and wanted.current_stars <= 0 and not (is_instance_valid(target) and target.get_meta("ambient_crime",false)):
			if not is_acting: is_returning_to_base = true
		elif wanted and wanted.has_method("get_pursuit_target") and (get_meta("police_player_pursuit", false) or (is_instance_valid(target) and target.is_in_group("player"))):
			target = wanted.get_pursuit_target()
	_update_response_audio()
	if type == 0: _vehicle_combat.tick(self, delta)
	if is_instance_valid(target) and target.get("is_driven_by_player") == true:
		_target_stopped_time = _target_stopped_time + delta if target.velocity.length() <= 12.0 else 0.0
	else:
		_target_stopped_time = 0.0
	if is_broken:
		if type == 0 and _police_crew_on_foot: return
		current_speed = move_toward(current_speed, 0.0, 500.0 * delta)
		velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
		preload("res://cars/VehicleMotionSafety.gd").move(self)
		return
	if bool(get_meta("hospital_available", false)) or bool(get_meta("hospital_unloading", false)):
		current_speed = 0.0
		velocity = Vector2.ZERO
		stuck_despawn_timer = 0.0
		return
	if type == 3 and _coroner_stage == "morgue":
		current_speed = 0
		velocity = Vector2.ZERO
		_coroner_wait -= delta
		if _coroner_wait <= 0: _leave_morgue()
		return
	if type == 3 and _coroner_stage == "waiting_plot":
		current_speed = 0
		velocity = Vector2.ZERO
		_coroner_wait -= delta
		if _coroner_wait <= 0:
			_coroner_wait = 10.0
			_deploy_morticians_for_burial()
		return
	if not is_acting and not is_returning_to_base and bool(get_meta("depot_departure_pending", false)) and has_meta("depot_departure_waypoints"):
		if _depot_driveway.tick(self, delta): return
	if not is_acting and ((type == 1 and has_emergency_priority()) or (type == 3 and is_heading_to_cemetery) or _traffic_passage.state != "idle"):
		if _traffic_passage.tick(self,delta): return
		
	# Recuperação anti-travamento (Dá ré e manobra se ficar preso em engarrafamentos)
	if type == 1 and not is_acting and not is_returning_to_base and is_instance_valid(target) and global_position.distance_to(target.global_position) <= 620:
		is_reversing = false
		stuck_despawn_timer = 0
	if is_reversing:
		reverse_timer -= delta
		velocity = -transform.x * 120.0
		# Back up on the current heading; do not spin long vehicles across a bridge.
		preload("res://cars/VehicleMotionSafety.gd").move(self)
		if reverse_timer <= 0.0:
			is_reversing = false
			reverse_cooldown = 1.5
		return
		
	# Waiting for traffic to clear a driveway is not a failed route.
	var waiting_for_merge := bool(get_meta("depot_departure_pending", false)) and _is_vehicle_ahead()
	if global_position.distance_to(last_tracked_pos) < 8.0 and not is_acting and not waiting_for_merge and not _lane_router.at_roadside_goal and not has_meta("medical_sequence"):
		stuck_despawn_timer += delta
		if stuck_despawn_timer >= 5.0 and reverse_cooldown <= 0.0:
			_lane_router.reset()
			reverse_cooldown = 3.0
			if not _is_vehicle_ahead():
				is_reversing = true
				reverse_timer = 0.6
			# A response cannot disappear beside its patient or pursuer.
			# Only recycle a distant, unseen unit after sustained route failure.
			var viewer := get_tree().get_first_node_in_group("player") as Node2D
			var screen := get_canvas_transform() * global_position
			var unseen := not get_viewport().get_visible_rect().grow(180).has_point(screen)
			if stuck_despawn_timer >= 24.0 and unseen and viewer and viewer.global_position.distance_to(global_position) > 1000.0 and not (type == 1 and is_instance_valid(target) and target.has_meta("medical_pending")):
				_recycle_and_despawn()
				return
	else:
		stuck_despawn_timer = 0.0
		last_tracked_pos = global_position

	# === VIAGEM ATÉ O CEMITÉRIO (só CORONER, depois de recolher o corpo) ===
	if is_heading_to_cemetery:
		if siren_audio and siren_audio.playing:
			siren_audio.stop()
		if _cemetery_target_position == Vector2.ZERO:
			# No cemetery registered in this scene -- fall back to base
			# rather than driving toward the world origin forever.
			is_heading_to_cemetery = false
			is_returning_to_base = true
			return
		# Road guidance ends at the gate; only the crew enters the cemetery.
		var dist_cem = global_position.distance_to(_cemetery_target_position)
		var waypoint: Vector2 = _get_road_guidance_target(_cemetery_target_position)
		if _lane_router.at_roadside_goal and waypoint.distance_to(global_position)<2 and dist_cem<240:
			dist_cem = 0.0
		var dir_cem = global_position.direction_to(waypoint)
		var cem_angle_diff = absf(wrapf(dir_cem.angle() - rotation, -PI, PI))
		preload("res://cars/VehicleMotionSafety.gd").rotate_clear(self, lerp_angle(rotation, dir_cem.angle(), minf(1.0, 4.5 * delta)))
		var cem_cruise = max_target_speed * 0.55
		if cem_angle_diff > 0.4:
			cem_cruise *= 0.5
		var clearance := _forward_clearance()
		cem_cruise = minf(cem_cruise, sqrt(1040.0 * maxf(0.0, clearance - 8.0)))
		if dist_cem > 40.0:
			current_speed = move_toward(current_speed, cem_cruise, acceleration * delta)
			current_speed = minf(current_speed, maxf(0, clearance-3)/maxf(delta,.001))
			velocity = transform.x * current_speed
		else:
			current_speed = move_toward(current_speed, 0.0, 400.0 * delta)
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
			if velocity.length() < 12 and current_speed < 12:
				is_heading_to_cemetery = false
				if _cemetery_leaving:
					# Back out at the gate (road-adjacent): the normal,
					# lane-following return-to-base leg can take over cleanly
					# from here instead of from deep inside the walled lot.
					_cemetery_leaving = false
					is_returning_to_base = true
				else:
					is_acting = true
					if deployed_morticians == 0:
						_deploy_morticians_for_burial()
				return
		preload("res://cars/VehicleMotionSafety.gd").move(self)
		return

	# === VIAGEM DE RETORNO À BASE (Quartel ou Hospital) ===
	if is_returning_to_base:
		_notify_return_started()
		var base_pos := home_return_position
		var medical_sequence: Node = get_meta("medical_sequence") if has_meta("medical_sequence") else null
		var hospital: Node2D = null
		var medical_director: Node = instance_from_id(int(get_meta("harbor_director_id", 0))) if int(get_meta("harbor_director_id", 0)) > 0 else null
		if type == 1:
			hospital = get_tree().get_first_node_in_group("hospital_emergency_admission")
			if hospital: base_pos = hospital.get_ambulance_stop_position()
			if hospital and is_instance_valid(medical_director) and medical_director.has_method("get_medical_return_position"):
				base_pos = medical_director.get_medical_return_position(self)
		if hospital and not base_pos.is_finite():
			current_speed = 0
			velocity = Vector2.ZERO
			set_meta("hospital_parking_wait", true)
			return
		remove_meta("hospital_parking_wait")
		if hospital and global_position.distance_to(base_pos) < 330:
			if not bool(get_meta("hospital_arrived",false)):
				if not _hospital_arrival.tick(self,base_pos,hospital.get_ambulance_stop_rotation(),delta): return
				set_meta("hospital_arrived",true)
				_lane_router.reset()
				if siren_audio: siren_audio.stop()
			current_speed = 0
			velocity = Vector2.ZERO
			if not is_instance_valid(medical_sequence) or not medical_sequence.delivered:
				finish_hospital_parking()
				return
			if is_instance_valid(medical_director) and medical_director.has_method("is_medical_bay_owner") and not medical_director.is_medical_bay_owner(self):
				set_meta("medical_waiting_admission", true)
				return
			remove_meta("medical_waiting_admission")
			medical_sequence.start_hospital_admission(hospital)
			arrived_at_depot.emit(self, home_depot_id)
			return
		if base_pos == Vector2.ZERO:
			var depot_director := get_tree().get_first_node_in_group("emergency_depot_director")
			if depot_director and depot_director.has_method("get_return_position"):
				base_pos = depot_director.get_return_position(_service_key())
		if base_pos == Vector2.ZERO:
			_deactivate()
			return
		if type == 3 and int(get_meta("harbor_director_id",0))>0 and global_position.distance_to(base_pos)<330:
			if not _hospital_arrival.tick(self,base_pos,0.0,delta): return
			if _admit_coroner_cargo(): return
			arrived_at_depot.emit(self,home_depot_id)
			var owner: Node = instance_from_id(int(get_meta("harbor_director_id")))
			if is_instance_valid(owner): owner.complete_vehicle_return(self)
			_deactivate()
			return
		var waypoint = _get_road_guidance_target(base_pos)
		if waypoint.distance_to(global_position) < 1.0 and global_position.distance_to(base_pos) > 45.0:
			current_speed = 0.0
			velocity = Vector2.ZERO
			return
		var dist_base = global_position.distance_to(base_pos)
		var dir_wpt = global_position.direction_to(waypoint)
		
		var angle_diff = absf(wrapf(dir_wpt.angle() - rotation, -PI, PI))
		preload("res://cars/VehicleMotionSafety.gd").rotate_clear(self, lerp_angle(rotation, dir_wpt.angle(), minf(1.0, 4.5 * delta)))
		
		var target_cruise = max_target_speed * 0.75
		if angle_diff > 0.4:
			target_cruise *= 0.5 # Desacelera nas curvas
			
		if dist_base > 45.0:
			var clearance := _forward_clearance()
			target_cruise = minf(target_cruise, sqrt(1040.0 * maxf(0.0, clearance - 8.0)))
			current_speed = move_toward(current_speed, target_cruise, (520.0 if target_cruise < current_speed else acceleration) * delta)
			current_speed = minf(current_speed, maxf(0.0, clearance - 3.0) / maxf(delta, 0.001))
			velocity = transform.x * current_speed
		else:
			current_speed = move_toward(current_speed, 0.0, 400.0 * delta)
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
			if velocity.length() < 12 and current_speed < 12:
				if is_instance_valid(medical_sequence): medical_sequence.finish_transport_without_entrance()
				if _admit_coroner_cargo(): return
				arrived_at_depot.emit(self, home_depot_id)
				var depot_director := get_tree().get_first_node_in_group("emergency_depot_director")
				if depot_director and depot_director.has_method("complete_vehicle_return"):
					depot_director.complete_vehicle_return(self)
				_deactivate()
				return
		preload("res://cars/VehicleMotionSafety.gd").move(self)
		return
		
	if is_acting:
		if type == 0:
			_police_crew = _police_crew.filter(func(officer): return is_instance_valid(officer) and not officer.is_dead)
			if deployed_officers > 0 and returned_officers == 0 and _police_crew.is_empty():
				_clear_tactical_doors()
				return
			# Polícia em bloqueio tático: permanece firme servindo de barricada enquanto o alvo estiver procurado
			var wm = get_node_or_null("/root/WantedManager")
			var stars: int = 1 if is_instance_valid(target) and target.get_meta("ambient_crime",false) else (wm.current_stars if wm else 0)
			var dist_to_target = global_position.distance_to(target.global_position) if is_instance_valid(target) else 9999.0
			var fleeing_car: bool = is_instance_valid(target) and target.get("is_driven_by_player") == true and target.get("velocity") is Vector2 and (target.get("velocity") as Vector2).length() > 12.0
			if _police_recall_requested or stars == 0 or dist_to_target > 600.0 or not is_instance_valid(target) or fleeing_car or scene_timeout >= 1.5:
				scene_timeout += delta
				# Ask deployed officers to walk back to their assigned doors first.
				# A stuck, dead or missing officer never authorizes an empty car.
				if scene_timeout >= 1.5:
					_request_officers_return()
				if deployed_officers > 0 and _all_surviving_police_boarded():
					# A new engagement cannot recreate a killed or stranded partner.
					_police_available_seats = returned_officers
					for officer in _police_crew:
						if is_instance_valid(officer) and not officer.boarding_service_vehicle:
							officer.service_vehicle = null
							officer.returning_to_service_vehicle = false
					is_acting = false
					_police_crew_on_foot = false
					_clear_tactical_doors()
					is_returning_to_base = _police_recall_requested or stars == 0 or not is_instance_valid(target)
					_police_recall_requested = false
					officer_deployed = false
					deployed_officers = 0
					returned_officers = 0
					if siren_audio: siren_audio.stop()
			else:
				scene_timeout = 0.0
		else:
			scene_timeout += delta
			# Atendimento acaba com o embarque, não com um relógio que abandona
			# a equipe. Se ninguém sobreviveu, libera o veículo para a central.
			_response_crew = _response_crew.filter(func(crew): return is_instance_valid(crew) and not crew.is_queued_for_deletion() and crew.get("is_dead") != true)
			var awaiting_boarding := (type == 1 and returned_paramedics < deployed_paramedics) or (type == 2 and returned_firefighters < deployed_firefighters) or (type == 3 and returned_morticians < deployed_morticians)
			_missing_crew_time = _missing_crew_time + delta if _response_crew.is_empty() and awaiting_boarding else 0.0
			if _missing_crew_time >= 2.0:
				is_acting = false
				is_returning_to_base = true
				if siren_audio: siren_audio.stop()
			elif scene_timeout >= (45.0 if type == 2 else 30.0) and not has_meta("medical_sequence"):
				for crew in _response_crew:
					if type == 1: crew._start_return_to_ambulance()
					elif type == 2: crew._start_return_to_truck()
			
		current_speed = move_toward(current_speed, 0.0, 500.0 * delta)
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
		if type == 0 and _police_crew_on_foot: return
		preload("res://cars/VehicleMotionSafety.gd").move(self)
		return
	else:
		scene_timeout = 0.0
		
	if not is_instance_valid(target):
		if type == 2 and deployed_firefighters > 0 and returned_firefighters < deployed_firefighters:
			current_speed = 0.0
			velocity = Vector2.ZERO
			preload("res://cars/VehicleMotionSafety.gd").move(self)
			return
		if type == 1 and deployed_paramedics > 0 and returned_paramedics < deployed_paramedics:
			current_speed = 0.0
			velocity = Vector2.ZERO
			preload("res://cars/VehicleMotionSafety.gd").move(self)
			return
		if type == 3 and deployed_morticians > 0 and returned_morticians < deployed_morticians:
			current_speed = 0.0
			velocity = Vector2.ZERO
			preload("res://cars/VehicleMotionSafety.gd").move(self)
			return
			
		if type in [2, 3] and _advance_service_target(): return
		# Se não há ocorrência válida ativa, desliga sirene e retorna à central imediatamente
		if siren_audio and siren_audio.playing:
			siren_audio.stop()
		is_returning_to_base = true
		return
		
	if (type == 1 or (type == 3 and get_tree().current_scene.has_node("RoadNetwork"))) and _ambulance_approach.tick(self, target, delta): return
	var is_target_in_car: bool = target.is_in_group("vehicle") or target.get("is_driven_by_player") == true
	var arrival_radius := _police_stop_radius() if type == 0 else (120.0 if type == 2 else 75.0)
	var may_stop := type != 0 or not is_target_in_car or _target_stopped_time >= 0.6
	if may_stop and global_position.distance_to(target.global_position) <= arrival_radius:
		# Frear antes de orientar para outro waypoint evita rodar parado ao lado
		# da ocorrência e impede desembarque com a viatura ainda em movimento.
		current_speed = move_toward(current_speed, 0.0, 520.0 * delta)
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
		preload("res://cars/VehicleMotionSafety.gd").move(self)
		if velocity.length() <= 12.0 and current_speed <= 12.0: _begin_response()
		return
	var intercept_pos := target.global_position
	if is_target_in_car and "velocity" in target and target.velocity.length() > 30.0:
		# Antecipa a trajetória do veículo do jogador para interceptação
		intercept_pos = target.global_position + target.velocity * 0.35
		
	var waypoint = _get_road_guidance_target(intercept_pos)
	if waypoint.distance_to(global_position) < 1.0:
		current_speed = 0.0
		velocity = Vector2.ZERO
		# A faixa termina no meio-fio: socorristas percorrem o trecho a pé.
		var foot_response_range := 550.0 if type == 0 and _lane_router.at_roadside_goal else 360.0
		if global_position.distance_to(target.global_position) <= foot_response_range:
			if type != 0 or not is_target_in_car or _target_stopped_time >= 0.6:
				_begin_response()
		return
	var dir = global_position.direction_to(waypoint)
	if type == 0:
		var separation := _police_separation_dir()
		if separation != Vector2.ZERO:
			dir = (dir + separation * POLICE_SEPARATION_STRENGTH).normalized()
	var dist = global_position.distance_to(target.global_position)

	# Escala velocidade máxima com o nível de procurado
	var wm = get_node_or_null("/root/WantedManager")
	var stars: int = 1 if is_instance_valid(target) and target.get_meta("ambient_crime",false) else (wm.current_stars if wm else 1)
	var police_top_speed = max_target_speed + float(stars * 18.0)
	
	# The lane router chooses hull-checked detours; the forward sweep below
	# brakes for traffic that enters the maneuver after it was planned.
	var steer_avoid_angle := 0.0
		
	# Verificação de No-Go Zone (A polícia não se atreve a entrar no Beco dos Cobras com menos de 4 estrelas)
	if type == 0 and stars < 4 and get_tree().current_scene.has_node("DistrictOneComplete"):
		var no_go_rect := Rect2(480, 90, 290, 310)
		if no_go_rect.has_point(target.global_position):
			var roadblock_pos := Vector2(775, 205)
			if global_position.distance_to(roadblock_pos) < 60.0:
				current_speed = move_toward(current_speed, 0.0, 500.0 * delta)
				velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
				preload("res://cars/VehicleMotionSafety.gd").rotate_clear(self, lerp_angle(rotation, PI, 3.0 * delta)) # Aponta viatura para o beco montando cerco
				preload("res://cars/VehicleMotionSafety.gd").move(self)
				return
			else:
				waypoint = roadblock_pos
				dir = global_position.direction_to(waypoint)

	var target_angle = (dir.rotated(steer_avoid_angle)).angle()
	var angle_diff = absf(wrapf(target_angle - rotation, -PI, PI))
	var steer_rate = 6.0 if type == 0 else 4.5
	var next_heading: float = rotate_toward(rotation, target_angle, current_speed * delta / 70.0) if type == 1 else lerp_angle(rotation, target_angle, minf(1.0, steer_rate * delta))
	if type != 1: preload("res://cars/VehicleMotionSafety.gd").rotate_clear(self, next_heading)
	
	var desired_speed = police_top_speed if type == 0 else max_target_speed
	if angle_diff > 1.20:
		# A waypoint behind the bumper requires braking before turning. Keeping
		# half cruising speed here made short detours become circular orbits.
		desired_speed = 35.0 if type == 1 else 0.0
	elif angle_diff > 0.50:
		desired_speed *= 0.55 # Desaceleração realista em curvas fechadas
	desired_speed = minf(desired_speed, sqrt(1040.0 * maxf(0.0, global_position.distance_to(waypoint) - 4.0)))
		
	var clearance := _forward_clearance()
	desired_speed = minf(desired_speed, sqrt(2.0 * 520.0 * maxf(0.0, clearance - 8.0)))
	if waiting_for_merge:
		desired_speed = 0.0

	current_speed = move_toward(current_speed, desired_speed, (520.0 if desired_speed < current_speed else acceleration + float(stars * 20.0)) * delta)
	current_speed = minf(current_speed, maxf(0.0, clearance - 3.0) / maxf(delta, 0.001))
	var forward_vec = Vector2.from_angle(rotation + angle_difference(rotation,next_heading)*.5) if type == 1 else transform.x
	
	if type == 0: # POLÍCIA
		var target_moving := false
		if is_instance_valid(target) and "velocity" in target:
			target_moving = (target.velocity as Vector2).length() > 12.0 or _target_stopped_time < 0.6
			
		if is_target_in_car and target_moving:
			# === PERSEGUIÇÃO VEICULAR DINÂMICA (Acompanhamento e tentativa de emparelhar/cortar) ===
			velocity = forward_vec * current_speed
			if dist < 48.0 and velocity.length() > 60.0 and _ram_damage_cooldown <= 0.0:
				_ram_damage_cooldown = 0.85
				if target.has_method("take_damage"):
					target.take_damage(randi_range(4, 8))
				if collision_particles:
					collision_particles.restart()
					
			# Lançamento tático de Fita de Pregos (Spike Strip) em perseguições de 3+ estrelas
			if stars >= 3 and dist < 140.0:
				if not has_meta("spike_drop_timer"):
					set_meta("spike_drop_timer", randf_range(6.0, 12.0))
				var s_timer: float = float(get_meta("spike_drop_timer")) - delta
				set_meta("spike_drop_timer", s_timer)
				if s_timer <= 0.0:
					set_meta("spike_drop_timer", randf_range(16.0, 24.0))
					var spike := SpikeStrip.new()
					spike.global_position = global_position - forward_vec * 20.0
					spike.rotation = rotation + PI * 0.5 # Atravessado na pista
					get_tree().current_scene.add_child(spike)
		else:
			# === ALVO PARADO/ACUADO OU A PÉ: BLOQUEIO TÁTICO E DESEMBARQUE DA DUPLA ===
			var stop_distance := _police_stop_radius()
			if dist <= stop_distance:
				current_speed = move_toward(current_speed, 0.0, 520.0 * delta)
				velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
				if velocity.length() < 30.0:
					is_acting = true
					if engine_audio: engine_audio.volume_db = -32.0
					if not officer_deployed:
						officer_deployed = true
						_deploy_officers_duo()
					return
			else:
				velocity = forward_vec * current_speed
	elif type == 1: # AMBULÂNCIA
		if dist <= 75.0:
			current_speed = 0.0
			velocity = Vector2.ZERO
			is_acting = true
			if deployed_paramedics == 0:
				_deploy_paramedics()
			return
		else:
			velocity = forward_vec * current_speed
	elif type == 2: # BOMBEIROS
		if dist <= 120.0:
			current_speed = 0.0
			velocity = Vector2.ZERO
			is_acting = true
			if engine_audio: engine_audio.volume_db = -30.0
			if siren_audio: siren_audio.volume_db = -28.0
			if deployed_firefighters == 0:
				_deploy_firefighters()
			return
		else:
			velocity = forward_vec * current_speed
	elif type == 3: # CORONER (Rabecão do IML)
		if dist <= 75.0:
			current_speed = 0.0
			velocity = Vector2.ZERO
			is_acting = true
			if engine_audio: engine_audio.volume_db = -30.0
			if siren_audio: siren_audio.volume_db = -28.0
			if deployed_morticians == 0:
				_deploy_morticians()
			return
		else:
			velocity = forward_vec * current_speed
			
	var prev_velocity = velocity
	if type == 1:
		if not _ambulance_approach._move_to(self, global_position + velocity * delta, next_heading, delta):
			current_speed = 0
			velocity = Vector2.ZERO
	else:
		preload("res://cars/VehicleMotionSafety.gd").move(self)
	
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var normal_impact = absf(prev_velocity.dot(col.get_normal()))
		var impact_speed = maxf(prev_velocity.length() - velocity.length(), normal_impact)
		if impact_speed > 35.0:
			_apply_crash_deformation(col.get_normal(), impact_speed, col.get_position())
			var body = col.get_collider()
			if is_instance_valid(body) and body != self and body.has_method("_apply_crash_deformation"):
				body._apply_crash_deformation(-col.get_normal(), impact_speed, col.get_position())
	
	# Detecta travamento contra prédios ou barreiras e executa manobra ágil de ré e curva
	var low_speed_obstacle := current_speed < 15.0 and not is_acting and _is_obstacle_ahead()
	if (current_speed > 30.0 and velocity.length() < 16.0) or low_speed_obstacle:
		stuck_timer += delta
		if stuck_timer > 0.45 and reverse_cooldown <= 0.0:
			# Um congestionamento perto da ocorrência não exige repetir ré:
			# estacionar aqui permite que a equipe conclua o acesso a pé.
			if dist <= 360.0 and may_stop:
				_begin_response()
				return
			is_reversing = true
			reverse_timer = 0.45
			reverse_attempts += 1
			stuck_timer = 0.0
			# Repeated backing-up is an oscillation, not recovery. Force a
			# fresh lane plan after two attempts instead of reversing forever.
			if reverse_attempts >= 2:
				_lane_router.reset()
				reverse_attempts = 0
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 0.5)

func _begin_response() -> void:
	if type == 1 and (not is_instance_valid(target) or not _ambulance_approach.service_clear(self, target, global_transform)):
		return
	if type == 1:
		if not has_meta("ambulance_parking_goal"):
			set_meta("ambulance_parking_goal", global_position)
			set_meta("ambulance_parking_exceptional", true)
		set_meta("ambulance_walk_route", _ambulance_approach.walk_route.duplicate())
	_missing_crew_time = 0.0
	current_speed = 0.0
	velocity = Vector2.ZERO
	is_reversing = false
	scene_timeout = 0.0
	is_acting = true
	match type:
		0:
			if not officer_deployed:
				officer_deployed = true
				_deploy_officers_duo()
		1:
			if deployed_paramedics == 0: _deploy_paramedics()
		2:
			if deployed_firefighters == 0: _deploy_firefighters()
		3:
			if deployed_morticians == 0: _deploy_morticians()

func _forward_clearance() -> float:
	var hull := get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.transform = hull.global_transform
	query.collision_mask = EMERGENCY_COLLISION_MASK
	query.exclude = [get_rid()]
	query.margin = 2.0
	var distance := maxf(110.0, current_speed * current_speed / 1040.0 + 45.0)
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return 0.0
	query.motion = transform.x * distance
	return distance * space.cast_motion(query)[0]

func _get_obstacle_avoidance_angle() -> float:
	var space_state = get_world_2d().direct_space_state
	var forward = transform.x
	var left_query = PhysicsRayQueryParameters2D.create(global_position, global_position + forward.rotated(-0.55) * 85.0, EMERGENCY_COLLISION_MASK)
	left_query.exclude = [get_rid()]
	var left_res = space_state.intersect_ray(left_query)
	
	var right_query = PhysicsRayQueryParameters2D.create(global_position, global_position + forward.rotated(0.55) * 85.0, EMERGENCY_COLLISION_MASK)
	right_query.exclude = [get_rid()]
	var right_res = space_state.intersect_ray(right_query)
	
	if left_res.is_empty():
		return -0.55
	elif right_res.is_empty():
		return 0.55
	return 0.85

func _is_obstacle_ahead() -> bool:
	var space_state = get_world_2d().direct_space_state
	var forward = transform.x
	var sensor_length = 75.0 if type != 2 else 95.0
	
	for offset_angle in [0.0, 0.24, -0.24]:
		var ray_dir = forward.rotated(offset_angle)
		var query = PhysicsRayQueryParameters2D.create(global_position + forward * 20.0, global_position + ray_dir * sensor_length, EMERGENCY_COLLISION_MASK)
		query.exclude = [get_rid()]
		var res = space_state.intersect_ray(query)
		if not res.is_empty():
			var collider = res.get("collider")
			if collider != target and collider != null and not collider.is_in_group("player"):
				return true
	return false

func _is_vehicle_ahead() -> bool:
	var space_state := get_world_2d().direct_space_state
	var forward := transform.x.normalized()
	if forward.length_squared() < 0.01:
		return false
	var sensor_length := 88.0 if type != 2 else 118.0
	var query := PhysicsRayQueryParameters2D.create(global_position + forward * 18.0, global_position + forward * sensor_length, 2)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	var collider := result.get("collider") as Node if not result.is_empty() else null
	return collider != null and collider.is_in_group("vehicle")
	
	# Pitch dinâmico suave do motor
	if engine_audio:
		var speed_ratio = clampf(current_speed / maxf(1.0, max_target_speed), 0.0, 1.0)
		engine_audio.pitch_scale = lerp(0.8, 1.4, speed_ratio)

func _recycle_and_despawn() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func():
		modulate.a = 1.0
		_deactivate()
	)


func get_crew_door_point(side: float, longitudinal: float = -8.0) -> Vector2:
	return CREW_TRANSITION.get_door_point(self, side, longitudinal)


func get_crew_exit_point(side: float, longitudinal: float = -8.0) -> Vector2:
	return CREW_TRANSITION.get_exit_point(self, side, longitudinal)


func get_crew_spawn_point(side: float, longitudinal: float = -8.0) -> Vector2:
	return CREW_TRANSITION.get_spawn_point(self, side, longitudinal)


func play_crew_door(side: float, longitudinal: float = -8.0) -> void:
	if police_variant == "motorcycle": return
	if _tactical_doors.has(side):
		close_crew_cover_door(side)
		return
	if visual_3d:
		visual_3d.open_door(side, 0.42)
		return
	# Reuse the same painted, hinged door used by player traffic vehicles.  It
	# carries both the open and close sound, including the final latch.
	var door := CREW_DOOR_SCRIPT.new()
	door.name = "CrewDoor"
	add_child(door)
	door.configure(Vector2(longitudinal, side * 16.0), 34.0 if type != 2 else 40.0)
	door.play(CREW_TRANSITION.paint_for_service(type), side)
	var cleanup := door.create_tween()
	cleanup.tween_interval(1.2)
	cleanup.tween_callback(door.queue_free)

func open_crew_cover_door(side: float, longitudinal: float = -8.0) -> void:
	if police_variant == "motorcycle": return
	if _tactical_doors.has(side): return
	var door := CREW_DOOR_SCRIPT.new()
	door.name = "TacticalDoorLeft" if side < 0 else "TacticalDoorRight"
	add_child(door)
	# A police cruiser is only 82 pixels long: its front door occupies 22,
	# not the 34-pixel panel used for the long rescue vehicles.
	door.configure(Vector2(longitudinal, side * 16.0), 26.0)
	if visual_3d: door.configure(visual_3d.door_floor_hinge(side), 26.0)
	door.scale.x = 0.85
	door.play(CREW_TRANSITION.paint_for_service(type), side, 3600.0)
	if visual_3d:
		door.self_modulate.a = 0.0
		# Hide only rendered canvas surfaces; the physical door keeps blocking
		# bullets while its real authored 3D counterpart remains open.
		for piece in door.get_children():
			if piece is CanvasItem: piece.hide()
		visual_3d.open_door(side)
	var cover := StaticBody2D.new()
	cover.name = "BallisticCover"
	cover.collision_layer = 1
	cover.collision_mask = 0
	cover.add_to_group("metal_prop")
	var shape := CollisionShape2D.new()
	var panel := RectangleShape2D.new()
	panel.size = Vector2(24.0, 5.0)
	shape.shape = panel
	shape.position = Vector2(-12, 3)
	cover.add_child(shape)
	door.add_child(cover)
	_tactical_doors[side] = door

func close_crew_cover_door(side: float) -> void:
	if visual_3d: visual_3d.close_door(side)
	var door: Node2D = _tactical_doors.get(side)
	_tactical_doors.erase(side)
	if not is_instance_valid(door): return
	if door._active_tween != null: door._active_tween.kill()
	var body := door.get_node_or_null("BallisticCover") as StaticBody2D
	if body:
		_release_cover_exceptions(body)
		body.set_deferred("collision_layer", 0)
	var closing := door.create_tween()
	closing.tween_property(door, "rotation", 0.0, 0.26)
	closing.tween_callback(door._finish_close)
	closing.tween_interval(0.3)
	closing.tween_callback(door.queue_free)

func get_crew_cover_point(side: float, longitudinal: float, threat: Vector2) -> Vector2:
	var door: Node2D = _tactical_doors.get(side)
	if not is_instance_valid(door): return get_crew_exit_point(side, longitudinal)
	var center := door.to_global(Vector2(-12, 3))
	return center + threat.direction_to(center) * 13.0

func _clear_tactical_doors() -> void:
	if visual_3d: visual_3d.reset_doors()
	for side in _tactical_doors.keys():
		var door: Node2D = _tactical_doors[side]
		if is_instance_valid(door):
			door.hide()
			var body := door.get_node_or_null("BallisticCover") as StaticBody2D
			if body:
				_release_cover_exceptions(body)
				body.set_deferred("collision_layer", 0)
			door.queue_free()
	_tactical_doors.clear()

func _release_cover_exceptions(cover: StaticBody2D) -> void:
	# Uma exceção que ainda aponta para o RID da porta destruída quebra consultas
	# físicas posteriores; removê-la faz parte do fechamento da porta.
	if not is_inside_tree(): return
	for officer in get_tree().get_nodes_in_group("police_officer"):
		if officer.get("service_vehicle") == self:
			officer.remove_collision_exception_with(cover)

func _deploy_officers_duo() -> void:
	if _police_crew_on_foot: return
	var officer_scene = load("res://police/PoliceOfficer.tscn")
	var officer_pool := get_node_or_null("/root/EmergencyPool")
	if officer_scene:
		var driver_seat := Vector2(-8.0, -1.0)
		if police_variant == "motorcycle":
			driver_seat = preload("res://police/PoliceMotorcycleCrew.gd").exit_seat(self)
			if not driver_seat.is_finite():
				# Make physical room before spawning a rider inside an obstacle.
				officer_deployed = false
				is_acting = false
				is_reversing = true
				reverse_timer = 0.45
				return
		deployed_officers = mini(_police_available_seats, 1 if police_variant == "motorcycle" else 2)
		if deployed_officers <= 0:
			is_acting = false
			is_returning_to_base = true
			return
		returned_officers = 0
		_police_crew_on_foot = true
		_police_recall_requested = false
		_police_boarded_ids.clear()
		_police_crew.clear()
		# Policial 1 (Motorista - desce pela lateral esquerda)
		var driver_level := police_response_level if police_variant != "patrol" else mini(police_response_level, 2)
		var off1 = officer_pool.take_officer(driver_level) if officer_pool != null else officer_scene.instantiate()
		off1.set_meta("response_tier_level", police_response_level if police_variant != "patrol" else mini(police_response_level, 2))
		off1.target = target
		off1.global_position = get_crew_spawn_point(driver_seat.y, driver_seat.x)
		if off1.has_method("begin_service_disembark"):
			off1.begin_service_disembark(self, driver_seat.y, driver_seat.x)
		get_parent().add_child(off1)
		_police_crew.append(off1)
		open_crew_cover_door(driver_seat.y, driver_seat.x)
		if deployed_officers == 1: return
		
		# Policial 2 (Parceiro tático - desce pela lateral direita)
		var off2 = officer_pool.take_officer(police_response_level) if officer_pool != null else officer_scene.instantiate()
		off2.set_meta("response_tier_level", police_response_level)
		off2.target = target
		off2.global_position = get_crew_spawn_point(1.0, -8.0)
		if off2.has_method("begin_service_disembark"):
			off2.begin_service_disembark(self, 1.0, -8.0)
		get_parent().add_child(off2)
		_police_crew.append(off2)
		off1.add_collision_exception_with(off2)
		off2.add_collision_exception_with(off1)
		off1.crew_partner = off2
		off2.crew_partner = off1
		open_crew_cover_door(1.0, -8.0)

func _deploy_officer() -> void:
	_deploy_officers_duo()


func _request_officers_return() -> void:
	for officer in get_tree().get_nodes_in_group("police_officer"):
		if officer.get("service_vehicle") == self and officer.has_method("return_to_service_vehicle"):
			officer.return_to_service_vehicle()


func stand_down() -> void:
	if type != 0: return
	set_meta("police_player_pursuit", false)
	target = null
	if siren_audio and siren_audio.playing:
		siren_audio.stop()
	if lights:
		lights.visible = false
	_police_recall_requested = true
	_request_officers_return()
	if not is_acting or deployed_officers == 0:
		is_acting = false
		_police_crew_on_foot = false
		_clear_tactical_doors()
		is_returning_to_base = true


func on_officer_embarked(officer: Node2D) -> void:
	if not is_instance_valid(officer) or not _police_crew.has(officer): return
	if officer.service_vehicle != self or officer.is_dead or not officer.boarding_service_vehicle or officer.visible: return
	var id := officer.get_instance_id()
	if _police_boarded_ids.has(id): return
	_police_boarded_ids[id] = true
	returned_officers += 1

func _deploy_paramedics() -> void:
	var p_scene = load("res://emergency/Paramedic.tscn")
	if p_scene:
		deployed_paramedics = 2
		returned_paramedics = 0
		
		# Paramédico 1 (com a Maca)
		var p1 = p_scene.instantiate()
		p1.target = target
		p1.ambulance = self
		p1.is_stretcher_bearer = true
		p1.global_position = get_crew_spawn_point(-1.0, 8.0)
		if p1.has_method("begin_service_disembark"):
			p1.begin_service_disembark(self, -1.0, 8.0)
		get_parent().add_child(p1)
		_response_crew.append(p1)
		play_crew_door(-1.0, 8.0)
		
		# Paramédico 2 (Apoio / Médico)
		var p2 = p_scene.instantiate()
		p2.target = target
		p2.ambulance = self
		p2.is_stretcher_bearer = false
		p2.global_position = get_crew_spawn_point(1.0, 8.0)
		if p2.has_method("begin_service_disembark"):
			p2.begin_service_disembark(self, 1.0, 8.0)
		get_parent().add_child(p2)
		_response_crew.append(p2)
		play_crew_door(1.0, 8.0)
		if is_instance_valid(target) and target is CharacterBody2D and get_node_or_null("/root/NPCMedicalCare"):
			var sequence := preload("res://emergency/MedicalRescueSequence.gd").new()
			add_child(sequence)
			sequence.setup(self,target,[p1,p2])

func on_paramedic_embarked(_p: Node2D) -> void:
	returned_paramedics += 1
	if returned_paramedics >= deployed_paramedics:
		await get_tree().create_timer(1.0).timeout
		is_acting = false
		is_returning_to_base = true
		# Replan from the pickup position rather than retaining the inbound lane.
		_lane_router.reset()
		_update_response_audio()

func _deploy_firefighters() -> void:
	var ff_scene = load("res://emergency/Firefighter.tscn")
	if ff_scene:
		deployed_firefighters = 2
		returned_firefighters = 0
		
		var ff1 = ff_scene.instantiate()
		ff1.target = target
		ff1.fire_truck = self
		ff1.global_position = get_crew_spawn_point(-1.0, 22.0)
		if ff1.has_method("begin_service_disembark"):
			ff1.begin_service_disembark(self, -1.0, 22.0)
		get_parent().add_child(ff1)
		_response_crew.append(ff1)
		play_crew_door(-1.0, 22.0)
		
		var ff2 = ff_scene.instantiate()
		ff2.target = target
		ff2.fire_truck = self
		ff2.global_position = get_crew_spawn_point(1.0, 22.0)
		if ff2.has_method("begin_service_disembark"):
			ff2.begin_service_disembark(self, 1.0, 22.0)
		get_parent().add_child(ff2)
		_response_crew.append(ff2)
		play_crew_door(1.0, 22.0)

func on_firefighter_embarked(_ff: Node2D) -> void:
	returned_firefighters += 1
	if returned_firefighters >= deployed_firefighters:
		await get_tree().create_timer(1.0).timeout
		if _advance_service_target(): return
		is_acting = false
		is_returning_to_base = true
		if engine_audio:
			engine_audio.volume_db = -26.0
			engine_audio.play()
		if siren_audio:
			siren_audio.stop()

func _deploy_morticians() -> void:
	var m_scene = load("res://emergency/Mortician.tscn")
	if m_scene:
		deployed_morticians = 2
		returned_morticians = 0
		
		# Agente 1 (com a Maca e Saco de Cadáver)
		var m1 = m_scene.instantiate()
		m1.target = target
		m1.hearse = self
		m1.is_stretcher_bearer = true
		m1.global_position = get_crew_spawn_point(-1.0, 22.0)
		if m1.has_method("begin_service_disembark"):
			m1.begin_service_disembark(self, -1.0, 22.0)
		get_parent().add_child(m1)
		_response_crew.append(m1)
		play_crew_door(-1.0, 22.0)
		
		# Agente 2 (Apoio / Perito IML)
		var m2 = m_scene.instantiate()
		m2.target = target
		m2.hearse = self
		m2.is_stretcher_bearer = is_instance_valid(target) and target.has_method("collect_piece")
		m2.global_position = get_crew_spawn_point(1.0, 22.0)
		if m2.has_method("begin_service_disembark"):
			m2.begin_service_disembark(self, 1.0, 22.0)
		get_parent().add_child(m2)
		_response_crew.append(m2)
		play_crew_door(1.0, 22.0)

## One legist, sent to bury the body already loaded from the pickup leg
## (target is null here on purpose -- there is no living victim on this
## trip, only the cemetery plot; see Mortician.gd's is_burial_trip).
func _deploy_morticians_for_burial() -> void:
	var m_scene = load("res://emergency/Mortician.tscn")
	if m_scene:
		deployed_morticians = 1
		returned_morticians = 0
		var m1 = m_scene.instantiate()
		m1.is_burial_trip = true
		m1.burial_position = _cemetery_target_position
		if not get_node("/root/CoronerCare").start_burial(self, m1):
			m1.free()
			deployed_morticians = 0
			_coroner_stage = "waiting_plot"
			_coroner_wait = 10.0
			return
		_coroner_stage = "burial"
		m1.hearse = self
		m1.is_stretcher_bearer = true
		m1.global_position = get_crew_spawn_point(-1.0, 22.0)
		if m1.has_method("begin_service_disembark"):
			m1.begin_service_disembark(self, -1.0, 22.0)
		get_parent().add_child(m1)
		_response_crew.append(m1)
		play_crew_door(-1.0, 22.0)

func on_mortician_embarked(_m: Node2D) -> void:
	returned_morticians += 1
	if returned_morticians < deployed_morticians:
		var waiting := _response_crew.any(func(crew): return is_instance_valid(crew) and not crew.is_queued_for_deletion() and not crew.is_dead and crew.state != crew.State.EMBARKED)
		if waiting: return
	var care := get_node("/root/CoronerCare")
	if _coroner_stage == "burial":
		deployed_morticians = 0
		returned_morticians = 0
		if care.has_cargo(self):
			_deploy_morticians_for_burial()
		else:
			_coroner_stage = "return"
			is_acting = false
			is_returning_to_base = true
			_lane_router.reset()
		return
	if not is_heading_to_cemetery and _advance_service_target(): return
	if care.has_cargo(self):
		_coroner_stage = "to_morgue"
		is_acting = false
		is_returning_to_base = true
		target = null
		_lane_router.reset()
		return
	is_acting = false
	is_returning_to_base = true
	return

func _admit_coroner_cargo() -> bool:
	if type != 3 or _coroner_stage != "to_morgue" or not get_node("/root/CoronerCare").has_cargo(self): return false
	is_returning_to_base = false
	is_acting = true
	_coroner_stage = "morgue"
	_coroner_wait = 8.0
	get_node("/root/CoronerCare").morgue_arrival(self)
	return true

func _leave_morgue() -> void:
	var cemetery := get_tree().get_first_node_in_group("cemetery")
	if cemetery == null:
		_coroner_wait = 10.0
		return
	_cemetery_target_position = cemetery.get_coroner_stop_position()
	_coroner_stage = "cemetery"
	is_acting = false
	is_returning_to_base = false
	is_heading_to_cemetery = true
	deployed_morticians = 0
	returned_morticians = 0
	set_meta("depot_departure_pending", true)
	if int(get_meta("harbor_director_id",0))>0:
		var north_exit := _coroner_north_departure()
		if not north_exit.is_empty(): set_meta("depot_departure_waypoints",north_exit)
		_depot_driveway.cursor = 1
	_hospital_arrival.reset()
	_lane_router.reset()
	var care := get_node("/root/CoronerCare")
	for key in get_meta("coroner_cargo", []): care.set_phase(key, "cemetery")

func _coroner_north_departure() -> PackedVector2Array:
	# The cemetery is served via the yard's east driveway and a northbound
	# lane, avoiding the busy southern hospital entrance on the funeral leg.
	var gate: Vector2 = get_meta("depot_road_gate",global_position)
	var merge := Vector2.INF
	var best := INF
	for path in get_tree().get_nodes_in_group("unified_traffic_lane"):
		if not path is Path2D or path.curve==null or not path.can_process(): continue
		var offset: float = path.curve.get_closest_offset(path.to_local(gate))
		var pose: Transform2D = path.global_transform*path.curve.sample_baked_with_rotation(offset,true)
		if pose.x.y>-.8 or pose.origin.x<global_position.x+90: continue
		var distance := pose.origin.distance_to(gate)
		if distance<best and distance<160: best=distance; merge=pose.origin
	if not merge.is_finite(): return PackedVector2Array()
	var points := PackedVector2Array([global_position])
	var center := Vector2(merge.x-70,global_position.y-70)
	for i in 13:
		points.append(center+Vector2.from_angle(lerpf(PI*.5,0,i/12.0))*70)
	points.append(Vector2(merge.x,global_position.y-140))
	return points

func _get_road_guidance_target(dest: Vector2) -> Vector2:
	if type==0 and is_instance_valid(target) and target.get_meta("bank_blockade",false) and global_position.distance_to(dest)<300:
		# A última manobra do cerco sai da faixa até a vaga, sem atravessar sólidos.
		var maneuver: Vector2=dest
		if target.has_meta("bank_approach_position"):
			var approach: Vector2=target.get_meta("bank_approach_position")
			if global_position.x>approach.x+10: maneuver=approach
		var ray:=PhysicsRayQueryParameters2D.create(global_position,maneuver,1|2)
		ray.exclude=[get_rid()]
		if get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return maneuver
	if has_meta("depot_road_gate"):
		var gate: Vector2 = get_meta("depot_road_gate")
		if is_returning_to_base:
			# Only the authored driveway permits leaving the road on return.
			var driveway := Geometry2D.get_closest_point_to_segment(global_position, gate, home_return_position)
			if global_position.distance_to(driveway) <= 30.0:
				return home_return_position
			return _lane_router.guidance(self, gate)
		if bool(get_meta("depot_departure_pending", false)):
			if global_position.distance_to(gate) > 28.0:
				return gate
			set_meta("depot_departure_pending", false)
			_lane_router.reset()
	var routed_target: Vector2 = _lane_router.guidance(self, dest)
	if is_instance_valid(_lane_router.network) or is_instance_valid(_lane_router.linked_lane):
		return routed_target
	# Legacy CentralDistrict loops have no canonical connections. Keep their
	# existing guidance only in scenes without a routable unified network.
	# Road lanes are the source of truth for city movement.  The old direct
	# line-of-sight shortcut let police cut diagonally over pavements and across
	# traffic whenever no building happened to be in the way.
	var best_lane: Path2D = null
	var best_score := INF
	var candidate_lanes: Array[Node] = []
	candidate_lanes.append_array(get_tree().get_nodes_in_group("unified_traffic_lane"))
	for node in candidate_lanes:
		var lane := node as Path2D
		if lane == null or not lane.can_process() or lane.curve == null or lane.curve.get_point_count() < 2:
			continue
		var from_offset := lane.curve.get_closest_offset(lane.to_local(global_position))
		var to_offset := lane.curve.get_closest_offset(lane.to_local(dest))
		var from_point := lane.to_global(lane.curve.sample_baked(from_offset, true))
		var to_point := lane.to_global(lane.curve.sample_baked(to_offset, true))
		var score := global_position.distance_to(from_point) + dest.distance_to(to_point)
		if score < best_score:
			best_score = score
			best_lane = lane
	if best_lane != null:
		var curve := best_lane.curve
		var current_offset := curve.get_closest_offset(best_lane.to_local(global_position))
		var current_point := best_lane.to_global(curve.sample_baked(current_offset, true))
		# A depot apron may start beside the lane; this is the sole permitted
		# short off-road move before the unit merges into a road centre-line.
		if global_position.distance_to(current_point) > 54.0:
			return current_point
		var target_offset := curve.get_closest_offset(best_lane.to_local(dest))
		var length := maxf(curve.get_baked_length(), 1.0)
		var endpoint := best_lane.to_global(curve.sample_baked(target_offset, true))
		if global_position.distance_to(endpoint) < 28.0:
			return dest if endpoint.distance_to(dest) <= 32.0 else global_position
		# Open mountain roads must never wrap from their end to their beginning.
		var closed := curve.get_point_position(0).distance_to(curve.get_point_position(curve.point_count - 1)) < 5.0
		var lookahead := current_offset + 70.0
		if closed:
			lookahead = fposmod(lookahead, length)
		else:
			lookahead = minf(lookahead, length)
		return best_lane.to_global(curve.sample_baked(lookahead, true))
	# No authored pavement means no safe vehicular route.
	return global_position

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
	var factor = clampf(impact_force / 450.0, 0.05, 0.28)
	
	# A viatura NUNCA estica nem diminui: preserva proporção e escala rígidas
	visual.position = Vector2.ZERO
	visual.skew = 0.0

	# Escurecimento sutil (arranhões e fuligem na lataria)
	visual.modulate = visual.modulate.lerp(Color(0.60, 0.60, 0.62), 0.06 * (factor / 0.28))
	
	if hit_world_pos != Vector2.ZERO and dents_container:
		var local_hit: Vector2 = to_local(hit_world_pos)
		local_hit.x = clampf(local_hit.x, -40.0, 40.0)
		local_hit.y = clampf(local_hit.y, -18.0, 18.0)
		_spawn_dent_decal(local_hit, -local_norm, factor)
		
	var crumple_player = AudioStreamPlayer2D.new()
	crumple_player.stream = ProceduralAudio.get_metal_crumple_stream()
	crumple_player.volume_db = -10.0
	crumple_player.pitch_scale = randf_range(0.85, 1.15)
	crumple_player.max_distance = 500.0
	add_child(crumple_player)
	crumple_player.play()
	crumple_player.finished.connect(crumple_player.queue_free)

func _spawn_dent_decal(local_pos: Vector2, dir: Vector2, strength: float) -> void:
	if dents_container == null: return
	if dents_container.get_child_count() > 8:
		dents_container.get_child(0).queue_free()
		
	# Shallow paint scratches stay inside the sprite's body, including corners.
	var scratch := Line2D.new()
	var center := Vector2(clampf(local_pos.x, -30, 30), clampf(local_pos.y, -11, 11))
	var tangent := dir.orthogonal().normalized() * clampf(3.0 + strength * 10.0, 3.0, 6.0)
	scratch.points = PackedVector2Array([center - tangent, center + tangent])
	scratch.width = 0.8
	scratch.default_color = Color(0.34, 0.35, 0.37, 0.7)
	dents_container.add_child(scratch)

func _clear_all_dents() -> void:
	if dents_container:
		for child in dents_container.get_children():
			child.queue_free()

func finish_hospital_parking() -> void:
	set_meta("hospital_available",true)
	set_meta("hospital_unloading",false)
	set_meta("hospital_arrived",true)
	set_meta("medical_phase","parked")
	remove_meta("medical_waiting_admission")
	is_acting = false
	is_returning_to_base = false
	is_reversing = false
	target = null
	velocity = Vector2.ZERO
	current_speed = 0
	if siren_audio: siren_audio.stop()
	if lights: lights.hide()
	if engine_audio: engine_audio.stop()
	var owner_id := int(get_meta("harbor_director_id",0))
	var director: Node = instance_from_id(owner_id) if owner_id else get_tree().get_first_node_in_group("emergency_depot_director")
	if is_instance_valid(director): director.complete_vehicle_return(self)

func _update_response_audio() -> void:
	# A patient aboard is still an emergency response; only an empty return
	# should silence the ambulance and switch its warning lights off.
	var medical_sequence: Node = get_meta("medical_sequence") if has_meta("medical_sequence") else null
	var patient_transport: bool = type == 1 and is_instance_valid(medical_sequence) and medical_sequence.delivered and medical_sequence.phase == "transport"
	var responding := visible and not is_broken and ((not is_returning_to_base and is_instance_valid(target)) or patient_transport)
	if type == 0:
		var wanted := get_node_or_null("/root/WantedManager")
		responding = responding and ((is_instance_valid(target) and target.get_meta("ambient_crime",false)) or (wanted != null and wanted.current_stars > 0))
		if responding and target.get_meta("police_search_position", false):
			responding = global_position.distance_to(target.global_position) > 240.0
	if lights: lights.visible = responding
	if siren_audio:
		var sounding := responding and not is_acting and not bool(get_meta("medical_waiting_admission", false)) and not bool(get_meta("hospital_arrived",false)) and not bool(get_meta("hospital_dock_waiting",false)) and not bool(get_meta("hospital_parking_wait",false))
		if sounding: siren_audio.volume_db = -10.0
		if sounding and not siren_audio.playing: siren_audio.play()
		elif not sounding and siren_audio.playing: siren_audio.stop()
