extends SceneTree
## Real Main ground review only. Captures are not frame-time measurements.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
var world
var folder := ""
var checks := 0
var failures: Array[String] = []
var sequence: Array = []
var before := {}
var recording := ""
var recording_index := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("PARK_GROUND_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func fingerprints() -> Dictionary:
	var result := {}
	for file in ["ParkLume.gd","ParkLumeGround.gd","ParkGroundVerge.gdshader"]:
		result[file] = FileAccess.get_sha256("res://world/places/amusement_park/"+file)
	return result

func frames(count: int) -> void:
	for frame in count: await physics_frame

func capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func record_render_frame() -> void:
	if recording.is_empty(): return
	var filename := "%s_%03d.jpg"%[recording,recording_index]
	var ticks := Time.get_ticks_usec()
	var drawn := Engine.get_frames_drawn()
	var screenshot: Image = root.get_texture().get_image()
	screenshot.resize(960,540,Image.INTERPOLATE_LANCZOS)
	screenshot.save_jpg(folder.path_join(filename),.91)
	sequence.append({"route":recording,"file":filename,"index":recording_index,"render_frame":drawn,"ticks_usec":ticks,"player":str(world.player.global_position),"camera":str(world.camera.global_transform)})
	recording_index += 1

func view(id: String,at: Vector3,target: Vector3) -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 65
	camera.far = 450
	camera.environment = world.production.environment.environment.duplicate(true)
	camera.environment.fog_depth_begin = 110
	camera.environment.fog_depth_end = 330
	camera.global_position = LAYOUT.ORIGIN+at
	camera.look_at(LAYOUT.ORIGIN+target)
	camera.make_current()
	await frames(8)
	await capture(id)
	world.camera.make_current()
	camera.queue_free()

func record_walk(id: String,from: Vector3,to: Vector3) -> void:
	world.player.teleport(LAYOUT.ORIGIN+from)
	world.camera.initialized = false
	world.camera.make_current()
	await frames(8)
	var supported := true
	var target := LAYOUT.ORIGIN+to
	var prior_max_fps := Engine.max_fps
	Engine.max_fps = 30
	recording = id
	recording_index = 0
	var initial_index := sequence.size()
	for frame in 180:
		var offset: Vector3 = target-world.player.global_position
		offset.y = 0
		world.player.automatic_direction = offset.normalized() if offset.length()>.15 else Vector3.ZERO
		await physics_frame
		supported = supported and world.player.global_position.y>-.025 and world.player.global_position.y<.07
	await RenderingServer.frame_post_draw
	recording = ""
	Engine.max_fps = prior_max_fps
	world.player.automatic_direction = Vector3.ZERO
	var remaining: Vector3 = target-world.player.global_position
	remaining.y = 0
	check(remaining.length()<.30 and supported,id+" walks across finish seam with native supported body")
	# max_fps is a ceiling. Readback/encoding may slow this diagnostic capture;
	# continuity depends on actual render counters and coverage, not a frame quota.
	var continuous := sequence.size()-initial_index>=2
	if continuous:
		continuous = sequence[-1].ticks_usec-sequence[initial_index].ticks_usec>=2500000
	for index in range(initial_index+1,sequence.size()):
		continuous = continuous and sequence[index].render_frame==sequence[index-1].render_frame+1
	check(continuous,id+" captures every rendered frame without counter gaps")

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	create_timer(160).timeout.connect(func(): push_error("Ground review timeout"); finish(3))
	seed(81026)
	folder = FIXTURE.output_dir("amusement-park-ground-session")
	before = fingerprints()
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"fixture.json",snapshot))
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"production C# route service active")
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	RenderingServer.frame_post_draw.connect(record_render_frame)
	var at := LAYOUT.ORIGIN+Vector3(12,.08,19)
	world.production.region.set_focus(at)
	world.production.region.prepare_collision_at(at)
	world.player.teleport(at)
	world.camera.initialized = false
	await create_timer(2.0).timeout
	var park: Node3D = world.session.amusement_park.site
	check(is_instance_valid(park) and park.get_meta("integrated_ground",false),"new ground admitted in real Harbor")
	await capture("park_walk")
	await view("park_overview",Vector3(58,48,64),Vector3(0,3,0))
	await view("entry_north_joint",Vector3(45,2.8,8),Vector3(40,.02,13.1))
	await view("entry_south_joint",Vector3(45,2.8,25),Vector3(40,.02,18.9))
	await view("southwest_corner",Vector3(-44,2.5,40),Vector3(-40,.02,36))
	await view("northwest_corner",Vector3(-44,2.5,-40),Vector3(-40,.02,-36))
	await view("northeast_bevel",Vector3(43,2.5,-11),Vector3(39,.02,-11))
	await record_walk("entry_seams",Vector3(44,.08,11.7),Vector3(44,.08,20.3))
	await record_walk("garden_seam",Vector3(0,.08,-34),Vector3(0,.08,-28))
	check(world.session.amusement_park.life.actors.size()==4,"four live clowns remain admitted during ground walk")
	check(before==fingerprints(),"park ground sources stable throughout rendered review")
	finish()

func finish(code := -1) -> void:
	var report := {"checks":checks,"failures":failures,"sequence":sequence,"source_start":before,"source_end":fingerprints(),"capture_not_benchmark":true,"sequence_resolution":"960x540 JPEG91","sequence_max_fps":30,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"weather":0,"hour":.45}
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PARK_GROUND_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	quit(code if code>=0 else (0 if failures.is_empty() else 1))
