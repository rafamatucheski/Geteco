extends Node2D
## One continuous stream, one blocking ray, bounded splash particles.
const REACH := 420.0
const DAMAGE := 3
const HIT_INTERVAL := 0.20
const WASH := preload("res://emergency/VehicleWaterWash.gd")
const SUPPRESSION := preload("res://emergency/FireSuppression.gd")
const MATERIAL := preload("res://audio/combat/ImpactMaterial.gd")

var vehicle: CharacterBody2D
var firing := false
var controlled := false
var impact_position := Vector2.ZERO
var hit_target: Node
var _muzzle := Vector2.ZERO
var _aim := Vector2.ZERO
var _clock := 0.0
var _hit_clock := 0.0
var _stream := PackedVector2Array()
var _audio: AudioStreamPlayer2D
var _splash: CPUParticles2D

static func sync_vehicle(body: CharacterBody2D, enabled: bool) -> void:
	var existing := body.get_node_or_null("WaterCannon")
	if not enabled:
		if existing:
			body.remove_child(existing)
			existing.queue_free()
		return
	if existing: return
	var cannon := load("res://emergency/VehicleWaterCannon.gd").new() as Node2D
	cannon.name = "WaterCannon"
	cannon.vehicle = body
	body.add_child(cannon)

func _ready() -> void:
	z_index = 12
	_audio = AudioStreamPlayer2D.new()
	_audio.stream = ProceduralAudio.get_water_stream()
	_audio.bus = &"SFX"
	_audio.volume_db = -17.0
	_audio.max_distance = 700.0
	add_child(_audio)
	_splash = CPUParticles2D.new()
	_splash.emitting = false
	_splash.amount = 36
	_splash.lifetime = 0.30
	_splash.local_coords = false
	_splash.spread = 100.0
	_splash.initial_velocity_min = 28.0
	_splash.initial_velocity_max = 90.0
	_splash.gravity = Vector2(0, 42)
	_splash.scale_amount_min = 1.0
	_splash.scale_amount_max = 2.6
	var droplet := GradientTexture2D.new()
	droplet.width = 16
	droplet.height = 16
	droplet.fill = GradientTexture2D.FILL_RADIAL
	droplet.fill_from = Vector2(0.5, 0.5)
	droplet.fill_to = Vector2(1, 0.5)
	droplet.gradient = Gradient.new()
	droplet.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	_splash.texture = droplet
	_splash.scale_amount_min = 0.14
	_splash.scale_amount_max = 0.35
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.8, 0.95, 1, 0.85), Color(0.65, 0.85, 1, 0)])
	_splash.color_ramp = gradient
	add_child(_splash)

func can_operate() -> bool:
	if not is_instance_valid(vehicle) or not vehicle.is_visible_in_tree() or not vehicle.can_process(): return false
	if vehicle.get("is_driven_by_player") != true or vehicle.get("is_broken") == true or vehicle.get("is_exploded") == true: return false
	if vehicle.has_meta("vehicle_boarding"): return false
	var driver: Node = vehicle.get("_driver")
	if not is_instance_valid(driver): return false
	for flag in ["is_dead", "is_arrested", "is_control_disabled", "is_in_dialogue"]:
		if driver.get(flag) == true: return false
	return not get_tree().paused

func _physics_process(delta: float) -> void:
	_clock += delta
	_hit_clock = maxf(0.0, _hit_clock - delta)
	controlled = can_operate()
	if not controlled:
		stop()
		return
	var controls := get_node("/root/GameInput")
	_aim = controls.aim_target(vehicle)
	_update_turret()
	var wants_fire: bool = Input.is_action_pressed("fire") and not controls.remapping
	if get_viewport().gui_get_hovered_control() != null: wants_fire = false
	if not wants_fire:
		stop()
		return
	firing = true
	if not _audio.playing: _audio.play()
	_trace_stream()
	if _hit_clock <= 0.0:
		_hit_clock = HIT_INTERVAL
		_apply_hit(hit_target)
	_splash.global_position = impact_position
	_splash.direction = -_muzzle.direction_to(impact_position)
	_splash.emitting = true
	_build_stream()
	queue_redraw()

func _update_turret() -> void:
	_muzzle = vehicle.global_position
	var model: Node3D = vehicle.get("body_model")
	if not is_instance_valid(model) or not is_instance_valid(model.get("water_turret")): return
	var camera: Camera3D = model.get_viewport().get_camera_3d()
	var sprite: Sprite2D = vehicle.get("visual")
	if camera == null or sprite == null: return
	var turret: Node3D = model.get("water_turret")
	var origin_pixel := camera.unproject_position(turret.global_position)
	var origin := sprite.to_global(origin_pixel - Vector2(model.get_viewport().size) * 0.5)
	var direction := origin.direction_to(_aim)
	# Undo the camera's ground foreshortening to aim the barrel at the cursor.
	direction.y /= maxf(0.2, absf(camera.global_basis.y.y))
	var heading := -direction.angle() - PI * 0.5 - model.rotation.y
	var changed := absf(angle_difference(turret.rotation.y, heading)) > 0.002
	turret.rotation.y = heading
	var muzzle: Node3D = model.get("water_muzzle")
	_muzzle = sprite.to_global(camera.unproject_position(muzzle.global_position) - Vector2(model.get_viewport().size) * 0.5)
	if changed: model.get_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE

func _trace_stream() -> void:
	var end := _muzzle + (_aim - _muzzle).limit_length(REACH)
	var query := PhysicsRayQueryParameters2D.create(_muzzle, end, 1 | 2 | 4)
	query.exclude = [vehicle.get_rid()]
	var driver: Node = vehicle.get("_driver")
	if driver is CollisionObject2D: query.exclude = [vehicle.get_rid(), driver.get_rid()]
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	impact_position = hit.get("position", end)
	hit_target = hit.get("collider")

func _apply_hit(target: Node) -> void:
	if not is_instance_valid(target): return
	var subject := target
	for depth in 5:
		var cooling := subject is Node2D and SUPPRESSION.is_active(subject)
		if cooling: SUPPRESSION.apply_water(subject, HIT_INTERVAL)
		if subject.is_in_group("vehicle") or subject.is_in_group("ambient_traffic"):
			WASH.apply(subject)
			return
		if cooling: return
		if subject.has_method("take_damage") and MATERIAL.resolve(subject) == &"flesh":
			subject.take_damage(DAMAGE, true)
			return
		subject = subject.get_parent()
		if subject == null: return

func _build_stream() -> void:
	_stream.clear()
	var sideways := _muzzle.direction_to(impact_position).orthogonal()
	for i in 33:
		var t := float(i) / 32.0
		var ripple := sin(t * 24.0 - _clock * 32.0) * 0.55 * sin(t * PI)
		_stream.append(to_local(_muzzle.lerp(impact_position, t) + sideways * ripple))

func stop() -> void:
	firing = false
	hit_target = null
	_stream.clear()
	if _audio: _audio.stop()
	if _splash: _splash.emitting = false
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_DISABLED, NOTIFICATION_EXIT_TREE]:
		controlled = false
		stop()

func _draw() -> void:
	if firing and _stream.size() > 1:
		draw_polyline(_stream, Color(0.20, 0.64, 0.95, 0.18), 10.0, true)
		draw_polyline(_stream, Color(0.48, 0.82, 1, 0.65), 4.5, true)
		draw_polyline(_stream, Color(0.85, 0.96, 1, 0.75), 1.4, true)
		for i in 12:
			var t := fposmod(float(i) / 12.0 + _clock * 2.5, 1.0)
			draw_circle(to_local(_muzzle.lerp(impact_position, t)), 1.0 + t, Color(0.86, 0.97, 1, 0.75))
		var side := _muzzle.direction_to(impact_position).orthogonal()
		for i in 18:
			var t := fposmod(float(i) * 0.173 + _clock * 1.8, 1.0)
			var spread := sin(float(i) * 13.7) * t * t * 8.0
			var point := to_local(_muzzle.lerp(impact_position, t) + side * spread)
			draw_circle(point, 0.7 + t * 0.8, Color(0.7, 0.91, 1, 0.4 * t))
	if controlled:
		var target := to_local(_muzzle + (_aim - _muzzle).limit_length(REACH))
		var tint := Color(0.5, 0.9, 1, 0.85)
		draw_arc(target, 7, 0, TAU, 24, tint, 1.2, true)
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			draw_line(target - axis * 11, target - axis * 5, tint, 1, true)
			draw_line(target + axis * 5, target + axis * 11, tint, 1, true)
