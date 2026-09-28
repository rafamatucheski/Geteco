extends SceneTree
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,1,100)
	shape.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var a := BIKE.new()
	var b := BIKE.new()
	root.add_child(a); root.add_child(b)
	a.reset_to(Transform3D(Basis.IDENTITY,Vector3(0,.05,2)))
	b.reset_to(Transform3D(Basis.IDENTITY,Vector3(0,.05,0)))
	await frames(90)
	a.speed = 5; b.speed = 3
	a._planar_velocity = Vector3(0,0,-5)
	b._planar_velocity = Vector3(0,0,-3)
	a.drive(5.0/a.max_speed,0); b.drive(3.0/b.max_speed,0)
	var rubbed := false
	for i in 75:
		await physics_frame
		rubbed = rubbed or a._contact_cooldown>0 or b._contact_cooldown>0
	check(rubbed,"real hull contact produces a physical rubbing response")
	check(a.crash_count==0 and b.crash_count==0 and a.health==100 and b.health==100,"small relative impact lets both riders keep competing")
	a.reset_to(Transform3D(Basis.IDENTITY,Vector3(0,.05,4)))
	b.reset_to(Transform3D(Basis(Vector3.UP,PI),Vector3(0,.05,-4)))
	await frames(90)
	a.speed = 12; b.speed = 12
	a._planar_velocity = Vector3(0,0,-12)
	b._planar_velocity = Vector3(0,0,12)
	a.drive(1,0); b.drive(1,0)
	await frames(40)
	check(a.crash_count>0 and b.crash_count>0,"hard opposing impacts physically knock down both riders")
	check(a.health<100 and b.health<100 and a.health>=15 and b.health>=15,"contact damage remains nonfatal")
	a.drive(0,0,true); b.drive(0,0,true)
	await frames(900)
	check(a.crash_state=="riding" and b.crash_state=="riding","both riders recover after the impact")
	a.free(); b.free(); floor_body.free()
	print("MOTOCROSS_CONTACT_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
