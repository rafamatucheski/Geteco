extends Node2D
## A bounded pool gets a fresh road-edge layout for each rainfall.
const PUDDLE := preload("res://geodata/Puddle.gd")
const MAX_PUDDLES := 96
const DRY_RATE := 0.6
const FILL_RATE := 1.0 / 45.0
const PRESENTATION_INTERVAL := 0.05
const PUDDLE_BUILD_PER_FRAME := 2
const PUDDLE_BUILD_TIME_BUDGET_USEC := 1400
const PUDDLE_PLAN_TIME_BUDGET_USEC := 1200
const SPLASH_POOL_SIZE := 8
const SPLASH_POOL_BUILD_PER_FRAME := 1
var wetness := 0.0
var _weather: Node
var _raining := false
var _rng := RandomNumberGenerator.new()
var _presentation_elapsed := 0.0
var _layout_specs: Array[Dictionary] = []
var _layout_cursor := 0
var _layout_generation := 0
var _layout_planning := false
var _planning_peak_usec := 0
var _planning_total_usec := 0
var _planning_slices := 0
var _materialization_started_frame := -1
var _materialization_finished_frame := -1
var _materialization_peak_usec := 0
var _materialization_total_usec := 0
var _materialization_peak_count := 0
var _splash_pool_root: Node2D
var _splash_emitters: Array[CPUParticles2D] = []
var _splash_cursor := 0

func _ready() -> void:
	name = "RainPuddles"
	_weather = get_tree().get_first_node_in_group("day_night_manager")
	_rng.randomize()
	_splash_pool_root = Node2D.new()
	_splash_pool_root.name = "RainPuddleSplashPool"
	_splash_pool_root.top_level = true
	get_parent().call_deferred("add_child", _splash_pool_root)


func _exit_tree() -> void:
	if is_instance_valid(_splash_pool_root):
		_splash_pool_root.queue_free()

func _begin_rain() -> void:
	wetness = 0.0
	_layout_specs.clear()
	_layout_cursor = 0
	_layout_generation += 1
	_layout_planning = true
	_planning_peak_usec = 0
	_planning_total_usec = 0
	_planning_slices = 0
	_materialization_started_frame = Engine.get_process_frames()
	_materialization_finished_frame = -1
	_materialization_peak_usec = 0
	_materialization_total_usec = 0
	_materialization_peak_count = 0
	for puddle in _puddles():
		puddle.visible = false
		puddle.monitoring = false
		puddle.set_process(false)
	_build_layout_async.call_deferred(_layout_generation)


func _build_layout_async(generation: int) -> void:
	var count := 0
	var probe := Node2D.new()
	add_child(probe)
	var resolver := preload("res://audio/footsteps/FootstepSurfaceResolver.gd")
	var regions: Array[Dictionary] = []
	var world := get_tree().current_scene
	var slice_started_usec := Time.get_ticks_usec()
	for ground in get_tree().get_nodes_in_group("audio_ground"):
		if not ground is Polygon2D or not ground.is_visible_in_tree(): continue
		var surface := String(ground.get_meta("footstep_surface", ground.get_meta("mountain_surface", "")))
		if surface not in ["grass", "forest", "dirt", "earth"]: continue
		if ground.polygon.is_empty(): continue
		var bounds := Rect2(ground.polygon[0], Vector2.ZERO)
		for point in ground.polygon: bounds = bounds.expand(point)
		regions.append({"node":ground, "bounds":bounds})
		if Time.get_ticks_usec() - slice_started_usec >= PUDDLE_PLAN_TIME_BUDGET_USEC:
			_record_planning_slice(slice_started_usec)
			await get_tree().process_frame
			if generation != _layout_generation:
				probe.queue_free()
				return
			slice_started_usec = Time.get_ticks_usec()
	for provider_name in resolver.GARDENS:
		var provider := world.get_node_or_null(NodePath(provider_name)) if world else null
		if provider == null: continue
		for bounds in resolver.GARDENS[provider_name]:
			regions.append({"node":provider, "bounds":bounds})
	# At most 32 natural puddles; retain 64 slots for streets. Work only at rain start.
	for attempt in 256:
		if Time.get_ticks_usec() - slice_started_usec >= PUDDLE_PLAN_TIME_BUDGET_USEC:
			_record_planning_slice(slice_started_usec)
			await get_tree().process_frame
			if generation != _layout_generation:
				probe.queue_free()
				return
			slice_started_usec = Time.get_ticks_usec()
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
		_queue_layout(point, radii, angle, surface)
		count += 1
		if Time.get_ticks_usec() - slice_started_usec >= PUDDLE_PLAN_TIME_BUDGET_USEC:
			_record_planning_slice(slice_started_usec)
			await get_tree().process_frame
			if generation != _layout_generation:
				probe.queue_free()
				return
			slice_started_usec = Time.get_ticks_usec()
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
						_queue_layout(point, radii, angle, "asphalt")
						count += 1
					distance += _rng.randf_range(300,650)
					if Time.get_ticks_usec() - slice_started_usec >= PUDDLE_PLAN_TIME_BUDGET_USEC:
						_record_planning_slice(slice_started_usec)
						await get_tree().process_frame
						if generation != _layout_generation:
							probe.queue_free()
							return
						slice_started_usec = Time.get_ticks_usec()
				if count >= MAX_PUDDLES: break
			if count >= MAX_PUDDLES: break
	_record_planning_slice(slice_started_usec)
	remove_child(probe)
	probe.queue_free()
	if generation != _layout_generation:
		return
	_layout_planning = false
	var existing := _puddles()
	for i in range(count, existing.size()):
		existing[i].set_meta("fill_delay", 2.0)
		existing[i].visible = false
		existing[i].monitoring = false
		existing[i].set_process(false)
	if _layout_cursor >= _layout_specs.size():
		_materialization_finished_frame = Engine.get_process_frames()


func _record_planning_slice(started_usec: int) -> void:
	var elapsed := maxi(0, Time.get_ticks_usec() - started_usec)
	_planning_total_usec += elapsed
	_planning_peak_usec = maxi(_planning_peak_usec, elapsed)
	_planning_slices += 1

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

func _queue_layout(point: Vector2, radii: Vector2, angle: float, surface: String) -> void:
	_layout_specs.append({
		"point": point,
		"radii": radii,
		"angle": angle,
		"surface": surface,
		"fill_delay": _rng.randf_range(.04, .16),
	})


func _puddles() -> Array[Area2D]:
	var result: Array[Area2D] = []
	for child in get_children():
		if child is Puddle:
			result.append(child)
	return result


func _configure_puddle(puddle: Area2D, spec: Dictionary) -> void:
	puddle.set_surface(String(spec.surface))
	var full_scale: Vector2 = spec.radii / puddle.puddle_radius
	puddle.set_meta("full_scale", full_scale)
	puddle.scale = full_scale * .08
	puddle.global_position = spec.point
	puddle.global_rotation = float(spec.angle)
	puddle.set_meta("fill_delay", float(spec.fill_delay))
	puddle.visible = false
	puddle.monitoring = false
	puddle.set_process(false)


func _drain_puddle_materialization() -> void:
	if _layout_cursor >= _layout_specs.size():
		return
	var started := Time.get_ticks_usec()
	var built := 0
	var existing := _puddles()
	while _layout_cursor < _layout_specs.size() and built < PUDDLE_BUILD_PER_FRAME:
		if built > 0 and Time.get_ticks_usec() - started >= PUDDLE_BUILD_TIME_BUDGET_USEC:
			break
		var puddle: Area2D
		if _layout_cursor < existing.size():
			puddle = existing[_layout_cursor]
		else:
			puddle = PUDDLE.new()
			add_child(puddle)
		_configure_puddle(puddle, _layout_specs[_layout_cursor])
		_layout_cursor += 1
		built += 1
	var elapsed := Time.get_ticks_usec() - started
	_materialization_total_usec += elapsed
	_materialization_peak_usec = maxi(_materialization_peak_usec, elapsed)
	_materialization_peak_count = maxi(_materialization_peak_count, built)
	if not _layout_planning and _layout_cursor >= _layout_specs.size():
		_materialization_finished_frame = Engine.get_process_frames()


func _add_splash_emitter() -> CPUParticles2D:
	if not is_instance_valid(_splash_pool_root):
		return null
	var emitter: CPUParticles2D = PUDDLE.create_splash_emitter()
	_splash_pool_root.add_child(emitter)
	_splash_emitters.append(emitter)
	return emitter


func _drain_splash_pool_prewarm() -> void:
	var built := 0
	while _splash_emitters.size() < SPLASH_POOL_SIZE and built < SPLASH_POOL_BUILD_PER_FRAME:
		if _add_splash_emitter() == null:
			return
		built += 1


func emit_puddle_splash(world_position: Vector2) -> bool:
	if _splash_emitters.is_empty() and _add_splash_emitter() == null:
		return false
	var selected: CPUParticles2D
	for offset in _splash_emitters.size():
		var index := (_splash_cursor + offset) % _splash_emitters.size()
		if not _splash_emitters[index].emitting:
			selected = _splash_emitters[index]
			_splash_cursor = (index + 1) % _splash_emitters.size()
			break
	if selected == null:
		selected = _splash_emitters[_splash_cursor]
		_splash_cursor = (_splash_cursor + 1) % _splash_emitters.size()
	selected.global_position = world_position
	selected.restart()
	selected.emitting = true
	return true


func get_splash_pool_size() -> int:
	return _splash_emitters.size()


func get_active_splash_count() -> int:
	var active := 0
	for emitter in _splash_emitters:
		if is_instance_valid(emitter) and emitter.emitting:
			active += 1
	return active


func get_build_telemetry() -> Dictionary:
	var latency_frames := -1
	if _materialization_started_frame >= 0 and _materialization_finished_frame >= 0:
		latency_frames = _materialization_finished_frame - _materialization_started_frame + 1
	return {
		"pending": maxi(0, _layout_specs.size() - _layout_cursor),
		"planning": _layout_planning,
		"planning_peak_usec": _planning_peak_usec,
		"planning_total_usec": _planning_total_usec,
		"planning_slices": _planning_slices,
		"target": _layout_specs.size(),
		"materialized": _puddles().size(),
		"max_built_per_frame": _materialization_peak_count,
		"peak_build_usec": _materialization_peak_usec,
		"total_build_usec": _materialization_total_usec,
		"latency_frames": latency_frames,
		"splash_emitters": _splash_emitters.size(),
	}

func _process(delta: float) -> void:
	var rain: float = _weather.get_rain_intensity() if is_instance_valid(_weather) else 0.0
	var raining := rain > 0.01
	var state_changed := raining != _raining
	if raining and not _raining:
		_begin_rain()
	_raining = raining
	_drain_puddle_materialization()
	if raining:
		_drain_splash_pool_prewarm()
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
		if not puddle is Puddle:
			continue
		var delay: float = puddle.get_meta("fill_delay", 0.0)
		var opacity := smoothstep(delay, delay + 0.70, wetness)
		var full_scale: Vector2 = puddle.get_meta("full_scale", Vector2.ONE)
		puddle.scale = full_scale * lerpf(0.08, 1.0, sqrt(opacity))
		var active: bool = opacity > 0.01 and puddle.global_position.distance_to(center) < 1100
		puddle.visible = active
		puddle.modulate.a = opacity
		puddle.monitoring = active and raining and opacity > 0.08
		puddle.set_process(active)
