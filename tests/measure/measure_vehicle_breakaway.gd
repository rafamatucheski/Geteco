extends "res://tests/measure/measure_desert.gd"
## Real Main/.NET population. Staged vehicles collide via normal movement/StreetPhysics.
## --vehicle-damage-baseline selects original models/response; --capture records temporal PNGs.
var failures: Array[String] = []
var car: CharacterBody3D
var target: CharacterBody3D
var anchor := Vector3.ZERO
var yaw := 0.0
var collisions: Array[Dictionary] = []
var capture := false
var legacy := false
var debris_support: Array[Dictionary] = []
var reload_path := ""
var saved_path := ""
var player_model := "sport_coupe"
var traffic_model := "metro_hatch"
var capture_frames: Array[Dictionary] = []
var buffered_images: Array[Dictionary] = []
var display_at_start: Dictionary = {}
var ready_msec := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	capture = "--capture" in args
	legacy = "--vehicle-damage-baseline" in args
	for arg in args:
		if arg.begins_with("--reload="): reload_path=arg.trim_prefix("--reload=")
		if arg.begins_with("--player-model="): player_model=arg.trim_prefix("--player-model=")
		if arg.begins_with("--traffic-model="): traffic_model=arg.trim_prefix("--traffic-model=")
	if DisplayServer.get_name()=="headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	seed(21102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("vehicle-breakaway-"+("baseline" if legacy else "candidate")+("-capture" if capture else ""))
	var fixture:=FIXTURE.full_snapshot(Vector3(37.625,.12,18.875),true)
	if player_model!="sport_coupe":
		fixture.world.vehicles=[{"archetype":player_model,"vehicle_id":"breakaway-player","position":[37.625,.12,18.875],"yaw":0.0,"health":float(preload("res://runtime/FleetCatalog.gd").spec(player_model).get("durability",180)),"region":"harbor","was_driven":false,"paint":"d44233ff"}]
	var path:=reload_path if not reload_path.is_empty() else FIXTURE.write_fixture(output,"initial.json",fixture)
	fingerprint=source_fingerprint()
	fingerprint["user://settings.cfg"]=FileAccess.get_sha256("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else "MISSING"
	fingerprint["res://gameplay/Gameplay.gd"]=FileAccess.get_sha256("res://gameplay/Gameplay.gd")
	fingerprint["res://ui/SkyMenu.gd"]=FileAccess.get_sha256("res://ui/SkyMenu.gd")
	fingerprint_directory("res://gameplay/dispatch")
	for resource in ["res://Main.tscn","res://scripts/World.gd","res://runtime/StartupCurtain.gd","res://runtime/SessionOperations.gd","res://ui/LoadingPresenter.cs","res://ui/LoadingArtwork.gd","res://ui/LoadingMusic.gd","res://runtime/FishingRuntime.gd","res://runtime/coastal_lookout/CoastalLookoutRuntime.gd","res://runtime/amusement_park/AmusementParkRuntime.gd","res://world/places/amusement_park/ParkLume.gd"]:
		fingerprint[resource]=FileAccess.get_sha256(resource) if FileAccess.file_exists(resource) else "MISSING"
	for resource in ["res://tests/measure/measure_vehicle_breakaway.gd","res://gameplay/vehicle_effects/VehicleBodyDents.gd","res://gameplay/vehicle_effects/VehicleBreakawayParts.gd","res://gameplay/vehicle_effects/VehiclePanelDebris.gd","res://gameplay/street_physics/StreetPhysics.gd","res://runtime/FleetState.gd"]:
		fingerprint[resource]=FileAccess.get_sha256(resource)
	for resource in ["res://gameplay/vehicle_effects/VehicleBlood.gd","res://gameplay/vehicle_effects/VehicleDamage.gd","res://runtime/FleetCatalog.gd","res://runtime/RedesignedFleet.gd","res://runtime/VehiclePaint.gd","res://runtime/VehicleUsage.gd","res://gameplay/VehicleDoorBuilder.gd","res://gameplay/VehicleDoorPresentation.gd"]:
		fingerprint[resource]=FileAccess.get_sha256(resource) if FileAccess.file_exists(resource) else "MISSING"
	for resource in ["res://gameplay/vehicle_effects/VehiclePanelCatalog.gd","res://assets/fleet/breakaway/sport_coupe.scn","res://assets/fleet/breakaway/monaliza.scn","res://assets/fleet/breakaway/metro_hatch.scn","res://assets/fleet/breakaway/police_cruiser.scn"]:
		fingerprint[resource]=FileAccess.get_sha256(resource) if FileAccess.file_exists(resource) else "MISSING"
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for frame in 7000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if not failures.is_empty(): quit(1); return
	ready_msec=Time.get_ticks_msec()
	check(world.production.store.path==path and not world.production.save_invalid,"isolated checkpoint")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"C# road backend active")
	if not failures.is_empty(): quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	car=world.driving.car
	if not reload_path.is_empty():
		await verify_production_reload(path)
		return
	anchor=world.production.nearest_road(car.global_position)+Vector3.UP*.12
	yaw=world.production.road_yaw(anchor)
	car.place(anchor,yaw)
	car.set_physics_process(false)
	target=world.production.spawn_vehicle(traffic_model,anchor-car.global_basis.z*11,yaw)
	check(is_instance_valid(target),"production traffic target created")
	if not failures.is_empty(): quit(1); return
	target.traffic=true
	target.route=null # Um carro de trânsito parado; a física do veículo e o solver de colisão comum continuam ativos.
	target.set_physics_process(false)
	world.camera.set_process(false)
	frame_pair()
	if "--normal-limit" not in args:
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(10).timeout
	for line in 16:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
		await process_frame
	check(not world.session.dialogue_open,"startup dialogue completed before collision scene")
	world.camera.locked=true
	world.camera.set_process(false)
	world.camera.set_physics_process(false)
	world.camera.reset_physics_interpolation()
	display_at_start=display_configuration()
	if capture:
		await shot("intact")
		for index in 2:
			await strike(index,true)
			await create_timer(.7).timeout
		frame_current_pair()
		await shot("damaged")
		check(not car.body_dents.dents.is_empty() and not target.body_dents.dents.is_empty(),"physical collision deforms both cars")
		if not legacy:
			check(car.breakaway_parts!=null and target.breakaway_parts!=null,"prototype supports current and traffic cars")
			if car.breakaway_parts!=null and target.breakaway_parts!=null:
				check(car.breakaway_parts.detached_count()>=2,"attacker loses front bumper and hood")
				check(car.breakaway_parts.snapshot().parts.get("bumper_rear",0.0)<1,"attacker rear bumper stays attached after front hit")
				check(target.breakaway_parts.snapshot().parts.get("bumper_rear",0.0)>=1,"traffic loses rear bumper")
				check(target.breakaway_parts.snapshot().parts.get("hood",0.0)<1,"traffic hood stays attached after rear hit")
		await create_timer(3).timeout
		frame_current_pair()
		inspect_debris_support()
		await shot("settled")
		var fragment_index:=0
		for fragment: RigidBody3D in get_nodes_in_group("vehicle_panel_debris"):
			world.camera.size=5
			world.camera.global_position=fragment.global_position+Vector3(3,4,-4)
			world.camera.look_at(fragment.global_position)
			await shot("ground-%02d-%s" % [fragment_index,fragment.panel_id])
			fragment_index+=1
		await closeup("player-damage",car)
		await closeup("traffic-damage",target)
		if not legacy: save_damaged_vehicle()
	else:
		await timed_window("idle",false)
		await timed_window("physical-impacts",true)
		await timed_window("recovery",false)
	check(car.health>0 and target.health>0 and not car.damage_look.burning and not target.damage_look.burning,"collision leaves vehicles usable")
	var state:={"car":FLEET_CAPTURE(car),"traffic":FLEET_CAPTURE(target)}
	var result:={"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"args":args,"isolated_save":path,"native_csharp":world.dispatch.router._native!=null,"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"source_stable":fingerprint==source_fingerprint(fingerprint),"population":{"vehicles":world.production.vehicles.size(),"people":world.people.size()},"archetypes":[car.archetype,target.archetype],"scenarios":reports,"collisions":collisions,"state":state,"debris_support":debris_support,"failures":failures,"scope":"Real rendered Main with live population; fixture positions two vehicles then normal physics creates impacts. Target is stopped traffic with route disabled. Benchmark uses fixed review camera; capture camera follows pair midpoint. This is not autonomous city driving or whole-fleet coverage."}
	result["capture_frames"]=capture_frames
	result["display_start"]=display_at_start
	result["display_end"]=display_configuration()
	result["ready_msec"]=ready_msec
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	if not saved_path.is_empty(): print("BREAKAWAY_RELOAD_PATH ",saved_path)
	print("BREAKAWAY_MAIN_REPORT ",output," failures=",failures)
	await finish_run(0 if failures.is_empty() else 1)

func FLEET_CAPTURE(vehicle: CharacterBody3D) -> Dictionary:
	return preload("res://runtime/FleetState.gd").capture(vehicle,"harbor")

func display_configuration() -> Dictionary:
	var screen:=DisplayServer.window_get_current_screen()
	return {"window_size":str(DisplayServer.window_get_size()),"window_mode":DisplayServer.window_get_mode(),"window_position":str(DisplayServer.window_get_position()),"screen_index":screen,"screen_size":str(DisplayServer.screen_get_size(screen)),"screen_dpi":DisplayServer.screen_get_dpi(screen),"screen_scale":DisplayServer.screen_get_scale(screen),"root_size":str(root.size),"viewport_visible_size":str(root.get_visible_rect().size),"viewport_texture_size":str(root.get_texture().get_size()),"content_scale_size":str(root.content_scale_size),"content_scale_factor":root.content_scale_factor,"content_scale_mode":root.content_scale_mode,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}

func fingerprint_directory(directory: String) -> void:
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".gd") or filename.ends_with(".cs"):
			var path:=directory.path_join(filename)
			fingerprint[path]=FileAccess.get_sha256(path)
	for child in DirAccess.get_directories_at(directory):
		fingerprint_directory(directory.path_join(child))

func save_damaged_vehicle() -> void:
	car.finish_doors()
	var record:=FLEET_CAPTURE(car)
	record.was_driven=false
	var snapshot: Dictionary=world.session.state.snapshot()
	snapshot.world.vehicles=[record]
	var state:=preload("res://runtime/GameState.gd").new()
	check(state.restore_snapshot(snapshot),"full GameState accepts missing panels")
	var store:=preload("res://runtime/SaveStore.gd").new()
	store.path=output.path_join("damaged-save.json")
	check(store.save(state)==OK,"real SaveStore writes isolated damaged vehicle")
	saved_path=store.path

func verify_production_reload(path: String) -> void:
	var data:=preload("res://runtime/SaveStore.gd").read_valid(path)
	var expected: Dictionary=data.get("world",{}).get("vehicles",[{}])[0].get("breakaway_parts",{})
	var actual: Dictionary=car.breakaway_parts.snapshot() if car.breakaway_parts!=null else {}
	check(not data.is_empty(),"reloaded checkpoint validates")
	check(car.breakaway_parts!=null and car.breakaway_parts.detached_count()>=2,"ProductionWorld restores absent hood and bumper")
	check(not car.body_dents.dents.is_empty(),"ProductionWorld restores dented body")
	if car.breakaway_parts!=null:
		check(same_panel_state(actual,expected),"production restore matches saved panel state")
		check(car.breakaway_parts.spawned_count==0,"production load does not replay detach effects")
		car.finish_doors()
		car.animate_driver_door(-1,true,.1)
		await create_timer(.2).timeout
		check(car.breakaway_parts.detached_count()>=2,"boarding preparation after reload preserves missing panels")
	world.camera.locked=true
	world.camera.set_process(false)
	world.camera.set_physics_process(false)
	world.camera.size=8
	world.camera.global_position=car.global_position+car.global_basis*Vector3(5,6,-7)
	world.camera.look_at(car.global_position+Vector3.UP*.6)
	world.camera.current=true
	world.camera.reset_physics_interpolation()
	await process_frame
	await process_frame
	await shot("production-restored")
	car.repair()
	check(car.breakaway_parts.detached_count()==0 and car.body_dents.dents.is_empty(),"repair after production reload restores panels and shell")
	await shot("production-repaired")
	FileAccess.open(output.path_join("reload-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"path":path,"native_csharp":world.dispatch.router._native!=null,"engine":Engine.get_version_info(),"archetype":car.archetype,"actual_before_repair":actual,"saved_state":expected,"version_types":{"actual":typeof(actual.get("version")),"saved":typeof(expected.get("version"))},"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"source_stable":fingerprint==source_fingerprint(fingerprint)},"\t"))
	print("BREAKAWAY_MAIN_RELOAD ",output," failures=",failures)
	await finish_run(0 if failures.is_empty() else 1)

func same_panel_state(actual: Dictionary, expected: Dictionary) -> bool:
	if float(actual.get("version",0))!=float(expected.get("version",0)): return false
	var actual_parts: Dictionary=actual.get("parts",{})
	var expected_parts: Dictionary=expected.get("parts",{})
	if actual_parts.size()!=expected_parts.size(): return false
	for id in actual_parts:
		if not expected_parts.has(id) or float(actual_parts[id])!=float(expected_parts[id]): return false
	return true

func timed_window(label: String, impacts: bool) -> void:
	samples.clear(); cpu.clear(); physics.clear()
	previous=Time.get_ticks_usec(); sampling=true
	var began:=Time.get_ticks_msec()
	var next:=began+1000
	var count:=0
	while Time.get_ticks_msec()-began<30000:
		await process_frame
		if impacts and Time.get_ticks_msec()>=next:
			next+=5000
			# Duas colisões completam um ciclo de dano: primeiro os para-choques, depois o capô.
			if count%2==0:
				car.repair(); target.repair()
			await strike(count,false)
			count+=1
	sampling=false
	reports.append({"id":label,"start_msec":began,"summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_ms":cpu.duplicate(),"physics_ms":physics.duplicate(),"debris":get_nodes_in_group("vehicle_panel_debris").size(),"vehicles":world.production.vehicles.size(),"people":world.people.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	reports[-1].display=display_configuration()
	FileAccess.open(output.path_join("partial.json"),FileAccess.WRITE).store_string(JSON.stringify({"complete":false,"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"scenarios":reports,"collisions":collisions,"failures":failures},"\t"))
	await shot(label)

func strike(index: int, frames: bool) -> void:
	car.set_physics_process(false); target.set_physics_process(false)
	car.stop_boarding_motion(); target.stop_boarding_motion()
	car.set_external_driver(false)
	target.traffic=true
	for vehicle: CharacterBody3D in [car,target]:
		vehicle.steer_input=0.0
		vehicle.steering=0.0
		if vehicle.has_meta("crash_was_traffic"): vehicle.remove_meta("crash_was_traffic")
	car.place(anchor,yaw)
	target.place(anchor-car.global_basis.z*11,yaw)
	target.speed=0; target.horizontal_velocity=Vector3.ZERO
	car.set_physics_process(true); target.set_physics_process(true)
	# Assenta as fixtures teleportadas na rua real antes de uma nova tentativa física.
	for frame in 12: await physics_frame
	var start_pose:={"car":str(car.global_position),"traffic":str(target.global_position),"car_grounded":car.is_on_floor(),"traffic_grounded":target.is_on_floor()}
	check(car.is_on_floor() and target.is_on_floor(),"trial starts on real floor "+str(index))
	car.set_external_driver(true)
	car.brake_input=false
	car.throttle_input=0
	car.speed=32
	car.horizontal_velocity=-car.global_basis.z*32
	var old_health: float=target.health
	car.set_physics_process(true); target.set_physics_process(true)
	var began:=Time.get_ticks_msec()
	var last_shot:=began-100
	var shot_index:=0
	var contact:=false
	var contact_msec: int=-1
	var max_car_y: float=car.global_position.y
	var max_target_y: float=target.global_position.y
	var hood_flight: Array[Dictionary]=[]
	while Time.get_ticks_msec()-began<1800:
		await physics_frame
		max_car_y=maxf(max_car_y,car.global_position.y)
		max_target_y=maxf(max_target_y,target.global_position.y)
		if not contact and target.health<old_health:
			contact=true
			contact_msec=Time.get_ticks_msec()
		if frames and index==1:
			for fragment: RigidBody3D in get_nodes_in_group("vehicle_panel_debris"):
				if fragment.panel_id=="hood" and fragment.source_vehicle_id==car.vehicle_id:
					var panel_bounds: AABB=fragment.panel_mesh.mesh.get_aabb()
					var box_size:=Vector3.ZERO
					for child in fragment.get_children():
						if child is CollisionShape3D and child.shape is BoxShape3D: box_size=child.shape.size
					hood_flight.append({"msec":Time.get_ticks_msec(),"physics_frame":Engine.get_physics_frames(),"panel_transform":pose_record(fragment.panel_mesh.global_transform),"body_transform":pose_record(fragment.global_transform),"car_transform":pose_record(car.global_transform),"traffic_transform":pose_record(target.global_transform),"car_hvel":vector_record(car.horizontal_velocity),"car_velocity":vector_record(car.velocity),"traffic_hvel":vector_record(target.horizontal_velocity),"traffic_velocity":vector_record(target.velocity),"linear_velocity":vector_record(fragment.linear_velocity),"angular_velocity":vector_record(fragment.angular_velocity),"mesh_aabb":{"position":vector_record(panel_bounds.position),"size":vector_record(panel_bounds.size)},"body_box_size":vector_record(box_size)})
					hood_flight[-1].car_local_box_corners=panel_corners_in_vehicle(fragment.panel_mesh,car)
					hood_flight[-1].traffic_local_box_corners=panel_corners_in_vehicle(fragment.panel_mesh,target)
		if frames and Time.get_ticks_msec()-last_shot>=(40 if index==1 else 100):
			last_shot=Time.get_ticks_msec()
			frame_current_pair()
			if index==1: await buffered_shot("impact-%02d-%03d" % [index,shot_index])
			else: await shot("impact-%02d-%03d" % [index,shot_index])
			shot_index+=1
	car.set_external_driver(false)
	car.set_physics_process(false); target.set_physics_process(false)
	car.speed=0; car.horizontal_velocity=Vector3.ZERO
	target.speed=0; target.horizontal_velocity=Vector3.ZERO
	collisions.append({"index":index,"contact":contact,"start_msec":began,"contact_msec":contact_msec,"end_msec":Time.get_ticks_msec(),"car_health":car.health,"traffic_health":target.health,"car_dents":car.body_dents.dents.size(),"traffic_dents":target.body_dents.dents.size(),"car_parts":car.breakaway_parts.snapshot() if car.get("breakaway_parts")!=null else {},"traffic_parts":target.breakaway_parts.snapshot() if target.get("breakaway_parts")!=null else {}})
	collisions[-1].start_pose=start_pose
	collisions[-1].end_pose={"car":str(car.global_position),"traffic":str(target.global_position)}
	collisions[-1].max_height={"car":max_car_y,"traffic":max_target_y}
	if not hood_flight.is_empty(): collisions[-1].hood_flight=hood_flight
	check(contact,"physical traffic contact "+str(index))
	check(max_car_y<anchor.y+.5 and max_target_y<anchor.y+.5,"vehicles remain at road height after impact "+str(index))
	if frames and index==1:
		for entry in buffered_images:
			entry.image.save_png(output.path_join(entry.file))
		buffered_images.clear()

func frame_pair() -> void:
	var center:=anchor-car.global_basis.z*5
	world.camera.size=15
	world.camera.global_position=center+Vector3(10,11,-12)
	world.camera.look_at(center+Vector3.UP*.5)
	world.camera.current=true
	world.camera.reset_physics_interpolation()

func frame_current_pair() -> void:
	var center: Vector3=(car.global_position+target.global_position)*.5
	world.camera.size=maxf(12.0,car.global_position.distance_to(target.global_position)*1.5+5.0)
	world.camera.global_position=center+Vector3(8,10,-11)
	world.camera.look_at(center+Vector3.UP*.5)
	world.camera.reset_physics_interpolation()

func inspect_debris_support() -> void:
	check(not get_nodes_in_group("vehicle_panel_debris").is_empty() or legacy,"physical collision leaves visible fragments before expiry")
	for body: RigidBody3D in get_nodes_in_group("vehicle_panel_debris"):
		var query:=PhysicsRayQueryParameters3D.create(body.global_position+Vector3.UP*2,body.global_position-Vector3.UP*10,1)
		var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
		var lowest:=INF
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				var half: Vector3=child.shape.size*.5
				for x in [-1,1]:
					for y in [-1,1]:
						for z in [-1,1]: lowest=minf(lowest,(child.global_transform*Vector3(half.x*x,half.y*y,half.z*z)).y)
		var gap: float=lowest-hit.position.y if not hit.is_empty() else INF
		debris_support.append({"id":body.panel_id,"position":str(body.global_position),"speed":body.linear_velocity.length(),"sleeping":body.sleeping,"ground_found":not hit.is_empty(),"lowest_gap_m":gap if is_finite(gap) else null})
		check(not hit.is_empty() and gap>-.15,"detached "+body.panel_id+" remains above real floor")
		check(gap<.20 and body.linear_velocity.length()<.60,"detached "+body.panel_id+" settles on real floor before expiry")

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	capture_frames.append({"file":label+".png","msec":Time.get_ticks_msec()})
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func buffered_shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	capture_frames.append({"file":label+".png","msec":Time.get_ticks_msec(),"buffered":true})
	buffered_images.append({"file":label+".png","image":root.get_texture().get_image()})

func vector_record(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func pose_record(value: Transform3D) -> Dictionary:
	return {"origin":vector_record(value.origin),"x":vector_record(value.basis.x),"y":vector_record(value.basis.y),"z":vector_record(value.basis.z)}

func panel_corners_in_vehicle(panel: MeshInstance3D, vehicle: Node3D) -> Array:
	var bounds:=panel.mesh.get_aabb()
	var relative:=vehicle.global_transform.affine_inverse()*panel.global_transform
	var result: Array=[]
	for x in [0,1]:
		for y in [0,1]:
			for z in [0,1]: result.append(vector_record(relative*(bounds.position+bounds.size*Vector3(x,y,z))))
	return result

func closeup(label: String, vehicle: CharacterBody3D) -> void:
	world.camera.size=8
	world.camera.global_position=vehicle.global_position+vehicle.global_basis*Vector3(3,9,-5)
	world.camera.look_at(vehicle.global_position+Vector3.UP*.6)
	world.camera.reset_physics_interpolation()
	await process_frame
	await process_frame
	await shot(label)

func finish_run(status: int) -> void:
	var before:=get_nodes_in_group("vehicle_panel_debris").size()
	var exiting: Node=world
	current_scene=null
	world=null
	car=null
	target=null
	exiting.queue_free()
	await exiting.tree_exited
	for frame in 4: await process_frame
	await create_timer(.1).timeout
	var after:=get_nodes_in_group("vehicle_panel_debris").size()
	FileAccess.open(output.path_join("shutdown-cleanup.json"),FileAccess.WRITE).store_string(JSON.stringify({"world_removed":not is_instance_valid(exiting),"debris_before":before,"debris_after":after},"\t"))
	print("BREAKAWAY_CLEANUP debris_before=",before," debris_after=",after)
	quit(status)
