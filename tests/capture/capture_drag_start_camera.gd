extends SceneTree
## Visual launch review in actual Main/.NET with an isolated checkpoint.
## PNG capture overhead makes this unsuitable for performance measurement.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT = preload("res://world/desert/DesertLayout.gd")
var world
var output := ""

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("DRAG_CAMERA timeout"); quit(3))
	run.call_deferred()

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output = FIXTURE.output_dir("drag-start-camera")
	var at: Vector3 = LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary = FIXTURE.full_snapshot(at,true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode = true
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	var session = world.session
	var race = session.desert.drag
	# Separate admission/queue contracts already have integration coverage.
	race.open_meet.enabled = false
	var car = world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not is_instance_valid(car): quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if not world.driving.interact(): quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	session.weather.set_process(false)
	session.weather.time_of_day = .9
	session.weather._update()
	await review(race)
	world.free()
	quit()

func review(race) -> void:
	Engine.max_fps = 60
	if not race.perform("start"): push_error(race.start_block_reason()); quit(1); return
	race._throttle_override = .54
	while race.active and race.phase=="preparing": await physics_frame
	await create_timer(.2).timeout
	await capture("rear-red")
	while race.countdown>0.8: await physics_frame
	await capture("rear-amber")
	while race.phase=="staging": await physics_frame
	await capture("green")
	for i in 24:
		race._throttle_override = 1.0
		await create_timer(.1).timeout
		await capture("sweep-%02d"%i)
	race.cancel_attempt()
	await create_timer(.2).timeout
	await capture("restored")
	print("DRAG_CAMERA_VISUAL ",ProjectSettings.globalize_path(output))
