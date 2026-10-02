extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var yard := preload("res://assets/maciota/GarageBackyard.gd").new()
	root.add_child(yard)
	var probe := CharacterBody3D.new()
	probe.collision_layer=2
	probe.collision_mask=1
	var shape := CapsuleShape3D.new()
	shape.radius=.3
	shape.height=1.7
	var collision := CollisionShape3D.new()
	collision.shape=shape
	collision.position.y=.85
	probe.add_child(collision)
	root.add_child(probe)
	await physics_frame
	await physics_frame
	# Fast sweeps against each prop, from both sides of the yard.
	for case in [[Vector3(-2,.05,-5),Vector3(0,0,4),"car"],
		[Vector3(-5,.05,-2),Vector3(0,0,3),"engine pallet"],
		[Vector3(-2.25,.05,2),Vector3(0,0,-2),"detached panels"],
		[Vector3(.73,.05,-2),Vector3(0,0,3),"tires"],
		[Vector3(4.05,.05,-2),Vector3(0,0,3),"bin one"],
		[Vector3(4.94,.05,-2),Vector3(0,0,3),"bin two"],
		[Vector3(5.83,.05,-2),Vector3(0,0,3),"bin three"]]:
		probe.position=case[0]
		if probe.move_and_collide(case[1],true)==null: failures.append("Unblocked "+case[2])
	# Cross-yard route and the side passage remain usable, including oil patches.
	for case in [[Vector3(-7,.05,-3.8),Vector3(15,0,0)],
		[Vector3(2.2,.05,-4),Vector3(0,0,5)],
		[Vector3(1.35,.05,-1.4),Vector3(0,0,.3)]]:
		probe.position=case[0]
		if probe.move_and_collide(case[1],true)!=null: failures.append("Blocked clear path at "+str(case[0]))
	if yard.find_children("*Solid","StaticBody3D",false,false).size()!=7: failures.append("Incomplete prop collision inventory")
	for failure in failures: push_error(failure)
	print("GARAGE_BACKYARD ","PASS" if failures.is_empty() else "FAIL"," 11 checks; failures=",failures.size())
	probe.free()
	yard.free()
	quit(0 if failures.is_empty() else 1)
