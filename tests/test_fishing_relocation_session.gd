extends SceneTree
## Uma jornada real no Main: save legado, controles reais do carro, emendas de terra/chão,
## entrada de caminhada/pesca e persistência isolada. Os quadros contínuos são evidência
## visual; o limite de leitura/JPEG/captura exclui explicitamente conclusões de FPS.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LOCATION := preload("res://runtime/FishingLocation.gd")
const LAYOUT := preload("res://world/places/fishing/FishingRuralLayout.gd")
const STATE := preload("res://runtime/GameState.gd")
const FISH_STATE := preload("res://activities/fishing/FishingState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world
var folder := ""
var save_path := ""
var failures: Array[String] = []
var checks := 0
var frames: Array[Dictionary] = []
var recording := false
var started := 0
var last_drawn := -1
var missed := 0
var phase := ""
var writes_ok := true
var source_before := {}
var finished := false
var depth_captures: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks += 1
	print("FISHING_RELOCATION_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(270).timeout.connect(func(): check(false,"finite journey deadline"); finish(3))
	folder = FIXTURE.output_dir("fishing-relocation-session")
	if not check(not folder.is_empty(),"unique evidence directory"): finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("route")))
	source_before = fingerprint()
	var legacy_point := LOCATION.LEGACY_ANCHOR+Vector3(0,.10,30)
	var snapshot := FIXTURE.full_snapshot(legacy_point,false)
	# O helper do portal usa por padrão um final ativo; esta jornada de propósito
	# começa entre missões, já que a pesca livre exige nenhuma campanha em andamento.
	snapshot.campaign.active_id = ""
	snapshot.campaign.step = 0
	snapshot.economy.balance = 500
	var state = STATE.new()
	check(state.restore_snapshot(snapshot),"legacy-position fixture restores before migration")
	var serial: int = FISH_STATE.begin(state.world_state,state.economy,-1)
	FISH_STATE.record_catch(state.world_state,serial,{"id":"tilapia","grams":1400})
	FISH_STATE.finish(state.world_state,serial,false)
	save_path = FIXTURE.write_fixture(folder,"isolated-save.json",state.snapshot())
	if not check(not save_path.is_empty(),"isolated checkpoint carries previous catch ledger"): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	check(world.production.store.path==save_path and not world.production.save_invalid,"Main admits isolated legacy save without invalidation")
	check(world.player.global_position.distance_to(legacy_point)<.6 and world.session.position_clear(world.player.global_position),"old lake checkpoint resumes safely on the retired meadow")
	check(world.session.fishing.snapshot().best==1400 and world.session.fishing.snapshot().catches==1 and world.session.state.economy.balance==490,"previous catch and wallet survive relocation")
	check(not is_instance_valid(world.session.fishing_runtime.site),"former lake location no longer mounts fishing props")
	await photo("legacy-meadow")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# route service remains active")
	check(world.production.ambient_traffic_routes.segments.all(func(segment): return segment.id!=LAYOUT.ROAD_ID),"ambient traffic never enters the private fishing access")
	var start := Vector3(-344,.12,18.32)
	world.production.region.set_focus(start)
	world.production.region.prepare_collision_at(start)
	var car = world.driving.car
	var heading := Vector3(-378,0,21)-Vector3(start.x,0,start.z)
	car.place(start,atan2(-heading.x,-heading.z))
	car.input_locked = false
	car.remove_meta("awaiting_ground")
	car.set_physics_process(true)
	car.finish_doors()
	var approach: Vector3 = car.driver_door_anchor(1)+car.global_basis.x*.6+Vector3.UP*.10
	world.production.region.prepare_collision_at(approach)
	world.player.teleport(approach)
	world.camera.initialized = false
	await create_timer(1).timeout
	if not check(world.driving.interact(),"ordinary door interaction starts boarding"): finish(); return
	var deadline := Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(world.driving.occupied and not world.driving.is_body_transition_active(),"player seated with production handling"): finish(); return
	Engine.max_fps = 30
	RenderingServer.frame_post_draw.connect(record_frame)
	started = Time.get_ticks_usec()
	phase = "road-start"
	recording = true
	await create_timer(2).timeout
	await photo("dirt-road-start")
	phase = "drive"
	var route := Curve3D.new()
	for point in LAYOUT.road_points(): route.add_point(point)
	route.add_point(LOCATION.ANCHOR+Vector3(-10,0,27))
	if not check(await drive(route),"real accelerator steering and brakes traverse the dirt road into parking"): finish(); return
	check(car.global_position.y>-.08 and car.health>0,"car remains supported and intact across old/new ground")
	phase = "parking"
	await photo("parking")
	if not check(world.driving.leave(),"ordinary disembark has a clear parking return"): finish(); return
	deadline = Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(not world.driving.occupied and not world.player.input_locked,"parking exit restores walking controls"): finish(); return
	var site = world.session.fishing_runtime.site
	if not check(is_instance_valid(site) and site.anglers.size()==5,"new clearing mounts one lake and five anglers"): finish(); return
	phase = "walk"
	if not check(await walk(site.to_global(Vector3(-3,.09,28))),"walk out of parking along the entrance apron"): finish(); return
	if not check(await walk(site.entry_position()),"walk from entrance to fishing counter"): finish(); return
	await photo("reception")
	if not check(await world.session.interact() and world.session.modal,"actual counter interaction opens the fishing menu"): finish(); return
	var selected := false
	for button in world.session.column.get_children():
		if button is Button and button.text.begins_with("Pesca livre"):
			button.pressed.emit()
			selected = true
			break
	if not check(selected and world.session.fishing.active,"menu buys a new free-fishing entry"): finish(); return
	for point in site.approach_waypoints(0):
		if not check(await walk(point),"dry bank approach "+str(point)): finish(); return
	if not check(await world.session.interact() and world.session.fishing.controls_locked(),"shore interaction equips the rod in the new lake"): finish(); return
	phase = "fishing"
	await create_timer(2).timeout
	await photo("fishing-ready")
	var event := InputEventAction.new()
	event.action = "exit_vehicle"
	event.pressed = true
	world.session._input(event)
	check(not world.session.fishing.active and not world.player.input_locked,"ordinary cancel releases rod and movement")
	check(world.session.fishing.snapshot().best==1400 and world.session.fishing.snapshot().catches==1 and world.session.state.economy.balance==480,"new entry preserves old catches and debits exactly once")
	phase = "bank-stationary"
	await create_timer(3).timeout
	recording = false
	Engine.max_fps = 144
	check(writes_ok and frames.size()>600 and missed==0,"continuous route frames written without counter gaps")
	check(float(frames[-1].elapsed_us)/1000000.0>=30,"continuous evidence covers at least thirty seconds of terrain traversal")
	world.production.no_save = false
	check(world.session.save_game(),"new lake checkpoint saved to isolated slot")
	world.production.no_save = true
	var restored = STATE.new()
	check(restored.restore_snapshot(STORE.read_valid(save_path)) and FISH_STATE.data(restored.world_state).best==1400,"new location save reload retains previous catch ledger")
	var saved_point: Array = restored.world_state.pedestrian.position
	check(Vector3(saved_point[0],saved_point[1],saved_point[2]).distance_to(world.player.global_position)<.6,"new pedestrian position persists at the new lake")
	var return_point: Vector3 = world.player.global_position
	var away := LOCATION.LEGACY_ANCHOR+Vector3(0,.1,30)
	world.production.region.set_focus(away)
	world.production.region.prepare_collision_at(away)
	world.player.teleport(away)
	world.session.fishing_runtime.refresh()
	for frame in 8: await process_frame
	check(not is_instance_valid(world.session.fishing_runtime.site) and get_nodes_in_group("fishing_angler").is_empty(),"leaving unloads lake props and all anglers")
	world.production.region.set_focus(return_point)
	world.production.region.prepare_collision_at(return_point)
	world.player.teleport(return_point)
	world.session.fishing_runtime.refresh()
	for frame in 10: await process_frame
	check(get_nodes_in_group("fishing_angler").size()==5 and world.session.position_clear(world.player.global_position),"return restores one population and safe shore support")
	await photo("return-bank")
	var map := preload("res://ui/hud/WorldMapData.gd").new()
	map.collect(world.production)
	check(map.markers.any(func(marker): return marker.id=="fishing" and marker.point.distance_to(Vector2(LOCATION.ENTRY.x,LOCATION.ENTRY.z))<.1),"map marker follows the new dirt-road destination")
	check(map.roads.any(func(road): return road.id==LAYOUT.ROAD_ID and road.surface=="earth" and road.points==PackedVector2Array(LOCATION.ROAD_POINTS)),"map draws the complete connected dirt-road itinerary despite exclusion from ambient traffic")
	check(world.production.region.coastal_protection.on_land(Vector2(LOCATION.ANCHOR.x,LOCATION.ANCHOR.z)),"shore protection classifies the new clearing as dry land")
	world.session.show_map()
	await process_frame
	var map_ui = world.hud.get_node_or_null("MapUI")
	if check(is_instance_valid(map_ui),"ordinary world map opens at the new fishing location"):
		for index in map_ui._markers.size():
			if map_ui._markers[index].id=="fishing": map_ui._selected=index; break
		map_ui._mark_selected()
		check(world.get_meta("map_waypoint",Vector2.INF).distance_to(Vector2(LOCATION.ENTRY.x,LOCATION.ENTRY.z))<.1,"map destination action marks the new fishing entrance")
		map_ui.focus_region("harbor")
		map_ui.target_center = Vector2(-425,-5)
		map_ui.target_zoom = 8
		await create_timer(.5).timeout
		await photo("map-road-destination")
	world.session.close_menu()
	await capture_tree_depth()
	finish()

func capture_tree_depth() -> void:
	# Dante real, porta-malas nativo real e teste de profundidade normal. As posições da fixture são
	# separadas da jornada; quadros pareados de mostrar/esconder isolam os pixels do alvo.
	var inventory := preload("res://world/places/fishing/FishingWoodland.gd").tree_inventory()
	inventory.sort_custom(func(a,b): return a.point.distance_to(LOCATION.ENTRY)<b.point.distance_to(LOCATION.ENTRY))
	var tree_point: Vector3 = inventory[0].point
	var actor_point := tree_point+Vector3(0,.10,1.9)
	var previous_point: Vector3 = world.player.global_position
	world.production.region.set_focus(actor_point)
	world.production.region.prepare_collision_at(actor_point)
	world.player.teleport(actor_point)
	world.player.automatic_direction = Vector3.ZERO
	for frame in 4: await physics_frame
	check(world.session.position_clear(world.player.global_position),"depth fixture places Dante on open ground beside a real trunk")
	var old_camera := root.get_camera_3d()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 64
	camera.near = .05
	camera.far = 160
	camera.make_current()
	var was_paused := paused
	paused = true
	await depth_pair(camera,world.player.visual,"dante-visible",tree_point+Vector3(2.5,1.0,-2.5),actor_point+Vector3.UP*.85,true)
	await depth_pair(camera,world.player.visual,"dante-behind-trunk",tree_point+Vector3(0,1.0,-2.5),actor_point+Vector3.UP*.85,false)
	old_camera.make_current()
	camera.queue_free()
	paused = was_paused
	world.player.teleport(previous_point)

func depth_pair(camera: Camera3D,target: Node3D,id: String,origin: Vector3,look: Vector3,expected_visible: bool) -> void:
	camera.global_position = origin
	camera.look_at(look)
	var was_visible := target.visible
	target.show()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var with_target := root.get_texture().get_image()
	check(with_target.save_png(folder.path_join("depth-"+id+".png"))==OK,"depth capture "+id)
	target.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var without_target := root.get_texture().get_image()
	check(without_target.save_png(folder.path_join("depth-"+id+"-control.png"))==OK,"depth control "+id)
	target.visible = was_visible
	var size := Vector2i(with_target.get_width()/12,with_target.get_height()/8)
	var region := Rect2i((Vector2i(with_target.get_width(),with_target.get_height())-size)/2,size)
	var changed := 0
	var maximum := 0.0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var a := with_target.get_pixel(x,y)
			var b := without_target.get_pixel(x,y)
			var difference := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			maximum = maxf(maximum,difference)
			if difference>8.0/255.0: changed += 1
	check(changed>=64 if expected_visible else changed<=8,id+" target pixels visible" if expected_visible else id+" trunk blocks target pixels")
	depth_captures.append({"id":id,"expected_visible":expected_visible,"camera":var_to_str(origin),"look":var_to_str(look),"roi":var_to_str(region),"changed_pixels":changed,"maximum_difference":maximum})

func drive(route: Curve3D) -> bool:
	var car = world.driving.car
	var length := route.get_baked_length()
	var deadline := Time.get_ticks_msec()+75000
	while Time.get_ticks_msec()<deadline:
		var along := route.get_closest_offset(car.global_position)
		var remaining := length-along
		var target := route.sample_baked(minf(length,along+5.0),true)
		var delta: Vector3 = target-car.global_position
		delta.y = 0
		if remaining<.7 and delta.length()<1.8: break
		var desired := atan2(-delta.x,-delta.z)
		var yaw_error := wrapf(desired-car.rotation.y,-PI,PI)
		var turn := clampf(-yaw_error*1.9,-1.0,1.0)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if turn<0: Input.action_press("move_left",maxf(.23,-turn))
		elif turn>0: Input.action_press("move_right",maxf(.23,turn))
		var target_speed := minf(4.3,maxf(1.0,remaining*.8))
		Input.action_release("accelerate")
		Input.action_release("brake")
		if car.speed<target_speed: Input.action_press("accelerate",clampf((target_speed-car.speed)*.16,.035,.36))
		elif car.speed>target_speed+.5: Input.action_press("brake",.15)
		if car.global_position.y<-.25 or car.health<=0: break
		await physics_frame
	release_driving()
	Input.action_press("handbrake")
	await create_timer(1).timeout
	Input.action_release("handbrake")
	var goal := route.sample_baked(length)
	var error: Vector3 = car.global_position-goal
	error.y = 0
	print("FISHING_DRIVE_END ",car.global_position," target=",goal," speed=",car.speed," health=",car.health)
	return error.length()<2 and car.global_position.y>-.1

func release_driving() -> void:
	for action in ["accelerate","brake","move_left","move_right","handbrake"]: Input.action_release(action)

func walk(point: Vector3) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		var delta: Vector3 = point-world.player.global_position
		delta.y = 0
		if delta.length()<.22: break
		world.player.automatic_direction = delta.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var error: Vector3 = point-world.player.global_position
	error.y = 0
	return error.length()<.35

func record_frame() -> void:
	if not recording: return
	var drawn := Engine.get_frames_drawn()
	if last_drawn>=0: missed += maxi(0,drawn-last_drawn-1)
	last_drawn = drawn
	var frame := root.get_texture().get_image()
	frame.resize(480,270,Image.INTERPOLATE_LANCZOS)
	var filename := "%05d.jpg"%frames.size()
	writes_ok = frame.save_jpg(folder.path_join("route").path_join(filename),.9)==OK and writes_ok
	frames.append({"index":frames.size(),"render_frame":drawn,"elapsed_us":Time.get_ticks_usec()-started,"phase":phase,"file":filename,
		"actor":var_to_str(world.player.global_position),"car":var_to_str(world.driving.car.global_position),"camera":var_to_str(root.get_camera_3d().global_position)})

func photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture "+label)

func fingerprint() -> Dictionary:
	var result := {}
	for path in ["res://runtime/FishingRuntime.gd","res://runtime/FishingLocation.gd","res://world/regions/NativeRegion.gd","res://world/editing/world_edits.json","res://gameplay/urban_v1/FreightOutskirts.gd","res://ui/hud/WorldMapData.gd"]:
		result[path] = FileAccess.get_sha256(path)
	for directory in ["res://world/places/fishing","res://activities/fishing"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".gd") or filename.ends_with(".gdshader"): result[directory.path_join(filename)] = FileAccess.get_sha256(directory.path_join(filename))
	return result

func finish(code := -1) -> void:
	if finished: return
	finished = true
	recording = false
	release_driving()
	var after := fingerprint()
	if not folder.is_empty():
		FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames,"depth":depth_captures,"missing_frames":missed,"writes_ok":writes_ok,"source_before":source_before,"source_after":after,"source_stable":source_before==after,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"note":"Real Main driving via input actions and native player handling. Initial car placement, final residency jumps and depth fixture positioning are setup; the access road, parking and shore were traversed physically. Every rendered frame captured; temporary 30 FPS cap/readback/JPEG prevent performance conclusions."},"\t"))
	print("FISHING_RELOCATION_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	quit(code if code>=0 else 0 if failures.is_empty() else 1)
