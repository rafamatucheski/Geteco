extends SceneTree
## Inspection in rendered Main, with real road/terrain/materials and camera.
## Requires --no-save. Does not read/write player saves or certify frame time.
const MODELS := preload("res://gameplay/police_response/ground/PoliceGroundModels.gd")
const BLOCK := preload("res://gameplay/police_response/ground/PoliceRoadblock.gd")
const OUTPUT := "res://evidence/police-response-20260928/"
var world: Node3D

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	seed(28092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for index in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save: quit(3); return
	world.gameplay.health = 1000000
	world.gameplay.set_physics_process(false)
	world.gameplay.police_air.set_physics_process(false)
	world.dispatch.set_physics_process(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(66,.15,129))
	world.production.region.set_focus(world.player.global_position)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.camera.set_physics_process(false)
	world.camera.set_process(false)
	var spot := Vector3.INF
	var yaw := 0.0
	var road_width := 8.0
	var candidates: Array = world.dispatch.router.spawn_candidates(world.player.global_position,5.0,95.0,14.0)
	for candidate in candidates.slice(0,40):
		if float(candidate.edge.width) < 7.5: continue
		var direction := Vector3(-sin(candidate.yaw),0,-cos(candidate.yaw))
		var point: Vector3 = candidate.point-world.dispatch.routes._lane_offset(direction,candidate.edge)
		world.production.region.prepare_collision_at(point)
		await physics_frame
		await physics_frame
		if not world.dispatch._space_clear(Vector3(7.3,3.5,18),point,candidate.yaw,world.dispatch.no_exclusions): continue
		spot = point
		yaw = candidate.yaw
		road_width = float(candidate.edge.width)
		break
	if not spot.is_finite(): print("GROUND_CAPTURE no clear physical road formation"); world.free(); quit(4); return
	world.player.teleport(spot+Basis(Vector3.UP,yaw)*Vector3(-3.0,.08,5.0))
	world.production.region.set_focus(spot)
	var formation := Node3D.new()
	world.add_child(formation)
	formation.global_position = spot
	formation.rotation.y = yaw
	var tank: CharacterBody3D = world.dispatch._create_vehicle("police",formation.to_global(Vector3(1.85,.06,-1)),yaw,"army_tank")
	var bike: CharacterBody3D = world.dispatch._create_vehicle("police",formation.to_global(Vector3(-1.7,.06,-2.6)),yaw,"bike_police")
	for car in [tank,bike]:
		car.set_physics_process(false)
		car.set_external_driver(true)
	for part in bike._motorcycle_rider_parts: part.visible = true
	bike.equipment.siren_on = true
	var block := BLOCK.new()
	formation.add_child(block)
	block.position = Vector3(0,.03,6.8)
	block.build(minf(road_width-.4,12.0))
	block.set_armed(true)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21
	camera.global_position = formation.to_global(Vector3(-15,20,-19))
	camera.look_at(spot+Vector3.UP)
	camera.make_current()
	for index in 90: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var result := root.get_texture().get_image().save_png(OUTPUT+"ground-main-day.png")
	camera.size = 11
	camera.global_position = formation.to_global(Vector3(-10,8,-12))
	camera.look_at(formation.to_global(Vector3(0,1,-1.5)))
	for index in 20: await process_frame
	await RenderingServer.frame_post_draw
	result |= root.get_texture().get_image().save_png(OUTPUT+"ground-main-vehicles.png")
	print("GROUND_CAPTURE result=",result," point=",spot," output=",OUTPUT)
	world.free()
	await process_frame
	quit(0 if result == OK else 1)
