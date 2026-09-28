extends SceneTree
var failures := 0
var checks := 0
var world
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	var edge := {"width":14.0,"lanes":2,"one_way":false}
	check(graph._lane_offset(Vector3.RIGHT,edge,0).is_equal_approx(Vector3(0,0,1.75)),"Inner eastbound lane at 1.75 m")
	check(graph._lane_offset(Vector3.RIGHT,edge,1).is_equal_approx(Vector3(0,0,5.25)),"Outer eastbound lane at 5.25 m")
	check(graph._lane_offset(Vector3.LEFT,edge,1).is_equal_approx(Vector3(0,0,-5.25)),"Opposing lane remains on correct side")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if failures: quit(1); return
	var ops=world.production.urban_transit.urban_service
	for frame in 120:
		await physics_frame
		if ops.prepared: break
	print("TRANSIT_BUILD ",ops.failure," stops=",ops.stops.size()," fleet=",ops.fleet.size())
	check(ops.route!=null and ops.stops.size()==6,"Six stations align with connected outer-lane circuit")
	check(ops.fleet.size()==2,"Two independent biarticulated services")
	if failures: quit(1); return
	var bus=ops.fleet[0]
	world.player.teleport(ops.stops[bus.service_stop].inside)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.35
	world.session.weather.set_process(false)
	for frame in 180: await physics_frame
	check(bus.sections.size()==3 and bus.bellows.size()==2,"Three collision bodies and two articulations")
	print("TRANSIT_BUS active=",bus.active," state=",bus.service_state," blocker=",bus.blocked_by," position=",bus.global_position)
	for p in ops.people:
		if p.stop==bus.service_stop: print("TRANSIT_PERSON ",p.id," ",p.phase," at=",p.actor.global_position if is_instance_valid(p.actor) else Vector3.INF)
	var folder := "res://evidence/biarticulated"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var poses := []
	var blocked := []
	# Audit the real streamed collision for all three bodies at every metre.
	bus.set_active(false)
	for other in ops.fleet: other.set_active(false)
	ops.set_physics_process(false)
	for p in ops.people:
		if is_instance_valid(p.actor): p.actor.collision_layer=0; p.actor.set_physics_process(false)
	for distance in range(0,ceili(ops.route.get_baked_length()),2):
		var trial: Array[Transform3D]=ops.path_poses.at(distance)
		for pose in trial: world.production.regions.harbor.prepare_collision_at(pose.origin)
		await physics_frame
		bus._apply_poses(trial,false)
		if not bus.admits(trial,false): blocked.append({"distance":distance,"by":bus.blocked_by,"position":str(trial[0].origin)})
		poses.append([trial[0].origin.x,trial[0].origin.z])
	FileAccess.open(folder+"/route-audit.json",FileAccess.WRITE).store_string(JSON.stringify({"blocked":blocked,"route":poses}))
	check(blocked.is_empty(),"Whole articulated hull clears the complete real corridor")
	print("TRANSIT_BLOCKED ",JSON.stringify(blocked.slice(0,15)))
	print("BIARTICULATED ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
