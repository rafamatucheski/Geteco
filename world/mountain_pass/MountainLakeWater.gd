extends Node2D
## The lake polygon owns both its visible water and the footstep surface.
const MAX_MARKS := 48
var polygon := PackedVector2Array()
var plane: Node2D
var dry_islands: Array[Polygon2D] = []
var marks: Array[Dictionary] = []
var wet_steps: Dictionary = {}

func _ready() -> void:
	add_to_group("water_surface")
	set_process(false)

func animate_surface(surface: Polygon2D) -> void:
	preload("res://geodata/nature/WaterPresentation.gd").apply(surface, "lake")

func is_deck_at(actor: Node2D) -> bool:
	return is_instance_valid(plane) and plane.contains_actor(actor)

func is_water_at(actor: Node2D) -> bool:
	if not actor.is_visible_in_tree() or actor.get_meta("mountain_interior", false) or actor.get_meta("harbor_interior", false): return false
	if not Geometry2D.is_point_in_polygon(to_local(actor.global_position), polygon): return false
	if is_deck_at(actor): return false
	for island in dry_islands:
		if is_instance_valid(island) and Geometry2D.is_point_in_polygon(island.to_local(actor.global_position), island.polygon): return false
	return true

func actor_step(actor: Node2D, sprinting: bool) -> void:
	var id := actor.get_instance_id()
	var water := is_water_at(actor)
	if water:
		wet_steps[id] = 6
	elif int(wet_steps.get(id, 0)) <= 0:
		return
	else:
		wet_steps[id] -= 1
		if wet_steps[id] == 0: wet_steps.erase(id)
		if is_deck_at(actor) or actor.get_meta("mountain_interior", false) or actor.get_meta("harbor_interior", false):
			wet_steps.erase(id)
			return
	var heading: float = actor.velocity.angle() if actor.get("velocity") is Vector2 else actor.global_rotation
	var side := 1.0 if marks.size() % 2 == 0 else -1.0
	var point := to_local(actor.global_position) + Vector2.from_angle(heading).orthogonal() * side * 3.0
	marks.append({"point": point, "age": 0.0, "water": water, "heading": heading, "sprint": sprinting})
	if marks.size() > MAX_MARKS: marks.pop_front()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	for mark in marks: mark.age += delta
	marks = marks.filter(func(mark): return mark.age < (0.85 if mark.water else 4.5))
	queue_redraw()
	if marks.is_empty(): set_process(false)

func _draw() -> void:
	for mark in marks:
		var point: Vector2 = mark.point
		var age: float = mark.age
		if mark.water:
			var radius := 3.0 + age * (24.0 if mark.sprint else 17.0)
			# Clip each ripple segment to the actual lake edge.
			for i in 24:
				var a := point + Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0) * 0.55) * radius
				var b := point + Vector2(cos(TAU * (i+1) / 24.0), sin(TAU * (i+1) / 24.0) * 0.55) * radius
				if Geometry2D.is_point_in_polygon(a, polygon) and Geometry2D.is_point_in_polygon(b, polygon):
					draw_line(a, b, Color(0.62, 0.88, 0.90, (1.0-age/0.85)*0.65), 1.0, true)
			for drop in 4:
				var offset := Vector2.from_angle(drop * PI * 0.5 + 0.4) * age * 15.0
				offset.y -= sin(age / 0.85 * PI) * 7.0
				if Geometry2D.is_point_in_polygon(point + offset, polygon):
					draw_circle(point + offset, 1.1, Color(0.65, 0.87, 0.91, (1.0-age/0.85)*0.8))
		else:
			draw_set_transform(point, mark.heading, Vector2(1.0, 0.50))
			draw_circle(Vector2.ZERO, 3.4, Color(0.06, 0.10, 0.09, (1.0-age/4.5)*0.5))
			draw_set_transform(Vector2.ZERO)
