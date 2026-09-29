extends SceneTree
## Quadros-chave da entrada e da saída pela porta, com o corpo do Dante (renderizado).
## Uso: --script res://tests/capture/capture_boarding_doors.gd -- [entry|exit] [side] [zoom=.6] id [id ...]
## Saída: res://evidence/vehicle-doors/boarding_<modo>_<id>_<lado>_<n>.png
const OUTPUT := "res://evidence/vehicle-doors/"
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const BOARDING := preload("res://gameplay/VehicleBoardingPresentation.gd")
const FRAMES := 8

var stage: Node3D
var camera: Camera3D

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(960, 540)
	stage = Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.55, .6, .66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7, .72, .78)
	env.environment.ambient_light_energy = .8
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(.32, .32, .33)
	ground.material_override = ground_material
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.fov = 38
	stage.add_child(camera)
	var actor := ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	var args: Array = Array(OS.get_cmdline_user_args())
	var mode: String = args.pop_front() if not args.is_empty() else "entry"
	var side := int(args.pop_front()) if not args.is_empty() else -1
	var zoom := 1.0
	var ids: Array = []
	for argument in args:
		if str(argument).begins_with("zoom="): zoom = float(str(argument).substr(5))
		else: ids.append(argument)
	for id in ids:
		var car := VEHICLE.new()
		car.archetype = id
		car.paint_color = Color("b04a3c")
		stage.add_child(car)
		car.set_physics_process(false)
		car.global_position = Vector3(0, .04, 0)
		await process_frame
		var layout: Dictionary = car.door_layout(side)
		if layout.is_empty():
			print("SEM PORTA ", id)
			car.queue_free()
			continue
		var start: Vector3 = car.to_global(Vector3(float(side) * (car.half_width + .55), 0, car._cab_z() + .2))
		start.y = car.global_position.y
		actor.global_position = start
		actor.show()
		var transition = BOARDING.new()
		stage.add_child(transition)
		if mode == "exit":
			transition.begin_exit(stage, car, actor, car.to_global(Vector3(layout.stand.x, 0.0, layout.stand.z)), side)
		else:
			transition.begin_entry(stage, car, actor, side)
		if is_instance_valid(transition._motion): transition._motion.kill()
		transition.set_process(false)
		var focus: Vector3 = car.to_global(Vector3(float(side) * (car.half_width + .2), .9, car._cab_z()))
		for frame in FRAMES:
			var t := (float(frame) + .5) / FRAMES
			transition.progress = 1.0 - t if mode == "exit" else t
			transition._apply()
			camera.position = focus + Vector3(float(side) * 3.6, 2.6, 2.4) * zoom
			camera.look_at(focus, Vector3.UP)
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + "boarding_%s_%s_%d_%d.png" % [mode, id, side, frame]))
		transition.abort("capture_done")
		car.queue_free()
		await process_frame
		print("CAPTURE boarding ", mode, " ", id)
	quit(0)
