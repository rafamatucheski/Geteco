extends "res://tests/test_belt_lantern_occlusion.gd"
## Render the real fleet meshes, including the occupied cabin presentation.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CABIN := preload("res://gameplay/VehicleInterior.gd")
const OUT := "res://evidence/mobile-lights-rain-20261015/body"
class BusKit extends Node:
	var headlights_on := false
	var lamps: Array[Dictionary] = []
	func _refresh() -> void:
		for item in lamps: item.lamp.visible = headlights_on
class MovingBody extends Node:
	var vehicle: Node3D
	var elapsed := 0.0
	func _physics_process(delta: float) -> void:
		elapsed += delta
		var phase := mini(3,int(elapsed/8.0))
		vehicle.rotation.y = [0.0,PI,PI/2.0,-PI/2.0][phase]
		vehicle.position.x = 6.0*cos(fposmod(elapsed,8.0)*TAU/8.0)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(120).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280,720)
	var bus_source := "--bus-source" in OS.get_cmdline_user_args()
	var output := OUT.path_join("bus-source") if bus_source else OUT
	var game := Game.new()
	game.world = game
	root.add_child(game)
	game.player = Actor.new()
	game.add_child(game.player)
	game.player.visual = Node3D.new()
	game.player.add_child(game.player.visual)
	camera = Camera3D.new()
	game.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21
	camera.position = Vector3(12,16,7)
	camera.look_at(Vector3(0,0,-7))
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .01
	camera.environment = environment
	box(game,Vector3(0,-.1,-8),Vector3(30,.2,40))
	var receiver_height := .4 if bus_source else .65
	var protected := Vector3(0,receiver_height,-12)
	# The sideways body casts a wider shadow downstream than its own width.
	var control := Vector3(5.5,receiver_height,-12)
	box(game,protected,Vector3(.7,.5,.08))
	box(game,control,Vector3(.7,.5,.08))
	var source = load("res://runtime/transit/BiarticulatedBus.gd").new() if bus_source else VEHICLE.new()
	if not bus_source: source.archetype = "union_sedan"
	source.position.y = .1
	if bus_source: source.position.z = 2.0
	game.add_child(source)
	source.set_physics_process(false)
	source.controlled = true
	var kit: Node
	if bus_source:
		source.set_active(true)
		kit = BusKit.new()
		game.add_child(kit)
		for beam in source.headlights:
			kit.lamps.append({"lamp":beam})
			check(beam.shadow_enabled,"articulated bus front projector blocks opaque bodies")
	else: kit = source.ensure_equipment(game)
	kit.headlights_on = true
	kit._refresh()
	DirAccess.make_dir_recursive_absolute(output)
	var report: Array = []
	for id in ["union_sedan", "courier_van", "sport_coupe"]:
		var target = VEHICLE.new()
		target.archetype = id
		target.position = Vector3(0,.1,-7)
		game.add_child(target)
		target.set_physics_process(false)
		for occupied in [false,true]:
			if occupied: CABIN.open_view(target)
			for orientation in [["front",PI],["rear",0.0],["left",PI/2.0],["right",-PI/2.0]]:
				target.rotation.y = orientation[1]
				target.reset_physics_interpolation()
				kit.headlights_on = false
				kit._refresh()
				var dark := await picture()
				kit.headlights_on = true
				kit._refresh()
				target.show()
				var blocked := await picture()
				target.hide()
				var open := await picture()
				target.show()
				var blocked_gain := brightness(blocked,protected)-brightness(dark,protected)
				var open_gain := brightness(open,protected)-brightness(dark,protected)
				var control_gain := brightness(blocked,control)-brightness(dark,control)
				var label := "%s-%s-%s" % [id,"occupied" if occupied else "parked",orientation[0]]
				check(open_gain > .08,label+" control source reaches receiver without vehicle")
				check(control_gain > .04,label+" light passes beside vehicle")
				check(blocked_gain < .025 and blocked_gain < open_gain*.15,label+" opaque body stops light")
				var entry := {"id":label,"blocked_gain":blocked_gain,"open_gain":open_gain,"beside_gain":control_gain,"leak_ratio":blocked_gain/maxf(.001,open_gain)}
				report.append(entry)
				print("BODY_OCCLUSION ",JSON.stringify(entry))
				blocked.save_png(output.path_join(label+".png"))
		target.free()
		await process_frame
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if "--motion" in OS.get_cmdline_user_args(): await moving_occlusion(game,kit,protected)
	game.free()
	quit(1 if failures else 0)

func moving_occlusion(game: Node3D,kit: Node,point: Vector3) -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var body = VEHICLE.new()
	body.archetype = "union_sedan"
	body.position = Vector3(6,.1,-7)
	game.add_child(body)
	body.set_physics_process(false)
	kit.headlights_on = false
	kit._refresh()
	var dark := brightness(await picture(),point)
	kit.headlights_on = true
	kit._refresh()
	var driver := MovingBody.new()
	driver.vehicle = body
	game.add_child(driver)
	var frames: Array = []
	var leaks := 0
	var dark_frames := 0
	var covered := 0
	var open := 0
	var start := Time.get_ticks_usec()
	while driver.elapsed < 32.0:
		await RenderingServer.frame_post_draw
		var gain := brightness(root.get_texture().get_image(),point)-dark
		var x: float = body.position.x
		if absf(x)<.5:
			covered += 1
			if gain>.025: leaks += 1
		if absf(x)>5.5:
			open += 1
			if gain<.08: dark_frames += 1
		frames.append({"us":Time.get_ticks_usec()-start,"x":x,"yaw":body.rotation.y,"receiver_gain":gain})
	check(covered>30 and leaks==0,"moving body blocks light every sampled covered frame")
	check(open>120 and dark_frames==0,"moving body restores steady light after clearing beam")
	FileAccess.open(OUT.path_join("motion.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":frames,"covered_frames":covered,"leaking_frames":leaks,"open_frames":open,"unexpected_dark_frames":dark_frames},"\t"))
	print("MOVING_BODY covered=",covered," leaks=",leaks," open=",open," dark=",dark_frames)
	body.free()
