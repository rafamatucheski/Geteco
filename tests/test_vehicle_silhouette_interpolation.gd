extends SceneTree
## The self-occlusion bounds must follow the rendered body, including turns.
class SilhouetteLook extends "res://world/city_look/CityLook.gd":
	# Only the production silhouette lifecycle is under test; skip unrelated
	# reflection viewports and city lighting startup.
	func _ready() -> void: pass
class Driving extends RefCounted:
	var occupied := true
	var car: Node3D
	var transition = null
class World extends Node3D:
	var player: Node3D
	var driving := Driving.new()
class Controller extends RefCounted:
	var world: World
	var session = null
	var state := {"place_id":""}
class MovingCar extends Node3D:
	func _physics_process(delta: float) -> void:
		position.z -= 60.0*delta
		rotation.y += .4*delta
var world: World
var look: Node
var samples := 0
var mismatches := 0
var max_gap := 0.0
var camera: Camera3D
var visual_output := ""
var sequence: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = World.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var car := MovingCar.new()
	world.add_child(car)
	world.driving.car = car
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	car.add_child(body)
	if "--visual" in OS.get_cmdline_user_args():
		body.free()
		car.add_child(preload("res://scripts/VehicleVisual.gd").create(Color("303d48")))
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("282d32")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = .8
		world.add_child(environment)
		camera = Camera3D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		world.add_child(camera)
		camera.make_current()
		root.size = Vector2i(640,360)
		root.msaa_3d = Viewport.MSAA_4X
		Engine.max_fps = 30
		visual_output = "res://evidence/vehicle-silhouette-isolated-%d"%OS.get_process_id()
		DirAccess.make_dir_recursive_absolute(visual_output)
	look = SilhouetteLook.new()
	world.add_child(look)
	look.set_process(false)
	var controller := Controller.new()
	controller.world = world
	look.controller = controller
	look._refresh_silhouette()
	# Prime interpolation before collecting assertions.
	car.get_global_transform_interpolated()
	for i in 4: await physics_frame
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < (36000 if camera!=null else 2000):
		await process_frame
		inspect()
		if camera!=null:
			var pose := car.get_global_transform_interpolated()
			camera.global_position = pose*Vector3(7,3,7)
			camera.look_at(pose*Vector3(0,.8,0))
			var legacy := Time.get_ticks_msec()-began<4000
			if legacy:
				look._silhouettes[car].set_shader_parameter("target_inverse",Projection(car.global_transform.affine_inverse()))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(visual_output.path_join("%05d.jpg"%sequence.size()),.95)
			sequence.append({"legacy":legacy,"render_frame":Engine.get_frames_drawn(),"us":Time.get_ticks_usec()})
	var passed := samples>30 and max_gap>.08 and mismatches==0
	print("VEHICLE_SILHOUETTE_INTERPOLATION samples=",samples," mismatches=",mismatches," max_physics_render_gap_m=",max_gap," pass=",passed)
	if not visual_output.is_empty():
		FileAccess.open(visual_output.path_join("sequence.json"),FileAccess.WRITE).store_string(JSON.stringify(sequence))
		print("VEHICLE_SILHOUETTE_ISOLATED ",ProjectSettings.globalize_path(visual_output)," (visual only; not Main or a performance benchmark)")
	world.free()
	quit(0 if passed else 1)

func inspect() -> void:
	look._follow_silhouettes()
	var car: Node3D = world.driving.car
	var pose := car.get_global_transform_interpolated()
	max_gap = maxf(max_gap,car.global_position.distance_to(pose.origin))
	var material: ShaderMaterial = look._silhouettes[car]
	var actual: Projection = material.get_shader_parameter("target_inverse")
	var expected := Projection(pose.affine_inverse())
	if not (actual.x.is_equal_approx(expected.x) and actual.y.is_equal_approx(expected.y) and actual.z.is_equal_approx(expected.z) and actual.w.is_equal_approx(expected.w)): mismatches += 1
	samples += 1
