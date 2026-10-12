extends SceneTree
## A civilian U-turn must not repeatedly cancel and restart its foot stroke.
const BOARD = preload("res://activities/skate/SkateBody.gd")
const ACTOR = preload("res://scripts/Actor.gd")
const SKATE = preload("res://activities/skate/Skate.gd")
var failures := 0
func _initialize(): run.call_deferred()
func run():
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, .2, 100)
	collider.shape = shape
	collider.position.y = -.1
	floor_body.add_child(collider)
	stage.add_child(floor_body)
	var board = BOARD.new()
	board.position.y = .05
	stage.add_child(board)
	var actor = ACTOR.new()
	actor.identity = 5
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.visual.get_child(0).set_process(false)
	board.add_collision_exception_with(actor)
	var skate = SKATE.new()
	skate.session = {"modal": false}
	var row := {"actor": actor, "board": board, "route": PackedVector3Array([Vector3(0, 0, 15)]), "waypoint": 0, "health": actor.health, "park": false, "stalled": 0.0, "push_requested": true, "pace": 3.15}
	skate.ambient.append(row)
	for i in 30: await physics_frame
	board.riding = true
	board.speed = 1.4
	var starts := 0
	var interrupted := 0
	var was_pushing := false
	var phase := 0.0
	var aligned := false
	for i in 240:
		skate._update_ambient(1.0 / 60)
		await physics_frame
		if board.pushing and not was_pushing: starts += 1
		if was_pushing and not board.pushing and phase < .90: interrupted += 1
		was_pushing = board.pushing
		phase = board.push_phase
		var toward: Vector3 = row.route[0] - board.position
		if absf(angle_difference(board.rotation.y, atan2(-toward.x, -toward.z))) < .3: aligned = true
	if interrupted > 1 or starts > 6 or not aligned or not board.riding: failures += 1
	print("SKATE_TURN_RESULT starts=", starts, " interrupted=", interrupted, " aligned=", aligned, " failures=", failures)
	skate.free()
	stage.free()
	quit(1 if failures else 0)
