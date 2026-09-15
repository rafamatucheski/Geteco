## Procedural, texture-free combat feedback for a top-down Godot 4 game.
##
## Add one WeaponEffects node to the current scene (or make it an autoload), then
## call the public spawn_* methods below from the weapon/projectile code.
class_name WeaponEffects
extends Node2D

@export var effects_enabled := true
@export_range(8, 256, 1) var max_live_effects := 96

var _live_effects := 0



func _ready() -> void:
	# Effects are drawn in world space above roads, but below UI CanvasLayers.
	z_index = 20
	add_to_group("weapon_effects")


func spawn_muzzle_flash(origin: Vector2, direction: Vector2, weapon: Dictionary = {}) -> void:
	if not effects_enabled or not _can_spawn():
		return
	var radius := float(weapon.get("flash_radius", 8.0))
	var life := float(weapon.get("flash_lifetime", 0.055))
	var flash := _MuzzleFlash.new()
	flash.setup(origin, direction, radius, life)
	_add_effect(flash)


func spawn_shell(origin: Vector2, direction: Vector2, weapon: Dictionary = {}) -> void:
	if not effects_enabled or not _can_spawn():
		return
	# Shotguns can opt out, or use a larger shell.
	if not (weapon.get("ejects_shell", true) == true):
		return
	var shell := _ShellCasing.new()
	var side := direction.rotated(PI * 0.5)
	var shell_seed := _random_signed()
	shell.setup(
		origin + side * 4.0,
		side * (58.0 + absf(shell_seed) * 25.0) + direction * (18.0 * shell_seed),
		float(weapon.get("shell_size", 0.75)),
		maxf(1.6, float(weapon.get("shell_lifetime", 0.72)))
	)
	_add_effect(shell)


func spawn_impact(
	pos: Vector2,
	normal: Vector2 = Vector2.ZERO,
	surf_material: StringName = &"world",
	damage: float = 0.0
) -> void:
	if not effects_enabled or not _can_spawn():
		return
	var impact := _ImpactBurst.new()
	impact.setup(pos, normal, surf_material, damage)
	_add_effect(impact)


func spawn_blood(pos: Vector2, direction: Vector2, damage: float = 0.0) -> void:
	if not effects_enabled or not _can_spawn():
		return
	var blood := _BloodBurst.new()
	blood.setup(pos, direction, damage)
	_add_effect(blood)


func spawn_vehicle_splash(pos: Vector2, incoming: Vector2, lethal: bool) -> void:
	if not effects_enabled or not _can_spawn():
		return
	if get_tree().get_nodes_in_group("vehicle_splashes").size() >= 12:
		return
	var splash := preload("res://guns/combat/VehicleSplash.gd").new()
	splash.setup(pos, incoming, lethal)
	splash.add_to_group("vehicle_splashes")
	_add_effect(splash)
	splash.global_position = pos


func spawn_empty_click(origin: Vector2) -> void:
	if not effects_enabled or not _can_spawn():
		return
	var click := _EmptyClick.new()
	click.setup(origin)
	_add_effect(click)


func _can_spawn() -> bool:
	return is_inside_tree() and _live_effects < max_live_effects


func _add_effect(effect: Node2D) -> void:
	_live_effects += 1
	effect.tree_exited.connect(_on_effect_exited, CONNECT_ONE_SHOT)
	add_child(effect)


func _on_effect_exited() -> void:
	_live_effects = maxi(0, _live_effects - 1)


func _random_signed() -> float:
	return randf() * 2.0 - 1.0


class _BaseEffect:
	extends Node2D
	var age := 0.0
	var duration := 0.25

	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age >= duration:
			queue_free()

	func progress() -> float:
		return clampf(age / maxf(duration, 0.001), 0.0, 1.0)


class _MuzzleFlash:
	extends _BaseEffect
	var direction := Vector2.RIGHT
	var radius := 8.0
	var flash_duration := 0.06
	var variation := 1.0

	func setup(world_position: Vector2, facing: Vector2, flash_radius: float, life: float) -> void:
		global_position = world_position
		direction = facing.normalized() if not facing.is_zero_approx() else Vector2.RIGHT
		radius = maxf(2.0, flash_radius)
		flash_duration = clampf(life, 0.045, 0.09)
		duration = 0.28
		variation = randf_range(0.85, 1.15)

	func _draw() -> void:
		var smoke_fade := sin(progress() * PI) * 0.16
		for i in 3:
			var smoke_pos := direction * (4.0 + age * (28.0 + float(i)*9.0)) + Vector2(0,-age*15.0)
			draw_circle(smoke_pos, radius*(0.18+progress()*0.32), Color(0.48,0.46,0.40,smoke_fade), true, -1, true)
		var fade := maxf(0.0, 1.0 - age / flash_duration)
		if fade <= 0.0: return
		var length := radius * (1.2 + fade) * variation
		var side := direction.orthogonal()
		var points := PackedVector2Array([Vector2.ZERO, direction*length*0.36+side*radius*0.35,
			direction*length*0.54+side*radius*0.14, direction*length,
			direction*length*0.48-side*radius*0.17, direction*length*0.26-side*radius*0.31])
		draw_colored_polygon(points, Color(1.0,0.36,0.025,fade*0.9))
		for i in points.size(): points[i] *= 0.65
		draw_colored_polygon(points, Color(1.0,0.83,0.32,fade))
		draw_line(Vector2.ZERO,direction*length*0.46,Color(1.0,0.98,0.8,fade),2.0,true)


class _ShellCasing:
	extends _BaseEffect
	var velocity := Vector2.ZERO
	var size := 0.75
	var spin := 0.0
	var angular_velocity := 0.0
	var height := 7.0
	var lift := 72.0
	var bounces := 0

	func setup(world_position: Vector2, initial_velocity: Vector2, casing_size: float, life: float) -> void:
		global_position = world_position
		velocity = initial_velocity
		size = maxf(0.3, casing_size)
		duration = maxf(0.2, life)
		angular_velocity = randf_range(-16.0, 16.0)

	func _process(delta: float) -> void:
		lift -= 360.0 * delta
		height += lift * delta
		if height <= 0.0:
			height = 0.0
			if lift < -24.0 and bounces < 2:
				lift = -lift * 0.35
				bounces += 1
				velocity *= 0.52
				angular_velocity *= 0.5
			else:
				lift = 0.0
				angular_velocity = move_toward(angular_velocity,0.0,80.0*delta)
		velocity = velocity.move_toward(Vector2.ZERO, (160.0 if height <= 0.0 else 20.0) * delta)
		global_position += velocity * delta
		spin += angular_velocity * delta
		super._process(delta)

	func _draw() -> void:
		var fade := minf(1.0, (1.0 - progress()) * 2.5)
		var long_axis := Vector2(cos(spin), sin(spin)) * size
		var short_axis := long_axis.rotated(PI * 0.5) * 0.42
		var polygon := PackedVector2Array([
			-long_axis - short_axis, long_axis - short_axis,
			long_axis + short_axis, -long_axis + short_axis
		])
		draw_line(-long_axis,long_axis,Color(0.05,0.04,0.02,fade*0.28),size*0.65,true)
		for i in polygon.size(): polygon[i].y -= height
		draw_colored_polygon(polygon, Color(0.73, 0.44, 0.10, fade))
		var offset := Vector2(0,-height)
		draw_line(offset-long_axis*0.8,offset+long_axis*0.8,Color(1,0.82,0.39,fade),size*0.32,true)
		draw_line(offset-long_axis-short_axis,offset-long_axis+short_axis,Color(0.38,0.23,0.07,fade),size*0.4,true)


class _ImpactBurst:
	extends _BaseEffect
	var normal := Vector2.ZERO
	var impact_surface: StringName = &"world"
	var strength := 1.0

	func setup(world_position: Vector2, surface_normal: Vector2, surface_material: StringName, damage: float) -> void:
		global_position = world_position
		normal = surface_normal.normalized()
		impact_surface = surface_material
		strength = clampf(0.7 + damage / 55.0, 0.7, 1.8)
		duration = 0.16

	func _draw() -> void:
		var fade := 1.0 - progress()
		var spark_color := Color(1.0, 0.74, 0.2, fade)
		if impact_surface == &"flesh":
			spark_color = Color(0.72, 0.04, 0.03, fade)
		elif impact_surface == &"concrete":
			spark_color = Color(0.76, 0.74, 0.65, fade)
		elif impact_surface == &"metal":
			spark_color = Color(1.0, 0.95, 0.55, fade)
		elif impact_surface == &"wood":
			spark_color = Color(0.64, 0.39, 0.18, fade)
		elif impact_surface == &"glass":
			spark_color = Color(0.65, 0.9, 1.0, fade)
		var away := normal if not normal.is_zero_approx() else Vector2.RIGHT
		for i in range(5):
			var angle := away.angle() + (-0.7 + float(i) * 0.35)
			var ray := Vector2.from_angle(angle) * (4.0 + float(i % 3) * 2.0) * strength * (0.4 + progress())
			draw_line(Vector2.ZERO, ray, spark_color, 1.3)
		draw_circle(Vector2.ZERO, 1.8 * strength, spark_color)


class _BloodBurst:
	extends _BaseEffect
	var direction := Vector2.RIGHT
	var strength := 1.0

	func setup(world_position: Vector2, travel_direction: Vector2, damage: float) -> void:
		# The emitter can live beneath a moving/transformed world container.
		top_level = true
		global_position = world_position
		direction = travel_direction.normalized() if not travel_direction.is_zero_approx() else Vector2.RIGHT
		strength = clampf(0.6 + damage / 45.0, 0.6, 1.7)
		duration = 0.28

	func _draw() -> void:
		var fade := 1.0 - progress()
		var color := Color(0.55, 0.02, 0.015, fade)
		for i in range(4):
			var velocity := direction.rotated(-0.42 + float(i) * 0.28) * (48.0 + float(i) * 19.0) * strength
			var offset := velocity * age + Vector2(0.0, 90.0 * age * age)
			var tangent := (velocity + Vector2(0.0, 180.0 * age)).normalized()
			var length := (1.8 + float(i % 3) * 0.6) * strength * fade
			draw_line(offset - tangent * length, offset, color, maxf(0.45, 0.9 * strength * fade), true)


class _EmptyClick:
	extends _BaseEffect
	func setup(world_position: Vector2) -> void:
		global_position = world_position
		duration = 0.12

	func _draw() -> void:
		var fade := 1.0 - progress()
		draw_arc(Vector2.ZERO, 6.0 + progress() * 5.0, 0.0, TAU, 12, Color(0.8, 0.8, 0.75, fade), 1.0)


class _CrashBurst:
	extends _BaseEffect
	var direction := Vector2.RIGHT
	var strength := 1.0

	func _draw() -> void:
		var fade := clampf((duration - age) / duration, 0.0, 1.0)
		for i in 8:
			var ray := direction.rotated(-1.1 + float(i) * 0.28)
			var travel := minf(age, 0.40)
			var pos := ray * (16.0 + float(i % 4) * 8.0) * strength * (1.0 - exp(-travel * 6.0))
			pos.y -= maxf(0.0, 20.0 * travel - 55.0 * travel * travel)
			var axis := Vector2.from_angle(float(i) + travel * 6.0) * (0.8 + strength * 0.6)
			var color := Color(0.64, 0.84, 0.89, fade * 0.7) if i % 3 == 0 else Color(0.42, 0.43, 0.45, fade * 0.85)
			draw_colored_polygon(PackedVector2Array([pos - axis, pos + axis, pos + axis.orthogonal() * 0.5]), color)
			if age < 0.18 and i % 2 == 0:
				draw_line(pos - ray * 5.0, pos, Color(1.0, 0.78, 0.25, (1.0 - age / 0.18) * 0.8), 1.0, true)


class _PostSparkBurst:
	extends _BaseEffect
	var direction := Vector2.RIGHT
	var strength := 1.0

	func _draw() -> void:
		var fade := 1.0 - progress()
		var away := direction if not direction.is_zero_approx() else Vector2.RIGHT
		for i in 8:
			var angle := away.angle() + (-0.65 + float(i) * 0.18) + sin(float(i) * 2.7) * 0.1
			var travel := progress()
			var spark_dist := (14.0 + float(i % 4) * 7.0) * strength * (1.0 - exp(-travel * 7.0))
			var end_pt := Vector2.from_angle(angle) * spark_dist
			var spark_len := maxf(1.5, (3.5 + float(i % 3)) * (1.0 - travel) * strength)
			var start_pt := end_pt - Vector2.from_angle(angle) * spark_len
			var spark_col := Color(1.0, 0.96, 0.70, fade) if i % 3 == 0 else Color(1.0, 0.72, 0.18, fade * 0.9)
			draw_line(start_pt, end_pt, spark_col, 1.15, true)
		if age < 0.10:
			var core_fade := (1.0 - age / 0.10) * 0.75
			draw_circle(Vector2.ZERO, 2.0 * strength, Color(1.0, 0.95, 0.75, core_fade))


static func spawn_crash(parent: Node, origin: Vector2, normal: Vector2, speed: float) -> void:
	if speed < 80.0 or not is_instance_valid(parent) or not parent.is_inside_tree(): return
	if parent.get_tree().get_nodes_in_group("crash_bursts").size() >= 24: return
	var burst := _CrashBurst.new()
	burst.direction = normal.normalized()
	burst.strength = clampf(speed / 320.0, 0.25, 1.0)
	burst.duration = 0.45
	parent.add_child(burst)
	burst.global_position = origin
	burst.z_as_relative = false
	burst.z_index = 21
	burst.add_to_group("crash_bursts")

static func spawn_post_impact(parent: Node, origin: Vector2, normal: Vector2, speed: float) -> void:
	if speed < 30.0 or not is_instance_valid(parent) or not parent.is_inside_tree(): return
	if parent.get_tree().get_nodes_in_group("post_sparks").size() >= 16: return
	var burst := _PostSparkBurst.new()
	burst.direction = normal.normalized() if not normal.is_zero_approx() else Vector2.RIGHT
	burst.strength = clampf(speed / 260.0, 0.35, 1.0)
	burst.duration = 0.24
	parent.add_child(burst)
	burst.global_position = origin
	burst.z_as_relative = false
	burst.z_index = 21
	burst.add_to_group("post_sparks")
