extends SceneTree

class SoundscapeProbe extends "res://world/harbor/HarborSoundscape.gd":
	func _ready() -> void:
		set_process(false)

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _run() -> void:
	var soundscape := SoundscapeProbe.new()
	root.add_child(soundscape)
	var people: Array[Node2D] = []
	for index in 4:
		var person := Node2D.new()
		person.position = Vector2(40, index * 3)
		root.add_child(person)
		person.add_to_group("pedestrian")
		people.append(person)
	await physics_frame
	check(is_equal_approx(soundscape.nearby_conversation_weight(Vector2.ZERO), 1.0), "Nearby visible crowd remains audible")
	check(soundscape.nearby_conversation_weight(Vector2.INF) == 0.0, "Unplaced listener never sends infinite ray coordinates to physics")
	check(soundscape.nearby_conversation_weight(Vector2(NAN, 0)) == 0.0, "NaN listener is rejected before physics queries")
	people[0].position = Vector2(NAN, 0)
	people[1].position = Vector2.INF
	var remaining := soundscape.nearby_conversation_weight(Vector2.ZERO)
	check(is_equal_approx(remaining, smoothstep(1.0, 4.0, 2.0)), "Invalid pedestrians are skipped while valid neighbors remain audible")
	people[0].position = Vector2(40, 0)
	people[1].position = Vector2(40, 3)
	var wall := StaticBody2D.new()
	wall.position = Vector2(20, 0)
	var hull := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(5, 100)
	hull.shape = rectangle
	wall.add_child(hull)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	check(soundscape.nearby_conversation_weight(Vector2.ZERO) == 0.0, "Walls still block conversation audio")
	wall.free()
	for person in people: person.free()
	soundscape.free()
	print("SOUNDSCAPE_INVALID_POSITIONS failures=", failures)
	quit(1 if failures else 0)
