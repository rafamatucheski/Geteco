extends Node2D
## One bounded, world-space liquid burst. Ballistic drops settle on the road.
var age := 0.0
var strength := 1.0
var direction := Vector2.RIGHT
var drops: Array[Vector4] = []
var lifts := PackedFloat32Array()
var sizes := PackedFloat32Array()
const LIFE := 1.35
const VISUAL_SCALE := 0.45

func setup(origin: Vector2, incoming: Vector2, lethal: bool) -> void:
	global_position = origin
	# Keep the directional spray readable without covering the person or vehicle.
	scale = Vector2.ONE * VISUAL_SCALE
	direction = incoming.normalized() if not incoming.is_zero_approx() else Vector2.RIGHT
	strength = lerpf(0.55, 1.35, clampf((incoming.length() - 60.0) / 300.0, 0.0, 1.0))
	if lethal: strength *= 1.15
	for i in 42:
		var angle := randf_range(-1.5, 1.5) if i % 4 != 0 else randf_range(-PI, PI)
		var velocity := direction.rotated(angle) * randf_range(40.0, 175.0) * strength
		drops.append(Vector4(velocity.x, velocity.y, randf_range(-4.0, 4.0), randf_range(-3.0, 3.0)))
		lifts.append(randf_range(35.0, 110.0) * strength)
		sizes.append(randf_range(0.8, 2.5) * strength)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var fade := 1.0 - smoothstep(0.85, LIFE, age)
	
	# A fast broad sheet breaks into fingers instead of a circular explosion.
	var sheet := (1.0 - smoothstep(0.08, 0.30, age))
	if sheet > 0.025:
		var reach := (8.0 + 100.0 * (1.0 - exp(-age * 18.0))) * strength
		for i in 9:
			var angle := lerpf(-1.35, 1.35, float(i) / 8.0)
			var axis := direction.rotated(angle)
			var across := axis.orthogonal()
			var tip := axis * reach * (0.72 + 0.20 * sin(float(i) * 2.7))
			var width := maxf(0.25, (5.0 + 3.0 * sin(float(i) * 1.9)) * strength * sheet)
			var points := PackedVector2Array([Vector2.ZERO, tip * 0.4 - across * width,
				tip * 0.78 - across * width * 0.45, tip,
				tip * 0.72 + across * width * 0.65, tip * 0.3 + across * width])
			draw_colored_polygon(points, Color(0.48, 0.025, 0.055, sheet * 0.92))
			draw_line(tip * 0.34, tip * 0.85, Color(0.86, 0.10, 0.14, sheet * 0.7), maxf(0.6, width * 0.23), true)
	for i in drops.size():
		var drop := drops[i]
		var velocity := Vector2(drop.x, drop.y)
		var landing := (lifts[i] + sqrt(lifts[i] * lifts[i] + 2.0 * 300.0 * 5.0)) / 300.0
		var t := minf(age, landing)
		var ground := Vector2(drop.z, drop.w) + velocity * (1.0 - exp(-t * 2.2)) / 2.2
		var height := maxf(0.0, 5.0 + lifts[i] * t - 150.0 * t * t)
		var point := ground + Vector2(0.0, -height)
		var radius := sizes[i]
		if age >= landing:
			draw_set_transform(ground, velocity.angle(), Vector2(1.6, 0.65))
			draw_circle(Vector2.ZERO, radius * 1.2, Color(0.32, 0.025, 0.04, fade), true, -1, true)
			draw_set_transform(Vector2.ZERO)
		else:
			var tangent := velocity * exp(-t * 2.2) + Vector2(0.0, -lifts[i] + 300.0 * t)
			var tail := tangent.normalized() * minf(12.0, tangent.length() * 0.065)
			draw_line(point - tail, point, Color(0.43, 0.02, 0.04, fade), radius * 1.5, true)
			draw_circle(point, radius, Color(0.68, 0.035, 0.07, fade), true, -1, true)
			if radius > 1.5:
				draw_circle(point + Vector2(-0.4, -0.6), radius * 0.3, Color(0.98, 0.35, 0.34, fade * 0.8), true, -1, true)


