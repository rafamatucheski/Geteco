extends SceneTree
## Real civilian feet and collision support, including interrupted AI throttle.
const BOARD = preload("res://activities/skate/SkateBody.gd")
const ACTOR = preload("res://scripts/Actor.gd")
const POSE = preload("res://activities/skate/SkatePose.gd")
const KIT = preload("res://assets/civilians/CivilianMeshKit.gd")
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		print("CONTACT FAIL ", label)
func run():
	for scenario in [{"slope": Vector3.ZERO, "speed": 0.0}, {"slope": Vector3(.20, 0, .16), "speed": 0.0}, {"slope": Vector3(-.20, 0, -.16), "speed": 0.0}, {"slope": Vector3(.20, 0, -.16), "speed": 8.0}]:
		var slope: Vector3 = scenario.slope
		var stage := Node3D.new()
		root.add_child(stage)
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(100, .2, 100)
		collision.shape = shape
		collision.position.y = -.1
		floor_body.add_child(collision)
		floor_body.rotation = slope
		stage.add_child(floor_body)
		var board = BOARD.new()
		board.position.y = .05
		stage.add_child(board)
		var actor = ACTOR.new()
		actor.identity = 5
		stage.add_child(actor)
		actor.set_physics_process(false)
		var model = actor.visual.get_child(0)
		model.set_process(false)
		board.add_collision_exception_with(actor)
		for i in 30: await physics_frame
		board.riding = true
		board.speed = scenario.speed
		board.drive(1, 0, false)
		var contacted := false
		var finished := false
		var planted := Vector3.ZERO
		var contact_frames := 0
		for i in 100:
			await physics_frame
			actor.position = board.position
			POSE.apply(actor, board)
			if board.push_contact:
				var sole: Vector3 = model.feet[1].global_position - model.feet[1].global_basis.y * KIT.ANKLE_HEIGHT
				if not contacted:
					contacted = true
					planted = sole
					board.drive(0, 0, false)
				contact_frames += 1
				check(sole.distance_to(planted) < .012, "shoe stays planted as board rolls on slope %s" % slope)
				check(model.feet[1].global_basis.y.normalized().dot(floor_body.global_basis.y) > .999, "sole follows real support normal")
				check(absf(floor_body.to_local(sole).y) < .012, "sole touches physical ground")
			if contacted and not board.pushing:
				finished = true
				check(board.visual.global_basis.y.dot(floor_body.global_basis.y) > .999, "deck follows pitch and cross slope")
				check(model.upper_arms[0].rotation.z > -.3, "cruising arms relax beside the body")
				break
		check(contacted and contact_frames > 3, "visible ground contact on slope %s" % slope)
		check(finished, "stroke returns to board after throttle release")
		board.ollie()
		await physics_frame
		check(not board.pushing and not board.push_contact, "takeoff releases ground foot")
		stage.free()
	print("SKATE_CONTACT_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
