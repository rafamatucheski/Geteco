extends SceneTree
## Real scene collision sweeps, ocean probes, logistics and optional render QA.
const L := preload("res://world/harbor/HarborSouthPortLayout.gd")
var failures: Array[String] = []
var steps := 0
var _capture_root := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_capture_root = arg.trim_prefix("out_dir=")
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1500,1400)
	root.content_scale_size = root.size
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	while not scene.world_build_ready: await process_frame
	for i in 25: await physics_frame
	var port: Node2D = scene.get_node("SouthPort")
	var player: CharacterBody2D = scene.get_node("Player")
	var car: CharacterBody2D = scene.get_node("PlayerCar")
	# GETECO-PERF: view.model pode ser HarborPortModel3D (Node3D, malha real ao
	# vivo) ou HarborPortModelBaked.BakedModelData (RefCounted só com
	# height/hoist_start/hoist_end) -- ver world/harbor/HarborPortModelBaked.gd.
	# Os itens já pré-renderizados por tools/bake_south_port_models.gd não têm
	# viewport_3d/camera_3d/mesh_stats; a verificação de recorte/malha real só
	# se aplica ao caminho ao vivo (que continua existindo como fallback para
	# qualquer item sem bake).
	var model_meshes := 0
	var model_pixels := 0
	var baked_views := 0
	for view in port.model_views:
		var size: Vector2 = view.footprint.size
		var first: Vector2 = view.project_floor(Vector2(-size.x/40.0,-size.y/32.0))
		var last: Vector2 = view.project_floor(Vector2(size.x/40.0,size.y/32.0))
		_check((last-first).distance_to(size) < .1,"3D floor matches world footprint: "+view.name)
		var is_baked: bool = view.get_script() == preload("res://world/harbor/HarborPortModelBaked.gd")
		if is_baked:
			baked_views += 1
			continue
		_check(view.model.mesh_stats.after_count > 0,"Real 3D geometry exists: "+view.name)
		_check(view.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS,"Static 3D renders are cached")
		model_meshes += view.model.mesh_stats.after_count
		model_pixels += view.viewport_3d.size.x*view.viewport_3d.size.y
		var fitted := true
		for mesh in view.model.get_node("BatchedStaticGeometry").get_children():
			var bounds: AABB = mesh.get_aabb()
			for corner in 8:
				var screen: Vector2 = view.camera_3d.unproject_position(mesh.to_global(bounds.get_endpoint(corner)))
				if not Rect2(Vector2.ZERO,Vector2(view.viewport_3d.size)).grow(-2).has_point(screen): fitted = false
		_check(fitted,"Whole 3D model fits cached image without clipping: "+view.name)
	print("PORT_3D_BAKED baked_views=%d live_views=%d" % [baked_views, port.model_views.size()-baked_views])
	_check(port.model_views.size() >= 30,"Port buildings, cargo, cranes and supplies use 3D models")
	_check(model_meshes < 450,"Port geometry remains batched instead of one draw per corrugation")
	print("PORT_3D views=%d batched_meshes=%d texture_pixels=%d" % [port.model_views.size(),model_meshes,model_pixels])
	for actor in get_nodes_in_group("vehicle")+get_nodes_in_group("harbor_dock_worker")+get_nodes_in_group("port_private_security"):
		actor.set_process(false)
		actor.set_physics_process(false)
		# Sweep static geometry with the production masks, excluding frozen traffic.
		if actor is PhysicsBody2D:
			if actor != player: player.add_collision_exception_with(actor)
			if actor != car: car.add_collision_exception_with(actor)
	port.checkpoint.set_process(false)
	port.set_process(false)
	player.set_physics_process(false)
	player.collision_mask = 7
	var space := player.get_world_2d().direct_space_state
	player.position = Vector2(3402,2070)
	for point in [Vector2(3570,2070),Vector2(3570,3260),Vector2(3570,3500),Vector2(3680,3500)]:
		_sweep(player,point)
	for point in [Vector2(3570,3500),Vector2(3570,3260),Vector2(3570,2070),Vector2(3402,2070)]:
		_sweep(player,point)
	# Board from the terminal, cross the cargo aisle and circle the wheelhouse.
	player.position = Vector2(4250,3380)
	for point in [Vector2(4250,3070),Vector2(4250,2880),Vector2(5600,2880),Vector2(5600,2990),Vector2(5500,3030),Vector2(5450,3080),Vector2(4250,3080),Vector2(4250,2752),Vector2(3960,2752),Vector2(3960,2820),Vector2(3940,2820),Vector2(3940,3080),Vector2(4250,3080),Vector2(4250,3380)]:
		_sweep(player,point)
	for worker in port.workers:
		player.position = worker.work_route[0]
		for index in range(1,worker.work_route.size()+1):
			_sweep(player,worker.work_route[index%worker.work_route.size()])
	for point in [Vector2(4250,3160),Vector2(4250,3000),Vector2(4780,2880),Vector2(5600,2920)]:
		_check(_hits(space,point).is_empty(),"Santa Mare deck and boarding surface are open: %s" % point)
	for rect in L.ship_containers()+[L.WHEELHOUSE]:
		_check(not _hits(space,rect.get_center()).is_empty(),"Ship cargo and wheelhouse are solid")
	player.position = Vector2(4500,3090)
	_check(player.move_and_collide(Vector2(0,100)) != null,"Hull rail prevents walking into water beside boarding opening")
	car.collision_mask = 23
	# Traversability sweep uses the new paid entrance contract.
	player.position = Vector2(3310,3320)
	port.checkpoint.pay_bribe()
	port._update_gate(player.position)
	await physics_frame
	car.position = Vector2(3000,2150)
	for point in [Vector2(3000,2200),Vector2(3180,2200),Vector2(3310,2330),Vector2(3310,3600),Vector2(3750,3600),Vector2(5750,3600),Vector2(5750,5650),Vector2(3750,5650),Vector2(3750,4770),Vector2(5750,4770)]:
		car.rotation = (point-car.position).angle()
		_sweep(car,point)
	for point in [Vector2(5750,3600),Vector2(3750,3600),Vector2(3310,3600),Vector2(3310,2330),Vector2(3180,2200),Vector2(3000,2200)]:
		car.rotation = (point-car.position).angle()
		_sweep(car,point)
	for point in [Vector2(3510,2530),Vector2(3640,2530),Vector2(3800,2600),Vector2(4600,3150),Vector2(6200,4000),Vector2(5300,6030)]:
		_check(not _hits(space,point).is_empty(),"Water must block: %s" % point)
	for point in [Vector2(3570,2530),Vector2(3570,3260),Vector2(4700,3450),Vector2(4400,4250),Vector2(5750,4770),Vector2(6240,3700),Vector2(6240,4260),Vector2(5485,5870)]:
		_check(_hits(space,point).is_empty(),"Land must be reachable: %s %s" % [point,_hits(space,point)])
	for rect in L.containers(): _check(not _hits(space,rect.get_center()).is_empty(),"Cargo solid: %s" % rect)
	# Input crosses the actual bollards with the unmodified player collision mask.
	for start in [Vector2(3570,2140),Vector2(3570,3150)]:
		player.position = start
		player.velocity = Vector2.ZERO
		player.set_physics_process(true)
		Input.action_press("move_down")
		# Caminhada ficou em 27,6 px/s por pedido (14/09): 100 quadros fixos só
		# cobriam 46 px. O prazo acompanha a velocidade real do jogador.
		for i in _walk_frames(player, 130.0): await physics_frame
		Input.action_release("move_down")
		player.set_physics_process(false)
		_check(player.position.y > start.y+85,"Native keyboard movement crosses pedestrian bollards")
	car.position = Vector2(3570,3210)
	car.rotation = -PI*.5
	var bollard_hit := car.move_and_collide(Vector2(0,-80))
	_check(bollard_hit != null,"Cars cannot enter the pedestrian gangway")
	car.position = Vector2(3000,2200)
	_check(port.workers.size() == 32 and port.trucks.size() == 3,"Port workforce and cargo fleet")
	# Native controls reach the deck through the new gangway and return to the quay.
	player.position = Vector2(4250,3270)
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	Input.action_press("move_up")
	for i in _walk_frames(player, 260.0): await physics_frame
	Input.action_release("move_up")
	_check(player.position.y < 3090,"Native keyboard movement boards Santa Mare")
	Input.action_press("move_down")
	for i in _walk_frames(player, 260.0): await physics_frame
	Input.action_release("move_down")
	player.set_physics_process(false)
	_check(player.position.y > 3230,"Native keyboard movement disembarks Santa Mare")
	_check(port.is_open_at(6) and port.is_open_at(17.99) and not port.is_open_at(18) and not port.is_open_at(5.99),"Shift boundaries")
	# Unassigned cranes retain their ship/quay transfer and occupied-pad behavior.
	player.position = Vector2(4700,3440)
	var truck: Node2D = port.trucks[0]
	var follow := truck.get_parent() as PathFollow2D
	for state in port.truck_stops: state.phase = "interrupted"
	# The carriers were frozen mid-approach above. Remove those hulls only for
	# the explicitly unassigned-crane scenario; otherwise the pad is occupied.
	var carrier_layers: Array[int] = []
	for carrier in port.trucks:
		carrier_layers.append(carrier.collision_layer)
		carrier.collision_layer = 0
	await physics_frame
	for i in 1000:
		port._process(.05)
	_check(port.completed_loads > 0,"Crane unloading cycles complete")
	_check(port.loaded_containers > 0 and port.unloaded_containers > 0,"Cranes load AND unload actual visible containers")
	_check(port.hoist_loads.size() == 3,"Cargo is conserved: one persistent load per crane")
	for i in 3:
		port.cargo_clocks[i] = 0.0
	port._update_hoists()
	await physics_frame
	_check(not _hits(space,port.cargo_ship_points[0]).is_empty(),"Container on deck has collision")
	_check(_hits(space,port.cargo_quay_points[0]).is_empty(),"Quay landing pad is empty before unloading")
	port.cargo_clocks[0] = 12.0
	port._update_hoists()
	await physics_frame
	_check(_hits(space,port.cargo_ship_points[0]).is_empty(),"Picked-up container leaves an open deck slot")
	_check(port.hoist_loads[0].position.distance_to(port.cargo_ship_points[0]) > 50,"Same 3D container travels under the crane")
	port.cargo_clocks[0] = 24.0
	port._update_hoists()
	await physics_frame
	_check(not _hits(space,port.cargo_quay_points[0]).is_empty(),"Unloaded container physically occupies quay landing pad")
	_check(_hits(space,port.cargo_ship_points[0]).is_empty(),"No duplicate cargo remains on ship after unloading")
	port.cargo_clocks[0] = 15.9
	port._update_hoists()
	await physics_frame
	player.position = port.cargo_quay_points[0]
	await physics_frame
	port._advance_cargo(.2)
	_check(is_equal_approx(port.cargo_clocks[0],15.9),"Crane holds suspended cargo while player occupies landing pad")
	player.position = Vector2(4700,3440)
	await physics_frame
	port._advance_cargo(.2)
	_check(port.cargo_clocks[0] > 16,"Crane resumes after landing pad clears")
	port.checkpoint.authorized = false
	scene.weather.time_of_day = .9
	var stopped_clocks: Array = port.cargo_clocks.duplicate()
	port._process(.3)
	_check(not port.shift_open and truck.speed == 0,"Freight pauses outside working hours")
	_check(port.cargo_clocks == stopped_clocks,"Suspended cargo also pauses after hours")
	await physics_frame
	_check(not port.gate_open,"Unoccupied freight gate closes after hours")
	player.position = Vector2(3310,3510)
	port._process(.3)
	_check(port.gate_open,"Outbound player can leave the terminal after hours")
	player.position = Vector2(4700,3440)
	scene.weather.time_of_day = .45
	port._process(.3)
	_check(port.shift_open,"Freight resumes during working hours")
	for i in port.trucks.size(): port.trucks[i].collision_layer = carrier_layers[i]
	await physics_frame
	await _test_truck_loading(scene,port,player)
	if DisplayServer.get_name() != "headless":
		var camera := scene.get_node("OverviewCamera") as Camera2D
		camera.make_current()
		camera.position = Vector2(4150,3270)
		camera.zoom = Vector2.ONE*.23
		await _capture("D:/geteco/artifacts/south-port-overview.png")
		camera.position = Vector2(4750,3330)
		camera.zoom = Vector2.ONE*.55
		await _capture("D:/geteco/artifacts/south-port-unloading.png")
		player.position = Vector2(4250,3040)
		camera.position = Vector2(4540,3010)
		camera.zoom = Vector2.ONE*.95
		await _capture("D:/geteco/artifacts/south-port-boarding.png")
		camera.position = Vector2(4780,4750)
		camera.zoom = Vector2.ONE*.46
		await _capture("D:/geteco/artifacts/south-port-yard.png")
		_export_model_image(port.get_node("CargoStack3D00"), "D:/geteco/artifacts/south-port-container-model.png")
		_export_model_image(port.get_node("QuaysideCrane3D0"), "D:/geteco/artifacts/south-port-crane-model.png")
		camera.position = Vector2(4200,3970)
		camera.zoom = Vector2.ONE*1.4
		await _capture("D:/geteco/artifacts/south-port-3d-detail.png")
		scene.weather.time_of_day = .9
		scene.weather._update_lighting()
		port._process(.3)
		camera.position = Vector2(4750,3330)
		camera.zoom = Vector2.ONE*.55
		await _capture("D:/geteco/artifacts/south-port-night.png")
	for failure in failures: push_error(failure)
	print("SOUTH_PORT steps=%d workers=%d trucks=%d loads=%d failures=%d" % [steps,port.workers.size(),port.trucks.size(),port.truck_stops[0].loads,failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_truck_loading(scene: Node2D,port: Node2D,player: CharacterBody2D) -> void:
	var camera := scene.get_node("OverviewCamera") as Camera2D
	camera.make_current()
	camera.position = Vector2(4350,3270)
	camera.zoom = Vector2.ONE*1.5
	player.position = Vector2(4250,3200)
	var starts: Array[Vector2] = []
	for i in 3:
		var truck: Node2D = port.trucks[i]
		var follow := truck.get_parent() as PathFollow2D
		follow.progress = port.truck_logistics.bay_offsets[i]-180
		truck._lane_motion_speed = 0
		truck._lane_motion_initialized = true
		truck.set_meta("traffic_stop_offset",port.truck_logistics.bay_offsets[i])
		port.truck_stops[i].phase = "approach"
		port.cargo_clocks[i] = 0
		starts.append(truck.global_position)
		_check(not truck.body_model.cargo_mount.visible,"Carrier arrives with an empty platform")
	port._update_hoists()
	var saw_lowering := false
	var saw_departure := false
	var pause_checked := false
	var saw_turn := false
	var laps := [0,0,0]
	for tick in 3800:
		port._process(.05)
		for index in port.trucks.size():
			var carrier: Node2D = port.trucks[index]
			var before: float = carrier.get_parent().progress
			carrier.advance_on_lane(.05)
			if carrier.get_parent().progress < before: laps[index] += 1
			carrier._update_3d_orientation(.05)
		var state: Dictionary = port.truck_stops[0]
		if state.phase == "loading":
			var carrier: Node2D = port.trucks[0]
			var follow := carrier.get_parent() as PathFollow2D
			_check(absf(follow.progress-port.truck_logistics.bay_offsets[0]) < .6,"Truck holds its exact loading position")
			_check(not carrier.body_model.cargo_mount.visible,"No container appears on truck before crane lowers it")
			if not pause_checked:
				var before: float = port.cargo_clocks[0]
				scene.weather.time_of_day = .9
				port._process(.3)
				_check(is_equal_approx(before,port.cargo_clocks[0]) and carrier.speed == 0,"Night shift pauses truck loading")
				scene.weather.time_of_day = .45
				port._process(.3)
				pause_checked = true
			if port.cargo_clocks[0] >= 18 and not saw_lowering:
				saw_lowering = true
				_check(carrier.speed == 0,"Truck stays stopped under suspended load")
				_check(port.workers[0].get_meta("port_guiding",false),"Dock worker signals during loading")
				if DisplayServer.get_name() != "headless": await _capture("D:/geteco/artifacts/south-port-truck-loading.png")
		if state.phase == "securing":
			_check(port.trucks[0].body_model.cargo_mount.visible and not port.hoist_loads[0].visible,"One load moves from crane to flatbed without duplication")
			_check(port.trucks[0].speed == 0,"Worker securing interval holds the truck")
		if state.phase == "departed" and port.trucks[0].global_position.distance_to(starts[0]) > 430 and not saw_departure:
			saw_departure = true
			camera.position = port.trucks[0].global_position+Vector2(0,-90)
			if DisplayServer.get_name() != "headless": await _capture("D:/geteco/artifacts/south-port-truck-departure.png")
		if state.phase == "departed" and absf(port.trucks[0].global_rotation) > 1 and not saw_turn:
			saw_turn = true
			camera.position = port.trucks[0].global_position
			port.trucks[0]._update_3d_orientation(.05)
			if DisplayServer.get_name() != "headless": await _capture("D:/geteco/artifacts/south-port-truck-turn.png")
		if tick%20 == 0: await physics_frame
	_check(saw_lowering and saw_departure,"Arrival, crane lowering and loaded departure occur through live scheduler")
	for i in 3:
		_check(port.truck_stops[i].loads == 1 and port.truck_stops[i].phase == "departed","Each carrier receives exactly one container and leaves")
		_check(port.trucks[i].global_position.distance_to(starts[i]) > 500,"Loaded truck travels away around the port")
		_check(port.trucks[i].body_model.cargo_mount.visible,"Container stays mounted after driving and turning")
		_check(not port.hoist_loads[i].visible,"Exported load is not duplicated back onto the ship")
		_check(not port.trucks[i].has_meta("traffic_stop_offset"),"Departure releases the loading stop")
		_check(laps[i] > 0,"Loaded carrier completes a full circuit without losing or reloading cargo")
	print("PORT_TRUCKS lowering=%s departure=%s laps=%s states=%s" % [saw_lowering,saw_departure,laps,port.truck_stops])

func _sweep(body: CharacterBody2D,target: Vector2) -> void:
	for i in 2000:
		var delta := target-body.position
		if delta.length() < .1: return
		var hit := body.move_and_collide(delta.limit_length(8))
		steps += 1
		if hit:
			_check(false,"%s blocked at %s towards %s by %s" % [body.name,body.position,target,hit.get_collider()])
			return
	_check(false,"Sweep exceeded budget")

func _hits(space: PhysicsDirectSpaceState2D,point: Vector2) -> Array[Dictionary]:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return space.intersect_point(query)

## Quadros de física para andar `distance` px na velocidade atual, com folga.
func _walk_frames(actor: Node, distance: float) -> int:
	return ceili(distance / maxf(float(actor.get("speed")), 1.0) * Engine.physics_ticks_per_second * 1.15)

func _check(ok: bool,reason: String) -> void:
	if not ok: failures.append(reason)

func _capture(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var output := _capture_path(path)
	_check(root.get_texture().get_image().save_png(output) == OK,"Screenshot saved: "+output)

## GETECO-PERF: se o item já foi pré-renderizado (HarborPortModelBaked), não
## existe viewport_3d ao vivo -- exporta a textura já bakeada (mesma imagem
## que o jogo realmente usa) em vez da renderização em tempo real.
func _export_model_image(view: Node2D, path: String) -> void:
	var output := _capture_path(path)
	if view.get_script() == preload("res://world/harbor/HarborPortModelBaked.gd"):
		_check(view.sprite_3d.texture.get_image().save_png(output) == OK,"Model image saved (baked): "+output)
	else:
		_check(view.viewport_3d.get_texture().get_image().save_png(output) == OK,"Model image saved (live): "+output)


func _capture_path(default_path: String) -> String:
	if _capture_root.is_empty():
		return default_path
	DirAccess.make_dir_recursive_absolute(_capture_root)
	return _capture_root.path_join(default_path.get_file())
