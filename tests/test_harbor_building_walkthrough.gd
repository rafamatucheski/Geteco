extends SceneTree
## Main-scene coverage: physical thresholds, real-height floors, roof, receipts,
## return, and cold restore. Supports bounded inventory slices without skipping
## a failing case or substituting catalog assertions for walking.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const STORE = preload("res://runtime/SaveStore.gd")
var world
var checks := 0
var failures: Array[String] = []
var folder := ""
var save_path := ""
var rendered := false
var visited: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("BUILDING_WALK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func boot() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.player.speed = 5.0
	for frame in 4: await physics_frame

func walk(point: Vector3) -> bool:
	var end := Time.get_ticks_msec() + 9000
	while world.player.global_position.distance_to(point) > .23 and Time.get_ticks_msec() < end:
		var direction: Vector3 = point - world.player.global_position
		direction.y = 0
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	if world.player.global_position.distance_to(point) > .4:
		print("WALK_BLOCKED expected=",point," actual=",world.player.global_position," place=",world.session.state.place_id)
		for index in world.player.get_slide_collision_count():
			var collision = world.player.get_slide_collision(index)
			var collider = collision.get_collider()
			print("BLOCKING_BODY ",collider.get_path() if is_instance_valid(collider) else "freed"," at=",collision.get_position()," normal=",collision.get_normal())
	return world.player.global_position.distance_to(point) < .4

func photo(label: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func stairs_to(destination: int) -> bool:
	var room = world.session.room
	if not await world.session.interact(): return false
	if world.session.modal:
		var prefix := "Subir" if destination > room.floor_index else "Descer"
		var selected := false
		for button in world.session.column.get_children():
			if button is Button and button.text.begins_with(prefix):
				button.pressed.emit()
				selected = true
				break
		if not selected: return false
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if room.floor_index == destination and not world.session.is_transition_blocked(): return true
	return false

func roof_walk_to(roof: Node3D, local_goal: Vector3) -> bool:
	# Original chimneys and roof units stay solid. Verify an actual route around
	# them instead of assuming every roof has an unobstructed straight aisle.
	var goal: Vector3 = roof.to_global(local_goal)
	var start: Vector3 = world.player.global_position
	if not world.session.position_clear(goal): return false
	var from: Transform3D = world.player.global_transform
	if not world.player.test_move(from,Vector3(goal.x-start.x,0,goal.z-start.z)): return await walk(goal)
	var astar := AStar3D.new()
	var cells := {}
	var size: Vector2 = roof.definition.size
	var columns := maxi(2,ceili((size.x-1.4)/.65))
	var rows := maxi(2,ceili((size.y-1.4)/.65))
	for x in columns+1:
		for z in rows+1:
			var point := roof.to_global(Vector3(lerpf(-size.x*.5+.70,size.x*.5-.70,float(x)/columns),.04,lerpf(-size.y*.5+.70,size.y*.5-.70,float(z)/rows)))
			if not world.session.position_clear(point): continue
			var id: int = astar.get_available_point_id()
			astar.add_point(id,point)
			cells[Vector2i(x,z)] = id
	for cell: Vector2i in cells:
		for step: Vector2i in [Vector2i(1,0),Vector2i(0,1)]:
			if not cells.has(cell+step): continue
			var first: int = cells[cell]
			var second: int = cells[cell+step]
			from.origin = astar.get_point_position(first)
			if not world.player.test_move(from,astar.get_point_position(second)-from.origin): astar.connect_points(first,second)
	var start_id: int = astar.get_available_point_id()
	astar.add_point(start_id,start)
	var goal_id: int = astar.get_available_point_id()
	astar.add_point(goal_id,goal)
	for endpoint in [start_id,goal_id]:
		var at: Vector3 = astar.get_point_position(endpoint)
		for other: int in cells.values():
			var point: Vector3 = astar.get_point_position(other)
			if Vector2(at.x-point.x,at.z-point.z).length()>1.35: continue
			from.origin = Vector3(at.x,point.y,at.z)
			if not world.player.test_move(from,Vector3(point.x-at.x,0,point.z-at.z)): astar.connect_points(endpoint,other)
	var path := astar.get_point_path(start_id,goal_id)
	if path.is_empty(): print("ROOF_ROUTE_UNREACHABLE ",roof.definition.id," goal=",goal); return false
	for index in range(1,path.size()):
		if not await walk(path[index]): return false
	return true

func run() -> void:
	create_timer(1200).timeout.connect(func(): push_error("BUILDING_WALK timeout"); finish(3))
	rendered = DisplayServer.get_name() != "headless"
	seed(100726)
	folder = FIXTURE.output_dir("harbor-building-walkthrough")
	var start := 0
	var count := 999
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start="): start = arg.trim_prefix("--start=").to_int()
		if arg.begins_with("--count="): count = arg.trim_prefix("--count=").to_int()
		if arg.begins_with("--building="): only = arg.trim_prefix("--building=")
	var selected: Array[Dictionary] = CATALOG.definitions()
	if not only.is_empty(): selected = selected.filter(func(row): return row.id in only.split(","))
	else: selected = selected.slice(start, mini(selected.size(),start+count))
	if selected.is_empty(): check(false,"nonempty selected inventory"); finish(); return
	var snapshot := FIXTURE.full_snapshot(selected[0].return_position + Vector3.UP * .08, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot()
	check(world.production.loaded_save and not world.production.save_invalid,"isolated save loaded")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"C# route runtime active")
	for definition in selected:
		var label: String = definition.id
		if definition.get("port_building",false):
			check(world.session.urban_operations.security.restore_snapshot({"version":1,"authorized_entry":false,"authorized_visit":true,"exiting_port":false}),label+" authorized port visit fixture")
		world.production.region.set_focus(definition.entry_position)
		world.player.teleport(definition.return_position + Vector3.UP * .08)
		var ready_end := Time.get_ticks_msec()+15000
		var runtime = world.session.building_entrance
		while (not is_instance_valid(runtime.staged) or runtime.staged.definition.id != label or runtime.preparing) and Time.get_ticks_msec()<ready_end: await physics_frame
		if not check(is_instance_valid(runtime.staged) and runtime.staged.definition.id == label and not runtime.preparing,label+" prepared at street"):
			finish(); return
		check(world.session.position_clear(world.player.global_position),label+" supported exterior body")
		if label in ["harbor_building_garden_flats","harbor_building_service_lodge"]:
			await create_timer(.7).timeout
			check(world.camera._building_approach_blend>.95,label+" entrance approach raises camera")
		await photo(label+"-exterior")
		if label in ["harbor_building_new_1790426066_503_97028106","harbor_building_torque_store"]:
			# These authored doors face away from the default street view. Use
			# the existing orbit to inspect their actual front-facing approach.
			var saved_orbit: float = world.camera.heading
			var view_offset: Vector3 = world.camera._exterior_view_offset()
			world.camera.heading = float(definition.exterior_rotation)-atan2(view_offset.x,view_offset.z)
			world.camera.initialized = false
			world.camera._process(0)
			await photo(label+"-exterior-door-orbit")
			world.camera.heading = saved_orbit
			world.camera.initialized = false
			world.camera._process(0)
		if label in ["harbor_building_garden_flats","harbor_building_service_lodge","harbor_building_torque_store","harbor_building_cold_storage","harbor_building_bridge_court_west","harbor_building_bridge_court_east"]:
			var previous_heading: float = world.camera.heading
			for turn in [-2,-1,1,2]:
				world.camera.heading = previous_heading+float(turn)*PI*.25
				world.camera.initialized = false
				world.camera._process(0)
				await photo(label+"-exterior-orbit-"+str(turn))
			world.camera.heading = previous_heading
			world.camera.initialized = false
			world.camera._process(0)
		check(world.session.nearest().get("id","") != "enter",label+" no door interaction")
		var room = runtime.staged
		if not check(await walk(room.spawn_position+Vector3.UP*.04),label+" walk across door"):
			finish(); return
		for frame in 5: await physics_frame
		if not check(world.session.state.place_id == label and world.session.room == room,label+" continuous admission"):
			finish(); return
		check(room.global_position.distance_to(definition.exterior_position)<.01,label+" room at actual facade")
		check(not world.player.input_locked and not world.session.marker.visible,label+" control and no orange marker")
		var collected_id := ""
		var collected_amount := 0
		for index in range(int(definition.floor_count)+1):
			if index > 0:
				world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
				if not check(await stairs_to(index),label+" stairs interaction reaches level "+str(index)):
					finish(); return
			check(world.session.position_clear(world.player.global_position),label+" admitted body and floor "+str(index))
			check(absf(world.player.global_position.y-definition.exterior_position.y-room.floor_height(index))<.35,label+" physical elevation "+str(index))
			if label == "harbor_building_truckers_station_store":
				var village = world.session.urban_operations.village
				check(village.is_visible_in_tree() and village.homes.is_visible_in_tree(),label+" village remains visible level "+str(index))
				check(village.solids.all(func(body): return is_instance_valid(body) and body.collision_layer==1),label+" village retains physical solids level "+str(index))
				check(village.homes.current_home<0 and root.get_camera_3d()==world.camera,label+" correct camera owner level "+str(index))
				var cars: Array = world.session.urban_operations.village_fleet.cars.values()
				check(cars.any(func(car): return is_instance_valid(car) and car.is_visible_in_tree() and car.collision_layer==4),label+" parked fleet remains visible and solid level "+str(index))
			if definition.get("port_building",false):
				var urban = world.session.urban_operations
				check(urban.cargo_handling.depot.is_visible_in_tree() and urban.cargo_handling.outskirts.is_visible_in_tree(),label+" surrounding port remains visible level "+str(index))
				check(urban.cargo_handling.depot.solids.all(func(body): return body.collision_layer==1),label+" company retains physical solids level "+str(index))
				var quays := Vector3(4885.0/16.0,0,3400.0/16.0)
				if world.player.global_position.distance_to(quays)<=urban.cargo_handling.ACTIVE_DISTANCE:
					# Residency scans run every .25s. A new landing can cross their
					# radius just after a scan and the stairs fade lasts only .20s.
					var cargo_deadline := Time.get_ticks_msec()+600
					while not urban.cargo_handling.active and Time.get_ticks_msec()<cargo_deadline: await physics_frame
					check(urban.cargo_handling.active,label+" nearby cargo activity continues level "+str(index))
				var launches: Vector3 = (urban.port.BERTHS[0]+urban.port.BERTHS[1])*.5
				if world.player.global_position.distance_to(launches)<=urban.port.ACTIVE_DISTANCE:
					var launch_deadline := Time.get_ticks_msec()+600
					while not urban.port.active and Time.get_ticks_msec()<launch_deadline: await physics_frame
					check(urban.port.active and urban.port.boats.any(func(boat): return is_instance_valid(boat.worker)),label+" nearby dock workers continue level "+str(index))
			if index == 0:
				check(await walk(room.to_global(Vector3(definition.entrance_local.x,.04,1.45))),label+" entry aisle")
				check(await walk(room.to_global(Vector3(0,.04,1.45))),label+" corridor")
				check(await walk(room.to_global(room.stair_point())+Vector3.UP*.04),label+" stair approach")
			if index == int(definition.floor_count):
				var roof = room.floor_room
				var cache_point: Vector3 = roof.to_local(room.reward_points[0].position)
				check(await roof_walk_to(roof,cache_point+Vector3.UP*.04),label+" physical route to roof cache")
				check(await roof_walk_to(roof,roof.jump_point+Vector3.UP*.04),label+" physical route to roof jump gate")
			for point in room.reward_points:
				check(world.session.position_clear(point.position+Vector3.UP*.04),label+" reward accessible "+str(point.reward.id))
				if collected_id.is_empty() and point.reward.kind == "cash" and not point.reward.get("locked",false):
					var balance_before: int = world.session.state.economy.balance
					var receipt_before: bool = world.session.state.world_state.rewards.has(point.reward.id)
					var receipts_before: Dictionary = world.session.state.economy.snapshot().transactions
					world.player.teleport(point.position+Vector3.UP*.04)
					world.session._collect_reward(room)
					collected_id = str(point.reward.id)
					collected_amount = int(point.reward.amount)
					check(world.session.state.world_state.rewards.has(collected_id),label+" cash receipt")
					var receipts_after: Dictionary = world.session.state.economy.snapshot().transactions
					var extra_achievements := 0
					for receipt_id in receipts_after:
						if str(receipt_id).begins_with("reward:achievement:") and not receipts_before.has(receipt_id): extra_achievements += int(receipts_after[receipt_id].amount)
					check(world.session.state.economy.balance==balance_before+(0 if receipt_before else collected_amount)+extra_achievements,label+" exact cash plus recorded achievements")
					var balance_after: int = world.session.state.economy.balance
					world.session._collect_reward(room)
					check(world.session.state.economy.balance==balance_after,label+" no duplicate cash")
			await photo(label+"-floor-"+str(index))
		check(room.is_rooftop() and not world.camera.locked,label+" rooftop exterior camera")
		check(not world.camera.has_meta("harbor_building_approach") and is_zero_approx(world.camera._building_approach_blend),label+" rooftop restores exterior pitch")
		check(not world.session.building_entrance.sightline.debug_snapshot().active,label+" railway fully restored on roof")
		check(not world.session.weather._inside_shelter(),label+" rooftop exposed to weather")
		var did_save: bool = world.session.save_game()
		if not did_save: print("SAVE_BLOCK_REASON ",world.session.save_block_reason()," error=",world.session.last_save_error)
		check(did_save,label+" rooftop save")
		var saved := STORE.read_valid(save_path)
		check(not saved.is_empty() and saved.get("place_id","") == label and saved.get("world",{}).get("harbor_building_floors",{}).get(label,-1) == room.floor_index,label+" written saved place, receipts and floor")
		visited.append({"id":label,"floors":definition.floor_count,"roof_height":definition.roof_height})
		if visited.size() == 1 or label == "harbor_building_truckers_station_store":
			world.free()
			await process_frame
			await boot()
			room = world.session.room
			if not check(is_instance_valid(room) and world.session.state.place_id==label and room.is_rooftop(),label+" cold roof restore"):
				finish(); return
			check(world.session.position_clear(world.player.global_position),label+" restored roof body support")
			if label == "harbor_building_truckers_station_store":
				check(world.session.urban_operations.village.is_visible_in_tree(),label+" village visible after cold rooftop restore")
				await photo(label+"-cold-roof")
		for index in range(int(definition.floor_count)-1,-1,-1):
			world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
			if not check(await stairs_to(index),label+" descend through interaction "+str(index)):
				finish(); return
		world.player.teleport(room.spawn_position+Vector3.UP*.04)
		check(await walk(definition.return_position+Vector3.UP*.04),label+" walking exit")
		check(world.session.state.place_id.is_empty() and not world.player.input_locked,label+" exterior control")
		check(not world.session.building_entrance.sightline.debug_snapshot().active,label+" railway fully restored after exit")
		if not world.session.state.place_id.is_empty(): finish(); return
	finish()

func finish(code := -1) -> void:
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"visited":visited,"rendered":rendered},"\t"))
	print("BUILDING_WALKTHROUGH ",folder," checks=",checks," failures=",failures)
	quit((0 if failures.is_empty() else 1) if code < 0 else code)
