extends SceneTree
## Real streamed region + Actor + Vehicle. Isolated geometry, not Main FPS evidence.
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DESERT_LAYOUT := preload("res://world/desert/DesertLayout.gd")
var region
var actor
var stage: Node3D
var camera: Camera3D
var output := ""
var failures: Array[String]=[]
var trace: Array[Dictionary]=[]
var temporal: Array[Dictionary]=[]

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("Canyon access watchdog"); quit(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	print("CANYON_ACCESS ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	output="res://evidence/smuggler-canyon-access-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1280,720)
	stage=Node3D.new(); root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("b4afa0")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e0d1b5")
	env.environment.ambient_light_energy=.65
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,-20,0); sun.light_energy=.9
	stage.add_child(sun)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=26; camera.far=500
	stage.add_child(camera); camera.current=true
	region=REGION.new(); region.initial_focus=L.APPROACH; stage.add_child(region)
	actor=ACTOR.new(); actor.is_player=true; actor.controlled_automatically=true
	actor.speed=6.5; actor.position=L.APPROACH+Vector3.UP*.2; stage.add_child(actor)
	var bridge_mid: Vector3=L.BRIDGE_START.lerp(L.BRIDGE_END,.5)
	var lateral_scale: float=L.BOUNDS.size.x/270.0
	for i in 20: await physics_frame
	if "--site-only" in OS.get_cmdline_user_args():
		await check_site_access()
		finish()
		return
	if not await walk(L.BRIDGE_START+Vector3(0,.12,1),12): finish(); return
	await photo("entrance")
	if not await walk(bridge_mid+Vector3.UP*.12,30): finish(); return
	await photo("bridge-gameplay")
	for side in [-1.0,1.0]:
		# Geology narrows while the walking deck keeps its3.8m width. Sample
		# outside the deck at the same relative floor/scarp/rim locations.
		var floor_offset := maxf(L.BRIDGE_WIDTH*.5+.6,10.0*lateral_scale)
		var at := Vector3(L.CENTER.x+side*floor_offset,2,bridge_mid.z)
		region.prepare_collision_at(at)
		await physics_frame
		var ray := PhysicsRayQueryParameters3D.create(at,at-Vector3.UP*100,1)
		var hit := stage.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.position.y<-L.DEPTH*(50.0/72.0),"scaled physical gorge depth on side %s (no flat hidden floor)"%side)
		for offset in [15.0,22.0,28.0]:
			var probe := Vector3(L.CENTER.x+side*offset*lateral_scale,2,bridge_mid.z)
			region.prepare_collision_at(probe)
			await physics_frame
			var probe_hit := stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe,probe-Vector3.UP*100,1))
			var predicted := preload("res://world/desert/canyon/DesertSmugglerTerrain.gd").surface_height(Vector2(probe.x,probe.z))
			check(not probe_hit.is_empty() and absf(probe_hit.position.y-predicted)<.03,"refined scarp physical/query agreement %s"%probe)
		var rim := Vector3(L.CENTER.x+side*38.0*lateral_scale,2,bridge_mid.z)
		region.prepare_collision_at(rim)
		await physics_frame
		var rim_hit := stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(rim,rim-Vector3.UP*100,1))
		check(not rim_hit.is_empty() and rim_hit.position.y>-L.DEPTH*(10.0/72.0),"nearby upper rim frames side %s"%side)
	if not await walk(Vector3(L.CENTER.x+.725,.12,L.GATE_Z-4),25): finish(); return
	if not await walk(L.BRIDGE_END+Vector3(.725,.12,3),10): finish(); return
	await photo("pedestrian-gate")
	if not await walk(L.CENTER,12): finish(); return
	await photo("camp-gameplay")
	for at in L.combat_spawn_points():
		region.prepare_collision_at(at)
		await physics_frame
		actor.position=at+Vector3.UP*.15
		check(not actor.test_move(actor.global_transform,Vector3.UP*.01),"guard spawn capsule clear %s"%at)
	actor.position=L.CENTER+Vector3(0,.15,0)
	actor.automatic_direction=Vector3.ZERO
	for id in ["desert_coyote","desert_bison","bike_urban"]:
		var car := VEHICLE.new(); car.archetype=id
		car.position=Vector3(L.CENTER.x+.725,.25,L.GATE_Z-8); car.rotation.y=PI
		stage.add_child(car); car.set_external_driver(true)
		for i in 15: await physics_frame
		check(car.test_move(car.global_transform,Vector3(0,0,14)),id+" swept body blocked by gate")
		car.throttle_input=.65
		for i in 180: await physics_frame
		check(car.position.z<L.GATE_Z-1 and car.position.y>-.5,id+" actual drive cannot enter camp")
		car.queue_free(); await physics_frame
	actor.position=L.BRIDGE_END+Vector3(.725,.2,3)
	if not await walk(Vector3(L.CENTER.x+.725,.12,L.GATE_Z-4),10): finish(); return
	if not await walk(bridge_mid+Vector3.UP*.12,30): finish(); return
	if not await walk(L.APPROACH,35): finish(); return
	await photo("returned")
	region.set_focus(DESERT_LAYOUT.TRUCK_STOP)
	for i in 30: await physics_frame
	check(not region.chunks.has(region._cell(L.BRIDGE_END)),"distant focus actually releases the canyon bridge chunk")
	region.set_focus(L.BRIDGE_END)
	region.prepare_collision_at(L.BRIDGE_END)
	for i in 15: await physics_frame
	actor.position=L.BRIDGE_END+Vector3.UP*.3
	for i in 30: await physics_frame
	check(actor.is_on_floor() and actor.position.y>-.2,"bridge support restored after streaming return")
	camera.size=maxf(L.BOUNDS.size.x,L.BOUNDS.size.y)*1.1
	camera.position=L.CENTER+Vector3(L.BOUNDS.size.x*.5,L.DEPTH+L.BOUNDS.size.y*.5,-L.BOUNDS.size.y*.65)
	camera.look_at(bridge_mid-Vector3.UP*L.DEPTH*.35)
	await photo("overview-diagnostic")
	finish()

func walk(target: Vector3,seconds: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	var frame := 0
	var seam_z := floorf(((L.BRIDGE_START.z+L.BRIDGE_END.z)*.5)/REGION.CELL)*REGION.CELL
	var recording_half_span := minf(18.0,L.BRIDGE_START.distance_to(L.BRIDGE_END)*.2)
	while Time.get_ticks_msec()<deadline:
		var move: Vector3=target-actor.position; move.y=0
		if move.length()<.3:
			actor.automatic_direction=Vector3.ZERO
			return check(true,"walked to %s"%target)
		actor.automatic_direction=move.normalized()
		region.set_focus(actor.position)
		camera.size=lerpf(26,L.CAMERA_SIZE,L.camera_weight(actor.position))
		camera.position=actor.position+Vector3(0,25.3,25.3)
		camera.look_at(actor.position+Vector3.UP*.8)
		if frame%30==0: trace.append({"ms":Time.get_ticks_msec(),"at":str(actor.position),"floor":actor.is_on_floor()})
		if actor.position.y<-.5:
			return check(false,"lost bridge support at %s"%actor.position)
		if "--record-canyon" in OS.get_cmdline_user_args() and frame%6==0 and absf(actor.position.z-seam_z)<recording_half_span and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var stamp := Time.get_ticks_msec()
			var filename := "temporal-%d.png"%stamp
			root.get_texture().get_image().save_png(output.path_join(filename))
			temporal.append({"ms":stamp,"file":filename,"position":str(actor.position)})
		await physics_frame
		frame+=1
	actor.automatic_direction=Vector3.ZERO
	await photo("walk-stalled")
	return check(false,"walk stalled at %s toward %s"%[actor.position,target])

func check_site_access() -> void:
	region.set_focus(L.CENTER)
	region.prepare_collision_at(L.CENTER)
	actor.position=L.BRIDGE_END+Vector3(.725,.2,3)
	for i in 30: await physics_frame
	if not await walk(L.CENTER,12): return
	await photo("hideout-arrival")
	if not await walk(L.ARMORY_POS+Vector3(0,.12,1.5),10): return
	await photo("hideout-armory")
	if not await walk(L.CENTER,10): return
	for at in L.combat_spawn_points():
		region.prepare_collision_at(at)
		await physics_frame
		actor.position=at+Vector3.UP*.15
		check(not actor.test_move(actor.global_transform,Vector3.UP*.01),"hideout guard spawn clear %s"%at)
		for i in 10: await physics_frame
		check(actor.is_on_floor() and actor.position.y>-.2,"hideout guard floor support %s"%at)
	actor.position=L.CENTER+Vector3.UP*.15
	if not await walk(L.BRIDGE_END+Vector3(.725,.12,3),12): return

func photo(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func finish() -> void:
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"trace":trace,"temporal_sequence":temporal,"scope":"Isolated production region, physical Actor route and Vehicle gate, no combat or Main performance certification. Optional timestamped readback sequence crosses bridge streaming seam; inspect recorded timestamps for actual cadence. Site-only mode checks the hideout after prop edits."},"\t"))
	print("CANYON_ACCESS_RESULT ",output)
	quit(0 if failures.is_empty() else 1)
