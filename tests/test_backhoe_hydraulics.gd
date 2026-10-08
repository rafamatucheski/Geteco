extends "res://tests/test_mining_machine.gd"
## Real fleet/physics: independent joints, swept obstacles and control ownership.
func run() -> void:
	stage = Node3D.new(); root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80,1,80)
	floor_shape.shape = floor_box; floor_shape.position.y = -.5
	floor_body.add_child(floor_shape); stage.add_child(floor_body)
	machine = spawn("mining_backhoe",Vector3(0,.08,0))
	controls = machine.get_node("MiningMachine")
	controls.set_physics_process(false)
	await physics_frame
	var rear: Node = controls.rear
	check(rear != null,"backhoe has independently articulated rear controller")
	if rear == null: finish(); return
	var front: Vector3 = controls.cargo_anchor()
	var start: Vector3 = rear.bucket.global_position
	check(controls.operate_rear(Vector4(.5,0,0,0),.3),"rear turret rotates under hydraulic command")
	check(absf(rear.bucket.global_position.x-start.x) > .1,"swing moves physical digging bucket sideways")
	check(controls.cargo_anchor().is_equal_approx(front),"rear swing leaves front loader unchanged")
	var pose: Vector4 = rear.pose
	check(controls.operate(1,.3),"front loader remains operable")
	check(rear.pose.is_equal_approx(pose),"front operation leaves all rear joints unchanged")
	for axis in [1,2,3]:
		var motion := Vector4.ZERO; motion[axis] = -1.0 if axis == 1 else 1.0
		pose = rear.pose
		check(controls.operate_rear(motion,.18),"rear joint %d has an independent hydraulic command" % axis)
		for other in 4:
			if other != axis: check(is_equal_approx(rear.pose[other],pose[other]),"joint %d does not move joint %d" % [axis,other])
	# A real wall encloses only the next swing destination; a large delta must
	# stop at contact rather than jump through its thin thickness.
	var before: Vector4 = rear.pose
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new(); wall_box.size = Vector3(.10,5,12)
	wall_shape.shape = wall_box; wall.add_child(wall_shape)
	wall.position = Vector3(rear.bucket.global_position.x+1.0,2.5,4)
	stage.add_child(wall); await physics_frame
	controls.operate_rear(Vector4(1,0,0,0),10.0)
	check(rear.pose.x < rear.MAX_POSE.x-.05,"large hydraulic step stops before thin wall")
	check(rear.bucket.global_position.x < wall.position.x+.02,"rear scoop cannot tunnel through wall")
	check(rear.pose.x >= before.x,"blocked movement preserves last safe hydraulic pose")
	wall.queue_free(); await physics_frame
	# No independent controls when the engine is unavailable, a modal owns
	# input, the driver is absent or save restoration has not finished.
	machine.controlled = true
	check(controls.active(),"occupied machine exposes controls")
	machine.input_locked = true
	check(not controls.active(),"modal/transition lock blocks hydraulic input")
	machine.input_locked = false; machine.engine_disabled = true
	check(not controls.active(),"disabled engine blocks hydraulic input")
	machine.engine_disabled = false; machine.controlled = false
	check(not controls.active(),"parked machine cannot consume driver input")
	# Unoccupied collision still follows a moved carrier; rear physical volumes
	# have the same live collision owner and disappear with its destruction.
	machine.position += Vector3.RIGHT*6
	controls.operate(0,0)
	for shape in rear.shapes:
		check(shape.get_parent() == machine,"rear collider remains owned by carrier for pooling/death")
	var tractor := spawn("mining_tractor",Vector3(15,.08,0))
	check(tractor.get_node("MiningMachine").rear == null,"loader tractor does not acquire backhoe controls")
	print("BACKHOE_HYDRAULICS checks=",checks," failures=",failures.size())
	finish()
