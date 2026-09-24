extends Node2D
## Bounded ground-local impressions; persist after the vehicle has left.
const LIMIT := 1600
const LIFETIME := 15.0
var clock := 0.0
var segments: Array = []
var previous: Dictionary = {}
var elapsed := 0.0

func _ready() -> void:
	material = CanvasItemMaterial.new()

func _physics_process(delta: float) -> void:
	clock += delta
	var had_marks := not segments.is_empty()
	while not segments.is_empty() and clock - float(segments[0][2]) >= LIFETIME:
		segments.pop_front()
	if had_marks: queue_redraw()
	elapsed += delta
	if elapsed < 0.08: return
	elapsed = 0.0
	var ground := get_parent() as Polygon2D
	var active: Dictionary = {}
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not vehicle is CharacterBody2D or not vehicle.is_visible_in_tree(): continue
		var center: Vector2 = ground.to_local(vehicle.global_position)
		if not Geometry2D.is_point_in_polygon(center, ground.polygon): continue
		var id: int = vehicle.get_instance_id()
		active[id] = true
		var wheels: Array[Vector2] = []
		var half_track := 15.0
		if vehicle.has_method("_wheel_track"): half_track = float(vehicle.call("_wheel_track")) * 18.0
		for side in [-1.0, 1.0]:
			wheels.append(ground.to_local(vehicle.to_global(Vector2(-20, side * half_track))))
		if previous.has(id):
			for i in 2:
				var start: Vector2 = previous[id][i]
				var finish: Vector2 = wheels[i]
				var distance := start.distance_to(finish)
				if distance > 1.5 and distance < 80 and Geometry2D.is_point_in_polygon(start, ground.polygon) and Geometry2D.is_point_in_polygon(finish, ground.polygon):
					segments.append([start, finish, clock])
		previous[id] = wheels
	for id in previous.keys():
		if not active.has(id): previous.erase(id)
	if segments.size() > LIMIT: segments = segments.slice(segments.size() - LIMIT)
	if not active.is_empty(): queue_redraw()

func _draw() -> void:
	var kind: String = str(get_parent().get_meta("mountain_surface", "earth"))
	var color := Color(0.12, 0.09, 0.055, 0.48)
	if kind == "forest": color = Color(0.20, 0.23, 0.09, 0.6)
	elif kind in ["snow", "packed"]: color = Color(0.32, 0.40, 0.43, 0.48)
	for segment in segments:
		var ink := color
		ink.a *= 1.0 - smoothstep(10.0, LIFETIME, clock - float(segment[2]))
		draw_line(segment[0], segment[1], ink, 5.0, true)
		var middle: Vector2 = (segment[0] + segment[1]) * 0.5
		var normal: Vector2 = (segment[1] - segment[0]).normalized().orthogonal() * 2.5
		draw_line(middle - normal, middle + normal, ink.darkened(0.25), 1.2, true)
