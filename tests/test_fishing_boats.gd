extends "res://tests/test_harbor_life.gd"
func run() -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	world.player.controlled_automatically=true
	world.player.teleport(Vector3(238.6,.2,189))
	world.production.region.set_focus(world.player.position)
	var terminal=world.session.urban_operations.passenger_terminal
	for i in 30: await physics_frame
	terminal.refresh_context()
	terminal.boat_locks._process(.2)
	check(terminal.boat_locks.nearby.size()==1,"only nearby fishing boat gets a small lock")
	world.player.teleport(Vector3(223,.2,203))
	terminal.boat_locks._process(.2)
	check(terminal.boat_locks.nearby.is_empty(),"locks disappear away from boats")
	for i in 2:
		terminal._ensure_angler(i)
		var actor=terminal.anglers[i]
		check(is_instance_valid(actor),"fisher %d has a free post"%i)
		if not is_instance_valid(actor): continue
		for frame in 15: await physics_frame
		check(actor.is_on_floor(),"fisher %d stays supported on the jetty"%i)
		var water: Vector3=actor.model.to_global(Vector3(.12,0,3.4))
		check(water.z<179.5 if i==0 else water.z>197,"line reaches open water beyond dock and hulls")
		actor.receive_damage(1000)
		check(not actor.fishing_line.visible,"dead fisher does not leave suspended fishing line")
	world.free()
	await process_frame
	print("FISHING_BOATS failures=",failures)
	quit(0 if failures.is_empty() else 1)
