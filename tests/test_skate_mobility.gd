extends SceneTree
const BOARD = preload("res://activities/skate/SkateBody.gd")
const PARK = preload("res://activities/skate/SkatePark.gd")
const LAYOUT = preload("res://activities/skate/SkateParkLayout.gd")
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool, title: String):
	checks += 1
	if not ok: failures += 1
	print("SKATE_MOBILITY ", "PASS " if ok else "FAIL ", title)
func frames(count: int):
	for i in count: await physics_frame
func run():
	var stage = Node3D.new()
	root.add_child(stage)
	stage.add_child(PARK.new())
	for angle in [0.0, PI * .5, PI, PI * 1.5]:
		var board = BOARD.new()
		board.position = LAYOUT.CENTER + Vector3(0, -LAYOUT.DEPTH + .1, 0)
		board.rotation.y = angle
		stage.add_child(board)
		await frames(20)
		board.riding = true
		board.drive(1, 0, false)
		var escaped := false
		for i in 480:
			await physics_frame
			var p := Vector2(board.position.x, board.position.z)
			var flat := (p - Vector2(LAYOUT.CENTER.x, LAYOUT.CENTER.z)) / LAYOUT.RADII
			if flat.length() / LAYOUT.outline_scale(flat.angle()) > 1.08 and board.position.y > -.1:
				escaped = true
				break
		check(escaped and board.riding, "leave actual bowl from rest heading %s (position %s)" % [angle, board.position])
		board.free()
	var board = BOARD.new()
	board.position = LAYOUT.CENTER + Vector3(0, -LAYOUT.DEPTH + .1, 0)
	stage.add_child(board)
	await frames(20)
	board.riding = true
	var start: Vector3 = board.position
	board.drive(-1, 0, false)
	await frames(45)
	check(board.speed < -.2 and board.position.z > start.z + .2 and board.is_on_floor(), "reverse from rest moves backward on the ground")
	board.drive(0, 0, true)
	await frames(60)
	check(absf(board.speed) < .1, "dedicated brake stops reverse")
	board.drive(1, 0, false)
	await frames(30)
	check(board.speed > .2, "forward command brakes reverse before pushing forward")
	board.free()
	stage.free()
	print("SKATE_MOBILITY_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
