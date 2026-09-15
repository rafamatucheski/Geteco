extends Node2D
## A bounded pool gets a fresh road-edge layout for each rainfall.
const PUDDLE := preload("res://Puddle.gd")
const MAX_PUDDLES := 96
const DRY_RATE := 0.6
const FILL_RATE := 1.0 / 45.0
const PRESENTATION_INTERVAL := 0.05
var wetness := 0.0
var _weather: Node
var _raining := false
var _rng := RandomNumberGenerator.new()
var _presentation_elapsed := 0.0

func _ready() -> void:
	name = "RainPuddles"
	_weather = get_tree().get_first_node_in_group("day_night_manager")
	_rng.randomize()

func _begin_rain() -> void:
	wetness = 0.0
	var count := 0
	var probe := Node2D.new()
	add_child(probe)
	var resolver := preload("res://audio/footsteps/FootstepSurfaceResolver.gd")
	var regions: Array[Dictionary] = []
	var world := get_tree().current_scene
	for ground in get_tree().get_nodes_in_group("audio_ground"):
		if not ground is Polygon2D or not ground.is_visible_in_tree(): continue
		var surface := String(ground.get_meta("footstep_surface", ground.get_meta("mountain_surface", "")))
		if surface not in ["grass", "forest", "dirt", "earth"]: continue
		if ground.polygon.is_empty(): continue
		var bounds := Rect2(ground.polygon[0], Vector2.ZERO)
		for point in ground.polygon: bounds = bounds.expand(point)
		regions.append({"node":ground, "bounds":bounds})
	for provider_name in resolver.GARDENS:
		var provider := world.get_node_or_null(NodePath(provider_name)) if world else null
		if provider == null: continue
		for bounds in resolver.GARDENS[provider_name]:
			regions.append({"node":provider, "bounds":bounds})
	# At most 32 natural puddles; retain 64 slots for streets. Work only at rain start.
	for attempt in 256:
		if count >= 32 or regions.is_empty(): break
		var region: Dictionary = regions[attempt % regions.size()]
		var bounds: Rect2 = region.bounds
		var point: Vector2 = region.node.to_global(bounds.position + Vector2(_rng.randf(), _rng.randf()) * bounds.size)
		probe.global_position = point
		var surface: String = resolver.resolve(probe, false)
		if surface not in ["grass", "dirt"]: continue
		var radii := Vector2(_rng.randf_range(18,32), _rng.randf_range(9,15))
		var angle := _rng.randf_range(0,TAU)
		if not _clear_surface(probe, point, radii, angle, surface): continue
		_place(count, point, radii, angle, surface)
		count += 1
	var roads := get_parent().get_node_or_null("RoadNetwork") as Node2D
	if roads:
		var road_order: Array = roads._roads.duplicate()
		for i in range(road_order.size()-1,0,-1):
			var other := _rng.randi_range(0,i)
			var saved: Dictionary = road_order[i]
			road_order[i] = road_order[other]
			road_order[other] = saved
		for road: Dictionary in road_order:
			var points: PackedVector2Array = road.points
			for i in range(1,points.size()):
				var a := points[i-1]
				var b := points[i]
				var distance := _rng.randf_range(80,360)
				while distance < a.distance_to(b) and count < MAX_PUDDLES:
					var radii := Vector2(_rng.randf_range(26,44),_rng.randf_range(11,19))
					var tangent := a.direction_to(b)
					var offset := maxf(0,float(road.width)*.5-radii.y*1.15-2)*_rng.randf_range(-.8,.8)
					var point := roads.to_global(a+tangent*distance+tangent.orthogonal()*offset)
					var angle := roads.global_rotation+tangent.angle()
					if _clear_surface(probe,point,radii,angle,""):
						_place(count,point,radii,angle,"asphalt")
						count += 1
					distance += _rng.randf_range(300,650)
				if count >= MAX_PUDDLES: break
			if count >= MAX_PUDDLES: break
	remove_child(probe)
	probe.queue_free()
	for i in range(count,get_child_count()):
		get_child(i).set_meta("fill_delay",2.0)

func _clear_surface(probe: Node2D, point: Vector2, radii: Vector2, angle: float, expected: String) -> bool:
	# Reject an entire indoor footprint, including concrete garage floors.
	var extent := Vector2.ONE * radii.length() * 1.18
	var bounds := Rect2(point-extent,extent*2.0)
	for room in get_tree().get_nodes_in_group("harbor_interior"):
		if room.has_method("get_camera_rect") and room.get_camera_rect().intersects(bounds): return false
	var outline := PackedVector2Array()
	for i in 16:
		var phase := TAU*i/16.0
		var edge := Vector2(cos(phase)*radii.x,sin(phase)*radii.y)*1.18
		outline.append(edge)
		probe.global_position = point + edge.rotated(angle)
		var surface: String = preload("res://audio/footsteps/FootstepSurfaceResolver.gd").resolve(probe,false)
		if expected != "" and surface != expected: return false
		if expected == "" and surface not in ["asphalt","concrete"]: return false
	var shape := ConvexPolygonShape2D.new()
	shape.points = outline
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(angle,point)
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func _place(index: int, point: Vector2, radii: Vector2, angle: float, surface: String) -> void:
	var puddle: Area2D
	# Probe is always the last child while distributing the pool.
	if index < get_child_count()-1:
		puddle = get_child(index)
	else:
		puddle = PUDDLE.new()
		add_child(puddle)
		move_child(puddle,index)
	puddle.set_surface(surface)
	puddle.set_meta("full_scale",radii/puddle.puddle_radius)
	puddle.scale = radii/puddle.puddle_radius*.08
	puddle.global_position = point
	puddle.global_rotation = angle
	puddle.set_meta("fill_delay",_rng.randf_range(.04,.16))
	puddle.visible = false
	puddle.monitoring = false
	puddle.set_process(false)

func _process(delta: float) -> void:
	var rain: float = _weather.get_rain_intensity() if is_instance_valid(_weather) else 0.0
	var raining := rain > 0.01
	var state_changed := raining != _raining
	if raining and not _raining:
		_begin_rain()
	_raining = raining
	# Stored water builds with rainfall over time, even during a steady drizzle.
	# A drop in rain intensity must not instantly drain an existing puddle.
	if raining:
		wetness = minf(1.0, wetness + delta * rain * FILL_RATE)
	else:
		wetness = move_toward(wetness, 0.0, delta * DRY_RATE)
	# Wetness integrates continuously. Visibility, scale and collision activation
	# change slowly and use one bounded 20Hz pass across the 96 pooled areas.
	_presentation_elapsed += delta
	if not state_changed and _presentation_elapsed < PRESENTATION_INTERVAL: return
	_presentation_elapsed = fmod(_presentation_elapsed, PRESENTATION_INTERVAL)
	var camera := get_viewport().get_camera_2d()
	var center := camera.get_screen_center_position() if camera else Vector2.ZERO
	for puddle in get_children():
		var delay: float = puddle.get_meta("fill_delay", 0.0)
		var opacity := smoothstep(delay, delay + 0.70, wetness)
		var full_scale: Vector2 = puddle.get_meta("full_scale", Vector2.ONE)
		puddle.scale = full_scale * lerpf(0.08, 1.0, sqrt(opacity))
		var active: bool = opacity > 0.01 and puddle.global_position.distance_to(center) < 1100
		puddle.visible = active
		puddle.modulate.a = opacity
		puddle.monitoring = active and raining and opacity > 0.08
		puddle.set_process(active)
