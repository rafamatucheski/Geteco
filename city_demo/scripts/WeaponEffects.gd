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
		float(weapon.get("shell_size", 2.5)),
		float(weapon.get("shell_lifetime", 0.72))
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

	func setup(world_position: Vector2, facing: Vector2, flash_radius: float, life: float) -> void:
		global_position = world_position
		direction = facing.normalized() if not facing.is_zero_approx() else Vector2.RIGHT
		radius = maxf(2.0, flash_radius)
		duration = maxf(0.02, life)

	func _draw() -> void:
		var fade := 1.0 - progress()
		var tip := direction * radius * (2.2 + fade)
		var wing := direction.rotated(PI * 0.5) * radius * 0.46
		var points := PackedVector2Array([Vector2.ZERO, tip + wing, tip, tip - wing])
		draw_colored_polygon(points, Color(1.0, 0.72, 0.12, fade))
		draw_circle(Vector2.ZERO, radius * 0.55, Color(1.0, 0.96, 0.68, fade))


class _ShellCasing:
	extends _BaseEffect
	var velocity := Vector2.ZERO
	var size := 2.5
	var spin := 0.0
	var angular_velocity := 0.0

	func setup(world_position: Vector2, initial_velocity: Vector2, casing_size: float, life: float) -> void:
		global_position = world_position
		velocity = initial_velocity
		size = maxf(1.5, casing_size)
		duration = maxf(0.2, life)
		angular_velocity = randf_range(-16.0, 16.0)

	func _process(delta: float) -> void:
		velocity = velocity.move_toward(Vector2.ZERO, 180.0 * delta)
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
		draw_colored_polygon(polygon, Color(0.93, 0.62, 0.12, fade))


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
		global_position = world_position
		direction = travel_direction.normalized() if not travel_direction.is_zero_approx() else Vector2.RIGHT
		strength = clampf(0.6 + damage / 45.0, 0.6, 1.7)
		duration = 0.28

	func _draw() -> void:
		var fade := 1.0 - progress()
		var color := Color(0.55, 0.02, 0.015, fade)
		for i in range(4):
			var offset := direction.rotated((-0.42 + float(i) * 0.28)) * (3.0 + float(i) * 2.0) * progress() * strength
			draw_circle(offset, (2.4 - progress() * 0.7) * strength, color)


class _EmptyClick:
	extends _BaseEffect
	func setup(world_position: Vector2) -> void:
		global_position = world_position
		duration = 0.12

	func _draw() -> void:
		var fade := 1.0 - progress()
		draw_arc(Vector2.ZERO, 6.0 + progress() * 5.0, 0.0, TAU, 12, Color(0.8, 0.8, 0.75, fade), 1.0)
