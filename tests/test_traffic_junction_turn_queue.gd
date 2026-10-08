extends "res://tests/test_traffic_junction_completed_turn.gd"
## Four real civilian Vehicles: two leaders turning towards one another and
## their following cars. Explicit committed leaders; followers request actual
## green admission before movement. There is no convoy or formation controller.

func _initialize() -> void:
	create_timer(75).timeout.connect(func(): push_error("turn queue timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if not ClassDB.class_exists(&"CSharpScript") or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	setup_graph()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160,.2,160)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(375,-.1,-262.5)
	world.add_child(floor_body)
	# Rounded corners with the normal 3 m trim/0.55 handle ratio.
	var route_w := curve([Vector3(382.5,0,-220),Vector3(382.5,0,-260.85),Vector3(379.5,0,-263.85),Vector3(325,0,-263.85)])
	route_w.set_point_out(1,Vector3.FORWARD*1.65)
	route_w.set_point_in(2,Vector3.RIGHT*1.65)
	var route_e := curve([Vector3(367.5,0,-305),Vector3(367.5,0,-264.11),Vector3(370.5,0,-261.11),Vector3(430,0,-261.11)])
	route_e.set_point_out(1,Vector3.BACK*1.65)
	route_e.set_point_in(2,Vector3.LEFT*1.65)
	var leaders := [make_car(Vector3(382.5,.04,-258),0,route_w),make_car(Vector3(367.5,.04,-267),PI,route_e)]
	var followers := [make_car(Vector3(382.5,.04,-249.5),0,route_w),make_car(Vector3(367.5,.04,-275.5),PI,route_e)]
	for frame in 3: await physics_frame
	J.register_signal(EAST,7.0)
	J.register_signal(WEST,7.0)
	for i in 2:
		var center: Vector3 = EAST if i==0 else WEST
		var heading := Vector3.FORWARD if i==0 else Vector3.BACK
		committed(leaders[i],center,heading)
		var car: CharacterBody3D = followers[i]
		car._junction_route=car.route
		car._junction_list=J.along(car.route)
		var key := J.key_of(center)
		var offset: float = car.route.get_closest_offset(center)
		car.position=car.route.sample_baked(offset-car.half_length-8.0,true)+Vector3.UP*.04
		var gap: float = offset-car.route.get_closest_offset(car.position)-car.half_length-7.0
		J._phase_frame=Engine.get_process_frames()
		# Restore each approach's own green admission snapshot. These two
		# signals have different phases, not a fabricated simultaneous green.
		J._phase_time=J.CYCLE*.5+1.0-J._offset(center)
		check(J.signal_state(key,heading)=="green","arrival uses its own real green phase")
		var admitted := J.request(key,car.get_instance_id(),heading,gap,0)
		check(not admitted,"green follower stays outside while its predecessor is still turning: %d"%i)
		if admitted:
			car._held_junction=key
			car._held_offset=offset
		print("QUEUE_ADMISSION index=",i," gap=",gap," admitted=",admitted)
	admission_contracts(leaders[0],followers[0])
	# Stop-controlled crossings isolate reservation behavior from waiting phases.
	# Green policy is independently checked above; no signal changed in production.
	J._signals.clear()
	for car in leaders+followers: car.set_physics_process(true)
	for frame in 2700: await physics_frame
	for i in 2:
		var leader: CharacterBody3D=leaders[i]
		var follower: CharacterBody3D=followers[i]
		var cleared: bool = leader.position.x<350 and follower.position.x<355 if i==0 else leader.position.x>400 and follower.position.x>395
		check(cleared,"both cars in queue %d physically clear the close crossings"%i)
		print("QUEUE_TRACE index=",i," leader=",leader.position," leader_wait=",leader.junction_wait," follower=",follower.position," follower_wait=",follower.junction_wait," held=",J.owners)
	world.free()
	print("TURN_QUEUE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func admission_contracts(leader: CharacterBody3D, follower: CharacterBody3D) -> void:
	var key := J.key_of(EAST)
	check(J._turn_queue_blocked(key,follower,1.0),"same-turn predecessor physically in crossing retains its one queue slot")
	var pose: Transform3D=leader.transform
	leader.position=Vector3(330,.04,-263.85)
	check(J.owners[key].has(leader.get_instance_id()) and not J._turn_queue_blocked(key,follower,1.0),"a lease outside the physical crossing does not block the following turn")
	check(J._turn_queue_blocked(key,follower,8.0),"short-turn queue cannot prebook far before the stop line")
	leader.transform=pose
	var saved_owners: Dictionary=J.owners.duplicate(true)
	J.owners.clear()
	var straight_route := curve([Vector3(420,0,-264),Vector3(320,0,-264)])
	var a := make_car(Vector3(389,.04,-264),PI/2,straight_route)
	var b := make_car(Vector3(397,.04,-264),PI/2,straight_route)
	for car in [a,b]:
		car._junction_route=straight_route
		car._junction_list=J.along(straight_route)
	J._phase_frame=Engine.get_process_frames()
	J._phase_time=1.0-J._offset(EAST)
	check(J.request(key,a.get_instance_id(),Vector3.LEFT,4,3) and J.request(key,b.get_instance_id(),Vector3.LEFT,12,3),"ordinary straight parallel flow retains multiple green reservations")
	a.free()
	b.free()
	J.owners=saved_owners
	var saved_rows: Array=follower._junction_list
	var far_rows: Array=saved_rows.duplicate(true)
	far_rows[1].offset=float(far_rows[0].offset)+60.0
	follower._junction_list=far_rows
	check(not J._turn_queue_blocked(key,follower,8.0),"turn towards a well-separated junction retains ordinary early admission")
	follower._junction_list=saved_rows
	# Already crossing the stop line is never ordered to stop inside by this gate.
	var previous: Dictionary=J.owners[key].duplicate(true)
	J.owners[key].erase(follower.get_instance_id())
	check(J.request(key,follower.get_instance_id(),Vector3.FORWARD,-2.0,2.0),"committed entry still clears the crossing despite queued-turn policy")
	J.owners[key]=previous
