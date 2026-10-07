extends "res://tests/test_desert_community_session.gd"
## Real rendered Main and real vehicle physics. Campaign states are valid test
## fixtures; this does not claim to replay the entire desert campaign.
const PASS_LAYOUT:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const STORY:=preload("res://runtime/desert/DesertStoryState.gd")
const VEHICLE:=preload("res://scripts/Vehicle.gd")

func overview(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var camera:=root.get_camera_3d()
	var previous:=camera.size
	camera.size=52
	await photo(label)
	camera.size=previous

func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("NORTH_PASS_SESSION timeout"); quit(3))
	folder=FIXTURE.output_dir("desert-north-pass-session")
	var at:=Vector3(349,.08,-1515)
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id="desert"
	# A legacy checkpoint could stand here before this worksite was authored.
	snapshot.world.pedestrian={"region":"desert","position":[349,.08,-1900]}
	var path:=FIXTURE.write_fixture(folder,"save.json",snapshot)
	check(not path.is_empty(),"isolated closed-road checkpoint valid")
	if path.is_empty(): quit(1); return
	await boot(path)
	check(world.player.global_position.distance_to(Vector3(348,.02,-1778))<.6,"legacy unfinished save north of works restores to safe southern shoulder")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# router")
	if "--art-review" in OS.get_cmdline_user_args():
		await art_review()
		return
	await stage_at(at)
	await create_timer(2).timeout
	var pass_runtime=world.session.desert.extras.north_pass
	pass_runtime.refresh()
	check(not PASS_LAYOUT.completed(world.session.state.world_state),"unfinished desert campaign keeps worksite")
	await photo("north-highway-junction")
	# Main already supplies PlayerCoupe here; a second spawn would overlap it.
	# Only this isolated fixture sets its initial heading after normal admission.
	var car: CharacterBody3D=world.driving.car
	check(is_instance_valid(car),"production player car exists")
	if not is_instance_valid(car): quit(1); return
	var start:=Vector3(345,.1,-1515)
	check(world.production.vehicle_position_clear(car,start,0),"production car body and four supports clear at junction")
	if not world.production.vehicle_position_clear(car,start,0): quit(1); return
	car.global_position=start
	car.rotation.y=0
	car.velocity=Vector3.ZERO
	car.horizontal_velocity=Vector3.ZERO
	car.speed=0
	await physics_frame
	var left_lane:=car.global_transform
	left_lane.origin=Vector3(339.5,car.global_position.y,-1527)
	check(not car.test_move(left_lane,Vector3(0,0,-24)),"actual car sweep on left lane clears relocated utility pole")
	world.player.teleport(car.driver_door_anchor(1)+Vector3(.4,.05,0))
	check(world.driving.interact(),"ordinary vehicle boarding")
	var deadline:=Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	check(world.driving.occupied and world.driving.car==car and not car.input_locked,"driver controls ready")
	Input.action_press("accelerate",.25)
	for i in 1800:
		await physics_frame
		if car.global_position.z<-1750: break
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	for i in 150: await physics_frame
	Input.action_release("handbrake")
	check(car.global_position.z<-1750 and car.global_position.z>-1796,"ordinary input drives from junction and stops safely before work barrier")
	check(car.global_position.y>-.2 and car.is_on_floor(),"closed-road car remains supported")
	check(car.test_move(car.global_transform,Vector3(0,0,-80)),"real car shape is blocked by physical worksite")
	pass_runtime.refresh()
	var gates:=get_nodes_in_group(PASS_LAYOUT.GROUP)
	check(gates.size()==1 and gates[0].visible,"one visible streamed landslide")
	check(is_instance_valid(pass_runtime._workers) and pass_runtime._workers.get_child_count()==2,"two working models only near site")
	await photo("closed-road-gameplay")
	await overview("closed-road-overview")
	for flag in STORY.FLAGS:
		if not STORY.data(world.session.state.world_state)[flag]: check(STORY.mark(world.session.state.world_state,flag),"public story checkpoint mark "+str(flag))
	pass_runtime.refresh()
	await physics_frame
	check(not gates[0].visible and not is_instance_valid(pass_runtime._workers),"validated final campaign state removes works and workers")
	await photo("opened-road-gameplay")
	# Sweep uses this real car's own collision shape, independently of speed.
	check(not car.test_move(car.global_transform,Vector3(0,0,-115)),"real car capsule clears released road")
	Input.action_press("accelerate",.32)
	for i in 1200:
		await physics_frame
		if car.global_position.z<-1895: break
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	for i in 150: await physics_frame
	Input.action_release("handbrake")
	check(car.global_position.z<-1860 and car.global_position.y>-.2,"real car drives through opened pass and chunk seam")
	check(world.driving.interact(),"ordinary exit after north drive")
	deadline=Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	check(not world.driving.occupied,"driver exits safely in released corridor")
	await stage_at(Vector3(349,.08,-1928))
	await photo("north-turnaround-and-map-end")
	await overview("north-cut-overview")
	check(world.session.position_clear(Vector3(342.5,.08,-1934)),"supported turning space before final guardrail")
	# Save/restore semantics use the same authored campaign condition.
	await stage_at(Vector3(349,.08,-1810))
	check(world.session.save_game(),"completed pass checkpoint writes isolated disk")
	var persisted:=STORE.read_valid(path)
	check(not persisted.is_empty() and PASS_LAYOUT.completed(persisted.world),"saved final campaign restores open passage condition")
	world.free()
	await process_frame
	await boot(path)
	pass_runtime=world.session.desert.extras.north_pass
	pass_runtime.refresh()
	check(PASS_LAYOUT.completed(world.session.state.world_state) and not is_instance_valid(pass_runtime._workers),"cold save reload preserves open road without workers")
	check(world.player.global_position.distance_to(Vector3(349,.02,-1810))<.5,"completed checkpoint inside former landslide restores without fallback relocation")
	await stage_at(Vector3(342.5,.08,-1530))
	await create_timer(.4).timeout
	check(not is_instance_valid(pass_runtime._workers),"workers absent away from completed site")
	await photo("north-highway-junction")
	# Final visual follow-up to the community run: continuous pipe to the existing
	# tower outlet, added after that run exposed a short disconnected inlet.
	await stage_at(SITE.RADIO)
	await create_timer(.5).timeout
	await photo("community-connected-tower-pipe")
	print("DESERT_NORTH_PASS_SESSION checks=%d failures=%d evidence=%s"%[checks,failures,folder])
	quit(0 if failures==0 else 1)

func art_review() -> void:
	# Focused recheck after the rock profile/material and utility-pole corrections;
	# the prior full ordinary-input/cold-save run remains separate evidence.
	await stage_at(Vector3(349,.08,-1534))
	var car: CharacterBody3D=world.driving.car
	var virtual_pose:=car.global_transform
	virtual_pose.basis=Basis.IDENTITY
	virtual_pose.origin=Vector3(339.5,.08,-1527)
	check(not car.test_move(virtual_pose,Vector3(0,0,-24)),"real car swept volume clears former pole in left lane")
	await photo("north-highway-junction-corrected")
	await overview("north-junction-overview")
	await stage_at(Vector3(345,.08,-1790))
	var pass_runtime=world.session.desert.extras.north_pass
	pass_runtime.refresh()
	await create_timer(.5).timeout
	check(is_instance_valid(pass_runtime._workers) and pass_runtime._workers.get_child_count()==2,"workers remain on cleared shoulders")
	await photo("closed-road-gameplay-corrected")
	await overview("closed-road-overview-corrected")
	for flag in STORY.FLAGS:
		if not STORY.data(world.session.state.world_state)[flag]: check(STORY.mark(world.session.state.world_state,flag),"fixture final flag "+str(flag))
	pass_runtime.refresh()
	await physics_frame
	# This is an unoccupied fixture car. Move Dante out of its virtual swept
	# lane; otherwise the query correctly collides with the test's own actor.
	await stage_at(Vector3(349,.08,-1810))
	virtual_pose.origin=Vector3(345,.08,-1786)
	var collision:=KinematicCollision3D.new()
	var blocked: bool=car.test_move(virtual_pose,Vector3(0,0,-152),collision)
	if blocked: print("NORTH_ART_BLOCKER ",collision.get_collider().get_path()," position=",collision.get_position())
	check(not blocked,"real car swept volume clears both new rock faces along released road")
	await photo("opened-road-actor-corrected")
	await stage_at(Vector3(349,.08,-1928))
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	for x in [300.0,383.0]:
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,1,-1930),Vector3(x,1,-1955),1)
		# Boundary outcrops may already occupy the ray's starting point.
		ray.hit_from_inside=true
		var boundary:=space.intersect_ray(ray)
		check(not boundary.is_empty(),"outer north boundary prevents bypass/fall x="+str(x))
	await photo("north-turnaround-corrected")
	await overview("north-cut-overview-corrected")
	print("DESERT_NORTH_ART checks=%d failures=%d evidence=%s"%[checks,failures,folder])
	quit(0 if failures==0 else 1)
