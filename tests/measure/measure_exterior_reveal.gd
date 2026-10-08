extends "res://tests/measure/measure_railway.gd"
## Isolated Main scene. Visual comparison by default; --reveal-benchmark opts
## into 30s A/B samples and must be launched without other rendered sessions.
var temporal_count := 0
var temporal_trace: Array = []
var temporal_errors: Array[String] = []
var _rail_point := Vector3.ZERO

func capture(id: String) -> void:
	if id != "station": return
	world.camera.set_preview_view(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.heading = 0
	if "--reveal-building-only" in OS.get_cmdline_user_args():
		await stage_reveal(Vector3(109.375,.12,32.8875))
		await compare("building-foot")
		return
	for point in [Vector3(346,.12,-138),Vector3(318,.12,-138),Vector3(170,.12,12),Vector3(229,.12,12)]:
		if await stage_reveal(point) and world.camera._tunnel_blend < .001:
			_rail_point = point
			break
	if _rail_point == Vector3.ZERO: push_error("No supported outdoor rail viewpoint"); quit(1); return
	await compare("railway-foot")
	var buildings: Array = world.production.regions.harbor.buildings.duplicate()
	buildings.sort_custom(func(a,b): return a.position.distance_to(Vector3(100,0,60)) < b.position.distance_to(Vector3(100,0,60)))
	var chosen := false
	for building in buildings:
		if building.size.x < 8 or building.size.y < 8: continue
		var point: Vector3 = building.position + Vector3(0,.12,-building.size.y*.5-1.8)
		if point.distance_to(Vector3(100,0,60)) > 100: continue
		if not await stage_reveal(point): continue
		if not world.session.position_clear(world.player.position): continue
		report.building = {"id":building.id,"point":str(point)}
		chosen = true
		break
	if not chosen: push_error("No valid building approach"); quit(1); return
	await compare("building-foot")
	# Real boarding transfers the camera to the actual production car.
	var car = world.driving.car
	var road_point := _rail_point
	if not await stage_reveal(road_point): quit(1); return
	car.place(road_point,PI*.5)
	car.external_input = true
	car.throttle_input = 0
	car.brake_input = true
	world.player.teleport(car.driver_door_anchor(-1))
	for i in 4: await physics_frame
	if not world.driving._begin_entry(car,-1): push_error("Reveal car boarding refused"); quit(1); return
	for i in 600:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	if not world.driving.occupied: push_error("Reveal car not occupied"); quit(1); return
	await compare("railway-car")
	await temporal_review()
	report.temporal = {"frames":temporal_count,"trace":temporal_trace,"errors":temporal_errors}
	FileAccess.open(output.path_join("reveal-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("REVEAL_VISUAL_DONE ",output," frames=",temporal_count)

func stage_reveal(point: Vector3) -> bool:
	world.player.set_physics_process(false)
	world.player.teleport(point)
	world.production.regions.harbor.set_focus(point)
	world.production.regions.harbor.prepare_collision_at(point)
	world.session.railway_world.set_focus(point)
	for i in 900:
		await physics_frame
		if world.production.regions.harbor.pending.is_empty() and world.production.regions.harbor.build_jobs.is_empty(): break
	world.player.set_physics_process(true)
	world.camera.initialized = false
	await create_timer(2).timeout
	print("REVEAL_STAGE requested=",point," actual=",world.player.position," floor=",world.player.is_on_floor())
	return world.player.is_on_floor() and world.player.position.y > -1

func compare(label_id: String) -> void:
	for active in [false,true]:
		world.camera._exterior_reveal.enabled = active
		await create_timer(6).timeout
		var suffix := "after" if active else "before"
		await super.capture(label_id+"-"+suffix)
		print("REVEAL_STATE ",label_id," ",suffix," ",world.camera._exterior_reveal.debug_snapshot()," player=",world.player.position)
		if active and label_id == "building-foot": diagnose_blockers()
		if "--reveal-benchmark" in OS.get_cmdline_user_args(): await super.sample(label_id+"-"+suffix)

func diagnose_blockers() -> void:
	var start: Vector3 = world.player.global_position + Vector3.UP*.85
	var end: Vector3 = start + world.camera.global_basis.z*36
	for node in world.find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree(): continue
		var bounds: AABB = node.global_transform*node.get_aabb()
		if not bounds.intersects_segment(start,end): continue
		var sources: Array = []
		if world.camera._exterior_reveal._states.has(node.get_instance_id()):
			for saved in world.camera._exterior_reveal._states[node.get_instance_id()].saved: sources.append(saved.source)
		else: sources.append(node.material_override if node.material_override != null else node.get_active_material(0))
		for source in sources:
			print("REVEAL_BLOCKER ",node.get_path()," box=",bounds," source=",source," overlay=",node.material_overlay," captured=",world.camera._exterior_reveal._states.has(node.get_instance_id())," next=",source.next_pass if source != null else null," tri=",source.uv1_triplanar if source is StandardMaterial3D else false)

func temporal_review() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join("temporal")))
	var start := Time.get_ticks_usec()
	var car = world.driving.car
	while Time.get_ticks_usec()-start < 30000000:
		var seconds := (Time.get_ticks_usec()-start)/1000000.0
		# Bounded genuine steering/drive input under the viaduct, then stop and orbit.
		car.throttle_input = .3 if seconds < 7 else -.25 if seconds < 13 else 0
		car.brake_input = seconds >= 13
		if seconds > 16: world.camera.heading = (seconds-16)*.18
		if seconds > 23:
			world.session.weather.time_of_day = .9
			world.session.weather._update()
		await RenderingServer.frame_post_draw
		var stamp := Time.get_ticks_usec()
		root.get_texture().get_image().save_jpg(output.path_join("temporal/%05d.jpg"%temporal_count),.85)
		temporal_trace.append({"frame":temporal_count,"usec":stamp,"position":str(car.global_position),"reveal":world.camera._exterior_reveal.debug_snapshot()})
		temporal_count += 1
	car.throttle_input = 0
	car.brake_input = true
