extends Node2D
## Scene-owned ground ink: no per-mark nodes and no retained vehicle references.
const MAX_MARKS := 1200
const LIFETIME := 40.0
const FADE := 8.0
var marks: Array[Dictionary] = []
var clock := 0.0
var redraw_time := 0.0

static func ensure(car: Node) -> Node:
	var scene := car.get_tree().current_scene
	if scene == null: scene = car.get_parent()
	var existing := scene.get_node_or_null("VehicleSkidMarks")
	if existing: return existing
	var ink := new()
	ink.name = "VehicleSkidMarks"
	scene.add_child(ink)
	return ink

func _ready() -> void:
	z_as_relative = false
	z_index = 4 # Same ground plane as tire residue, below bodies and people.

func add_segment(a: Vector2, b: Vector2, intensity: float) -> void:
	if a.distance_squared_to(b) > 6400.0: return
	marks.append({"a": to_local(a), "b": to_local(b), "time": clock, "alpha": clampf(intensity, 0.18, 0.65)})
	if marks.size() > MAX_MARKS: marks.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	redraw_time += delta
	if marks.is_empty(): return
	var changed := false
	while not marks.is_empty() and clock - float(marks[0].time) >= LIFETIME:
		marks.pop_front()
		changed = true
	if changed or (redraw_time >= 0.1 and not marks.is_empty() and clock - float(marks[0].time) > LIFETIME - FADE):
		redraw_time = 0.0
		queue_redraw()

func _draw() -> void:
	for mark in marks:
		var alpha := float(mark.alpha) * clampf((LIFETIME - clock + float(mark.time)) / FADE, 0.0, 1.0)
		draw_line(mark.a, mark.b, Color(0.075, 0.065, 0.055, alpha), 3.2, true)
