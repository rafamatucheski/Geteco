extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var gate := preload("res://runtime/terminal/TerminalGate.gd").new()
	stage.add_child(gate)
	var coach := preload("res://runtime/terminal/TerminalCoach.gd").new()
	coach.position = Vector3(0,.1,-8)
	stage.add_child(coach)
	var route := Curve3D.new()
	route.add_point(coach.position); route.add_point(Vector3(0,.1,8))
	coach.set_path(route)
	coach.gate_stop = gate.stop_distance(coach,route)
	check(coach.gate_stop>3 and coach.gate_stop<5,"Stop protects full coach nose with margin")
	await physics_frame
	check(coach.test_move(coach.global_transform,Vector3(0,0,8)),"Closed arm physically blocks coach")
	coach.progress = coach.gate_stop
	gate.clearance(coach)
	gate.tick(.1)
	check(gate.state=="checking" and gate.requests==1,"Stopped coach requests authorization")
	gate.tick(1)
	check(gate.opening==0,"Arm waits for authorization delay")
	gate.tick(1.3)
	for frame in 80: gate.tick(1.0/60)
	check(gate.state=="passing" and gate.authorizations==1,"Authorized coach receives open arm")
	await physics_frame
	check(not coach.test_move(coach.global_transform,Vector3(0,0,8)),"Open arm frees the physical lane")
	coach.position.z = 1
	gate.tick(.1)
	check(gate.state=="passing","Rear of coach keeps gate open")
	coach.position.z = 5
	await physics_frame
	gate.tick(.1)
	check(gate.state=="closing" and coach.gate_passed,"Whole hull must clear before closing")
	var person := StaticBody3D.new()
	person.collision_layer = 2
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7; shape.radius = .3
	capsule.shape = shape
	capsule.position.y = .86
	person.add_child(capsule)
	stage.add_child(person)
	await physics_frame
	gate.tick(.5)
	check(gate.opening>=.99 and gate.collider.disabled,"Pedestrian under arm prevents closure")
	person.free()
	await physics_frame
	for frame in 80: gate.tick(1.0/60)
	check(gate.state=="closed" and not gate.collider.disabled,"Empty gate closes and restores collision")
	stage.free()
	print("TERMINAL_GATES ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
