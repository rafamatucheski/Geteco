extends Node
## One reusable burst. Per-collider cooldown prevents continuous slide contact spam.

const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const CRASH_AUDIO := preload("res://audio/VehicleCrashAudio.gd")
const MIN_IMPACT_SPEED := 35.0/16.0
const STRONG_IMPACT_SPEED := 180.0/16.0
const CONTACT_COOLDOWN_MSEC := 650
const GLOBAL_COOLDOWN_MSEC := 120

var vehicle: CharacterBody3D
var emitter: GPUParticles3D
var last_by_collider: Dictionary = {}
var last_global_msec := -999999
var burst_count := 0

func configure(car: CharacterBody3D) -> void:
	vehicle = car

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void:
	stop()

func physics_tick(active: bool, incoming_velocity: Vector3) -> void:
	if not active:
		stop()
		return
	for index in vehicle.get_slide_collision_count():
		var contact := vehicle.get_slide_collision(index)
		var normal: Vector3 = contact.get_normal()
		var relative := incoming_velocity - contact.get_collider_velocity()
		var audio_closing := maxf(0,-relative.dot(normal))
		var closing_speed := maxf(0,-incoming_velocity.dot(normal))
		var collider := contact.get_collider()
		# Audio has its own lighter threshold and pair budget; visual bursts stay unchanged.
		CRASH_AUDIO.play_contact(vehicle, collider, contact.get_position(), audio_closing)
		if closing_speed < MIN_IMPACT_SPEED: continue
		var collider_id := collider.get_instance_id() if is_instance_valid(collider) else 0
		present_impact(contact.get_position(),normal,closing_speed,collider_id,-1,collider)

func present_impact(point: Vector3, normal: Vector3, intensity: float, collider_id: int, now_msec := -1, _collider: Object = null) -> bool:
	if intensity < MIN_IMPACT_SPEED: return false
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	if now-last_global_msec < GLOBAL_COOLDOWN_MSEC: return false
	if now-int(last_by_collider.get(collider_id,-999999)) < CONTACT_COOLDOWN_MSEC: return false
	last_global_msec = now
	last_by_collider[collider_id] = now
	if last_by_collider.size() > 16:
		for key in last_by_collider.keys():
			if now-int(last_by_collider[key]) > CONTACT_COOLDOWN_MSEC*2: last_by_collider.erase(key)
	_ensure_emitter()
	var strength := clampf((intensity-MIN_IMPACT_SPEED)/(STRONG_IMPACT_SPEED-MIN_IMPACT_SPEED),0,1)
	var process := emitter.process_material as ParticleProcessMaterial
	process.direction = (normal+Vector3.UP*.25).normalized()
	process.spread = lerpf(42,62,strength)
	process.initial_velocity_min = lerpf(35.0/16.0,50.0/16.0,strength)
	process.initial_velocity_max = lerpf(75.0/16.0,100.0/16.0,strength)
	process.gravity = Vector3(0,-5.5,0)
	process.scale_min = .55
	process.scale_max = 1.0
	process.color = Color(.85,.87,.89,1).lerp(Color(1,.78,.25,1),strength)
	emitter.global_position = point+normal*.035
	emitter.amount_ratio = lerpf(.30,1.0,strength)
	emitter.restart()
	burst_count += 1
	return true

func _ensure_emitter() -> void:
	if is_instance_valid(emitter): return
	emitter = RESOURCES.emitter("VehicleImpactBurst",14,.26,Vector2(.035,.13))
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.process_material = RESOURCES.particle_process()
	vehicle.add_child(emitter)
	emitter.top_level = true

func stop() -> void:
	if is_instance_valid(emitter): emitter.emitting = false
