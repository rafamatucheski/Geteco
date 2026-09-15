class_name Puddle
extends Area2D

## Poça d'água decorativa espalhada pelo mapa (calçadas, docas, sarjetas).
## Qualquer carro, pedestre ou o jogador que passa por cima gera um respingo
## visual (reaproveita a textura de respingo da chuva) e um "splash" sonoro.

const RAIN_VISUALS := preload("res://audio/weather/RainVisualPalette.gd")

@export var puddle_radius: Vector2 = Vector2(26.0, 15.0)

var _surface := "asphalt"
var _rim: Polygon2D
var _reflection_poly: Polygon2D
var _clock: float = 0.0
var _cooldown := 0.0
var _visual_elapsed := 0.0
var _splash_particles: CPUParticles2D

func _ready() -> void:
	z_index = 4
	z_as_relative = false
	add_to_group("rain_puddle")
	# Sky highlights stay readable after the night CanvasModulate darkens asphalt.
	# Child polygons retain ordinary lighting, so the water body never glows.
	var reflection_material := CanvasItemMaterial.new()
	reflection_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = reflection_material
	collision_layer = 0
	collision_mask = 1 | 2 | 4 | 8 # Jogador, carros, pedestres — quem passar, respinga

	var col := CollisionShape2D.new()
	var shape := ConvexPolygonShape2D.new()
	shape.points = Geometry2D.convex_hull(_create_ellipse_polygon(puddle_radius.x, puddle_radius.y, 16))
	col.shape = shape
	add_child(col)

	_reflection_poly = Polygon2D.new()
	_reflection_poly.polygon = _create_ellipse_polygon(puddle_radius.x, puddle_radius.y, 16)
	_reflection_poly.color = Color(0.16, 0.22, 0.30, 0.55)
	add_child(_reflection_poly)

	var rim := Polygon2D.new()
	_rim = rim
	rim.polygon = _create_ellipse_polygon(puddle_radius.x * 1.08, puddle_radius.y * 1.08, 16)
	rim.color = Color(0.35, 0.45, 0.55, 0.18)
	add_child(rim)
	move_child(rim, 0)

	_splash_particles = CPUParticles2D.new()
	_splash_particles.emitting = false
	_splash_particles.one_shot = true
	_splash_particles.amount = 18
	_splash_particles.lifetime = 0.35
	_splash_particles.explosiveness = 0.95
	_splash_particles.direction = Vector2(0, -1)
	_splash_particles.spread = 60.0
	_splash_particles.gravity = Vector2(0, 340.0)
	_splash_particles.initial_velocity_min = 70.0
	_splash_particles.initial_velocity_max = 170.0
	_splash_particles.scale_amount_min = 0.35
	_splash_particles.scale_amount_max = 0.75
	_splash_particles.texture = RAIN_VISUALS.splash()
	_splash_particles.color = Color(0.82, 0.90, 1.0, 0.75)
	_splash_particles.z_index = 9
	add_child(_splash_particles)

	body_entered.connect(_on_body_entered)

func _create_ellipse_polygon(radius_x: float, radius_y: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		var shore := 1.0 + 0.08 * sin(ang * 3.0) + 0.05 * cos(ang * 5.0)
		arr.append(Vector2(cos(ang) * radius_x, sin(ang) * radius_y) * shore)
	return arr

func _process(delta: float) -> void:
	_clock += delta
	_cooldown = maxf(0,_cooldown-delta)
	_visual_elapsed += delta
	if _visual_elapsed < 1.0 / 30.0: return
	_visual_elapsed = fmod(_visual_elapsed, 1.0 / 30.0)
	queue_redraw()
	if _reflection_poly:
		_reflection_poly.color.a = 0.50 + sin(_clock * 1.4) * 0.08

func _on_body_entered(body: Node2D) -> void:
	var speed := 0.0
	if "velocity" in body:
		speed = (body.velocity as Vector2).length()
	if speed > 15 and _cooldown <= 0:
		_cooldown = 0.2
		_splash(speed)

func _draw() -> void:
	# Broken highlights and expanding rain rings make shallow water legible.
	draw_arc(Vector2(-7,-3),puddle_radius.y*0.7,3.3,5.6,16,Color(0.65,0.82,0.94,0.32),1.5,true)
	var phase := fmod(_clock*0.8,1.0)
	draw_arc(Vector2(8,1),2+phase*10,0,TAU,20,Color(0.62,0.78,0.91,(1-phase)*0.4),1.0,true)

func _splash(impact_speed: float) -> void:
	if _splash_particles:
		_splash_particles.restart()
		_splash_particles.emitting = true

	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = ProceduralAudio.get_water_stream()
	p.pitch_scale = randf_range(1.5, 2.1)
	p.volume_db = clampf(-16.0 + impact_speed * 0.01, -16.0, -4.0)
	p.max_distance = 420.0
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var stop_timer := get_tree().create_timer(0.4)
	stop_timer.timeout.connect(func():
		if is_instance_valid(p):
			p.stop()
			p.queue_free()
	)

func set_surface(surface: String) -> void:
	_surface = surface
	if not is_instance_valid(_reflection_poly): return
	match surface:
		"dirt":
			_reflection_poly.color = Color(.24,.20,.14,.55)
			_rim.color = Color(.16,.12,.07,.30)
		"grass":
			_reflection_poly.color = Color(.15,.23,.18,.55)
			_rim.color = Color(.12,.20,.10,.25)
		_:
			_reflection_poly.color = Color(.16,.22,.30,.55)
			_rim.color = Color(.35,.45,.55,.18)
