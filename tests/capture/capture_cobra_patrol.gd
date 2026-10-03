extends SceneTree
var world
var failures: Array[String] = []
var folder := "D:/geteco/artifacts/cobra-patrol-1002"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func shot(_origin,_direction,source) -> void:
	if source.is_in_group("iron_cobras"): foot_shots+=1
var foot_shots:=0
func photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(150).timeout.connect(func(): quit(3))
	seed(77001700)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	for i in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather._update()
	# Long-lived target for separate retaliation checks; no invulnerability or disabled AI.
	world.gameplay.health=5000
	world.player.teleport(Vector3(450,.1,98))
	await create_timer(7).timeout
	await photo("uniform")
	var locals=get_nodes_in_group("iron_cobras")
	check(locals.size()>=3,"Neighborhood guards still present")
	for actor in locals:
		check(actor.visual.find_children("CobraInsignia*","MeshInstance3D",true,false).size()==2,"Shirt has front and back Cobra insignia")
	check(get_nodes_in_group("cobra_patrol").size()>0,"Real ambient spawner supplies Cobra cars")
	var patrol
	for candidate in get_nodes_in_group("cobra_patrol"):
		if candidate.car.is_visible_in_tree() and candidate.car.health>0: patrol=candidate; break
	if patrol==null: check(false,"Visible patrol exists"); quit(1); return
	var car=patrol.car
	check_roof(car,"before boarding")
	if "--pursuit-only" in OS.get_cmdline_user_args():
		await pursuit_case(patrol)
		print("COBRA_PURSUIT failures=",failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	if "--collision-only" in OS.get_cmdline_user_args():
		await collision_case(patrol)
		print("COBRA_COLLISION failures=",failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	world.player.teleport(car.global_position+car.global_basis.x*7+Vector3.UP*.2)
	await create_timer(2).timeout
	world.camera.target=car
	await photo("car")
	var start: Vector3=car.global_position
	await create_timer(3).timeout
	check(car.global_position.distance_to(start)>1,"Unprovoked Cobra car drives the real road")
	check(not patrol.hostile and patrol.shots==0,"Passing player does not trigger gunfire")
	car.receive_damage(1,null)
	check(not patrol.hostile,"Unattributed damage does not blame player")
	# Actual boarding flow; fixture moves the player to an existing car's door.
	car.speed=0
	var door: Vector3=car.driver_door_anchor(1)
	world.player.teleport(door+car.global_basis.x*.25+Vector3.UP*.12)
	await physics_frame
	check(world.driving.interact(),"Door interaction starts gang-car theft")
	await create_timer(2.5).timeout
	check(patrol.stolen and patrol.hostile,"Theft provokes the gang through real boarding")
	check(patrol.crew.size()==2,"Both gang occupants leave; no generic civilian replacement")
	check(not car.traffic and not car.external_input,"Stolen vehicle belongs to player")
	check(world.driving.occupied and world.driving.car==car,"Player finishes boarding Cobra car")
	check_roof(car,"occupied")
	await photo("occupied-roof")
	world.gameplay.npc_gunfire.connect(shot)
	if world.driving.occupied: world.driving.leave()
	for i in 360:
		await physics_frame
		if not world.driving.is_body_transition_active() and not world.driving.occupied: break
	print("EXIT occupied=",world.driving.occupied," locked=",world.player.input_locked," transition=",world.driving.is_body_transition_active())
	check_roof(car,"after exit")
	world.gameplay.health=5000
	if not patrol.crew.is_empty():
		var guard=patrol.crew[0]
		var clear_target:=Vector3.INF
		for index in 16:
			var angle:=index*TAU/16.0
			var candidate: Vector3=guard.global_position+Vector3(cos(angle),0,sin(angle))*6+Vector3.UP*.05
			var ray:=PhysicsRayQueryParameters3D.create(guard.global_position+Vector3.UP*1.4,candidate+Vector3.UP,7,[guard.get_rid(),world.player.get_rid()])
			if world.session.position_clear(candidate) and world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): clear_target=candidate; break
		check(clear_target.is_finite(),"Retaliation fixture has unobstructed line of sight")
		if clear_target.is_finite(): world.player.teleport(clear_target)
		await create_timer(3).timeout
		print("GUNSTATE engaged=",guard.engaged," sees=",guard.sees_target," locked=",world.player.input_locked," health=",world.gameplay.health," distance=",guard.global_position.distance_to(world.player.global_position))
		check(foot_shots>0,"Disembarked Cobra actually fires at player")
	await photo("retaliation")
	# A second existing patrol exercises attributed collision and pursuit driver.
	var pursuer
	for other in get_nodes_in_group("cobra_patrol"):
		if other!=patrol and not other.stolen and other.car.health>0: pursuer=other; break
	if pursuer!=null:
		world.gameplay.health=5000
		var route: Curve3D=pursuer.car.route
		var offset: float=route.get_closest_offset(pursuer.car.global_position)
		var road_target: Vector3=route.sample_baked(fposmod(offset+35,route.get_baked_length()),true)
		world.player.teleport(road_target+Vector3.UP*.1)
		await create_timer(1).timeout
		pursuer.car.receive_damage(2,world.player)
		check(pursuer.hostile and pursuer.pilot!=null,"Player damage activates vehicle pursuit")
		start=pursuer.car.global_position
		await create_timer(3).timeout
		if is_instance_valid(pursuer): print("CHASE moved=",pursuer.car.global_position.distance_to(start)," speed=",pursuer.car.speed," deployed=",pursuer.deployed," pilot=",pursuer.pilot," route=",pursuer.pilot.route if pursuer.pilot else null," blocked=",pursuer.pilot.blocked_ahead if pursuer.pilot else false)
		check(is_instance_valid(pursuer) and pursuer.car.global_position.distance_to(start)>1,"Pursuit moves with vehicle physics")
	else: check(false,"Second patrol available for pursuit")
	world.player.teleport(Vector3(350,.1,240))
	await create_timer(14).timeout
	check(not is_instance_valid(pursuer) or not pursuer.hostile,"Escape ends vehicle pursuit")
	print("COBRA_PATROL failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func check_roof(car, label: String) -> void:
	# Intersect actual rendered triangles above the cabin, not a roof node name.
	var highest := -INF
	var roof_material: Material
	for part in car.visual.find_children("*","MeshInstance3D",true,false):
		if not part.is_visible_in_tree() or part.mesh==null: continue
		var ray_from: Vector3 = part.to_local(car.to_global(Vector3(0,3,.2)))
		var ray_to: Vector3 = part.to_local(car.to_global(Vector3(0,-1,.2)))
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for triangle in range(0,count,3):
				var a: int = indices[triangle] if not indices.is_empty() else triangle
				var b: int = indices[triangle+1] if not indices.is_empty() else triangle+1
				var c: int = indices[triangle+2] if not indices.is_empty() else triangle+2
				var hit = Geometry3D.segment_intersects_triangle(ray_from,ray_to,vertices[a],vertices[b],vertices[c])
				if hit is Vector3:
					var height: float = car.to_local(part.to_global(hit)).y
					if height>highest:
						highest=height
						roof_material=part.get_active_material(surface)
	check(highest>1.1 and roof_material is BaseMaterial3D and roof_material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and roof_material.albedo_color.a>.99,"Painted opaque cabin roof "+label)

func collision_case(patrol) -> void:
	var target=patrol.car
	world.player.teleport(target.global_position+target.global_basis.x*5+Vector3.UP*.1)
	await create_timer(2).timeout
	target.speed=0
	target.set_physics_process(false)
	var point: Vector3=target.global_position+target.global_basis.z*(target.half_length+5)
	var ram=world.production.spawn_vehicle("union_sedan",point+Vector3.UP*.05,target.rotation.y)
	check(ram!=null,"Rear collision fixture fits existing road")
	if ram==null: target.set_physics_process(true); return
	world.player.teleport(ram.driver_door_anchor(1)+ram.global_basis.x*.2+Vector3.UP*.1)
	await physics_frame
	check(world.driving.interact(),"Player boards collision vehicle through door")
	for i in 360:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	check(world.driving.occupied and world.driving.car==ram,"Collision source is occupied player car")
	var initial: float=target.health
	ram.external_input=true
	ram.controlled=true
	ram.input_locked=false
	ram.brake_input=false
	ram.throttle_input=1
	ram.speed=8
	for i in 180:
		await physics_frame
		if target.health<initial: break
	check(target.health<initial,"Real physical car collision damages Cobra vehicle")
	check(patrol.hostile,"Collision attributed to player provokes Cobras")
	ram.throttle_input=0
	ram.brake_input=true
	target.set_physics_process(true)
	await create_timer(3).timeout
	check(patrol.shots>0,"Moving patrol fires from car at occupied player vehicle")
	await photo("collision_retaliation")
	var saved: Dictionary=preload("res://runtime/FleetState.gd").capture(target,"harbor")
	check(preload("res://runtime/FleetState.gd").validate(saved) and str(saved.vehicle_id).begins_with("cobra_patrol_"),"Vehicle snapshot retains gang identity")
	world.gameplay.damage_environment(10000)
	await create_timer(.5).timeout
	check(not is_instance_valid(patrol) or not patrol.hostile,"Player death stops gang retaliation")

func pursuit_case(patrol) -> void:
	var car=patrol.car
	var route: Curve3D=car.route
	var offset: float=route.get_closest_offset(car.global_position)
	var target: Vector3=route.sample_baked(fposmod(offset+35,route.get_baked_length()),true)
	world.player.teleport(target+Vector3.UP*.1)
	await create_timer(1).timeout
	var start: Vector3=car.global_position
	car.receive_damage(2,world.player)
	check(patrol.hostile and patrol.pilot!=null,"Aggression starts road pursuit")
	for step in 10:
		await create_timer(1).timeout
		if not is_instance_valid(patrol): break
		print("PURSUIT ",step," moved=",car.global_position.distance_to(start)," gap=",car.global_position.distance_to(target)," speed=",car.speed," deployed=",patrol.deployed," route=",patrol.pilot.route if patrol.pilot else null," blocked=",patrol.pilot.blocked_ahead if patrol.pilot else false)
	check(is_instance_valid(patrol) and car.global_position.distance_to(start)>3,"Pursuer covers road distance with physical driving")
	if is_instance_valid(patrol): await photo("pursuit")
	world.player.teleport(Vector3(350,.1,240))
	await create_timer(14).timeout
	check(not is_instance_valid(patrol) or not patrol.hostile,"Escape ends pursuit without replacement attackers")
