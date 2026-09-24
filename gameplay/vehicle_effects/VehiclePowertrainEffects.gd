extends Node
## Normal exhaust with idle micro-wisps, punch puffs and damage smoke with wake deflection.

const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const BACKFIRE_SPEED := 220.0/16.0

var vehicle: CharacterBody3D
var exhaust: GPUParticles3D
var damage_smoke: GPUParticles3D
var backfire: GPUParticles3D
var previous_throttle := 0.0
var rng := RandomNumberGenerator.new()

func configure(car: CharacterBody3D) -> void:
	vehicle = car
	rng.seed = 1777+car.get_instance_id()*31

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void:
	clear_all()

func physics_tick(active: bool) -> void:
	var throttle: float = vehicle.throttle_input
	if not active:
		_stop()
		previous_throttle = throttle
		return
	var engine_running: bool = vehicle.health>0 and not vehicle.engine_disabled and (vehicle.controlled or vehicle.traffic or vehicle.external_input or absf(vehicle.speed)>.15)
	var health_ratio: float = vehicle.health/maxf(1,vehicle.max_health)
	if engine_running:
		_ensure_exhaust()
		_update_exhaust(throttle)
	elif is_instance_valid(exhaust): exhaust.emitting = false
	if health_ratio < .5 and vehicle.health > 0:
		_ensure_damage_smoke()
		_update_damage_smoke(health_ratio)
	elif is_instance_valid(damage_smoke): damage_smoke.emitting = false
	if engine_running and previous_throttle>.5 and throttle<=0 and absf(vehicle.speed)>BACKFIRE_SPEED and rng.randf()>.4: _emit_backfire()
	previous_throttle = throttle

func _ensure_exhaust() -> void:
	if is_instance_valid(exhaust): return
	exhaust = RESOURCES.emitter("NormalExhaust",14,.62,Vector2(.15,.15),true)
	exhaust.process_material = RESOURCES.particle_process()
	vehicle.add_child(exhaust)
	exhaust.top_level = true

func _ensure_damage_smoke() -> void:
	if is_instance_valid(damage_smoke): return
	damage_smoke = RESOURCES.emitter("DamageSmoke",28,1.20,Vector2(.38,.38),true)
	damage_smoke.process_material = RESOURCES.particle_process()
	vehicle.add_child(damage_smoke)
	damage_smoke.top_level = true

func _ensure_backfire() -> void:
	if is_instance_valid(backfire): return
	backfire = RESOURCES.emitter("ExhaustBackfire",12,.18,Vector2(.075,.22),false)
	backfire.one_shot = true
	backfire.explosiveness = 1.0
	backfire.process_material = RESOURCES.particle_process(false)
	vehicle.add_child(backfire)
	backfire.top_level = true

func _update_exhaust(throttle: float) -> void:
	var process := exhaust.process_material as ParticleProcessMaterial
	var speed: float = absf(vehicle.speed)
	var is_idle: bool = speed < 0.6 and absf(throttle) < 0.05
	var throttle_punch: bool = (throttle - previous_throttle) > 0.18 and throttle > 0.3
	var h_vel: Vector3 = vehicle.horizontal_velocity
	var air_wake: Vector3 = -h_vel.normalized() * clampf(speed / 14.0, 0.0, 0.6) if speed > 0.1 else Vector3.ZERO
	process.direction = (vehicle.global_basis.z * .82 + Vector3.UP * .24 + air_wake * .3).normalized()
	process.spread = 28.0
	if is_idle:
		process.initial_velocity_min = .12
		process.initial_velocity_max = .36
		process.gravity = Vector3(0, .26, 0)
		process.scale_min = .26
		process.scale_max = .60
		process.color = Color(.78, .80, .82, .18)
		exhaust.amount_ratio = .28
	elif throttle_punch:
		process.initial_velocity_min = .65
		process.initial_velocity_max = 1.45 + speed * .03
		process.gravity = Vector3(0, .14, 0)
		process.scale_min = .38
		process.scale_max = 1.15
		process.color = Color(.60, .64, .66, .38)
		exhaust.amount_ratio = clampf(.55 + absf(throttle) * .40 + speed / 40.0, .45, 1.0)
	else:
		process.initial_velocity_min = .28
		process.initial_velocity_max = .80 + speed * .025
		process.gravity = Vector3(0, .18, 0)
		process.scale_min = .35
		process.scale_max = .95
		process.color = Color(.72, .75, .76, .24)
		exhaust.amount_ratio = clampf(.28 + absf(throttle) * .42 + speed / 55.0, .25, .88)
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.angular_velocity_min = -1.2
	process.angular_velocity_max = 1.2
	exhaust.global_position = vehicle.to_global(Vector3(vehicle.half_width * .42, .38, vehicle.half_length * .94))
	exhaust.emitting = true

func _update_damage_smoke(health_ratio: float) -> void:
	var severity: float = clampf((.5 - health_ratio) / .5, 0.0, 1.0)
	var process := damage_smoke.process_material as ParticleProcessMaterial
	var speed: float = vehicle.horizontal_velocity.length()
	var h_vel: Vector3 = vehicle.horizontal_velocity
	var air_wake: Vector3 = -h_vel.normalized() * clampf(speed / 10.0, 0.0, 1.4) if speed > 0.1 else Vector3.ZERO
	process.direction = (Vector3.UP * 1.15 + air_wake * 0.85).normalized()
	process.spread = 32.0 + severity * 8.0
	process.initial_velocity_min = .45 + severity * .25
	process.initial_velocity_max = 1.15 + severity * .65 + speed * .03
	process.gravity = Vector3(0, .32, 0)
	process.scale_min = lerpf(.26, .38, severity)
	process.scale_max = lerpf(.80, 1.45, severity)
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.angular_velocity_min = -1.8
	process.angular_velocity_max = 1.8
	process.color = Color(.68, .70, .72, .48).lerp(Color(.15, .16, .17, .82), smoothstep(.30, 0.95, severity))
	damage_smoke.global_position = vehicle.to_global(Vector3(0, .72, -vehicle.half_length * .54))
	damage_smoke.amount_ratio = lerpf(.35, 1.0, severity)
	damage_smoke.emitting = true

func _emit_backfire() -> void:
	_ensure_backfire()
	var process := backfire.process_material as ParticleProcessMaterial
	process.direction = vehicle.global_basis.z
	process.spread = 22
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.4
	process.gravity = Vector3.ZERO
	process.scale_min = .5
	process.scale_max = 1.0
	process.color = Color("f39c12")
	backfire.global_position = vehicle.to_global(Vector3(vehicle.half_width*.42,.38,vehicle.half_length*.98))
	backfire.restart()

func _stop() -> void:
	for emitter in [exhaust,damage_smoke]:
		if is_instance_valid(emitter): emitter.emitting = false

func clear_all() -> void:
	_stop()
	if is_instance_valid(backfire): backfire.emitting = false

