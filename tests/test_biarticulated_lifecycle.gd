extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	var presentation=world.production.urban_transit
	var service=presentation.urban_service
	for frame in 120:
		await physics_frame
		if service.prepared: break
	check(service.fleet.size()==2 and service.people.size()==18,"Fleet and passenger identities exist")
	if failures: quit(1); return
	world.player.teleport(service.stops[0].inside)
	service.refresh_presence()
	# The source remains on screen during the first frame of a transition.
	# Visibility must not override the region/interior lifetime boundary.
	world.camera.set_process(false)
	world.camera.global_position=service.fleet[0].global_position+Vector3(0,25,25)
	world.camera.look_at(service.fleet[0].global_position)
	check(service.fleet[0].active and world.production._on_screen(service.fleet[0].global_position,25),"Fixture keeps active source bus on screen")
	var identities:=[]
	for bus in service.fleet: identities.append(bus.get_instance_id())
	world.production.state.region_id="mountain"
	presentation.on_region_changed()
	check(service.fleet.all(func(bus): return not bus.active),"Region change immediately suspends physical buses")
	check(service.fleet.all(func(bus): return bus.sections.all(func(part): return part.collision_layer==0)),"All three sections relinquish collision")
	check(service.people.all(func(p): return not is_instance_valid(p.actor) or not p.actor.visible),"Passenger actors suspend on region change")
	world.production.state.region_id="harbor"
	presentation.on_region_changed()
	for frame in 30: await physics_frame
	check(service.fleet[0].active,"Returning restores physically admitted nearby bus")
	check(service.fleet.all(func(bus): return bus.get_instance_id() in identities) and service.people.size()==18,"Returning conserves fleet and passenger identities")
	world.production.state.place_id="garage"
	presentation.on_region_changed()
	check(service.fleet.all(func(bus): return not bus.active),"Entering an interior suspends buses even with source camera visible")
	world.production.state.place_id=""
	presentation.on_region_changed()
	check(service.fleet[0].active,"Leaving the interior reuses the nearby bus")
	print("BIARTICULATED_LIFECYCLE ",checks," checks ",failures," failures")
	world.free()
	await process_frame
	quit(1 if failures else 0)
