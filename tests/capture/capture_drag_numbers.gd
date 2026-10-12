extends SceneTree
## Rear-glass registration fit across the desert fleet.
## Isolated art inspection; integrated gameplay/performance use test_drag_open_meet.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var output := ""
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	output="res://evidence/drag-numbers-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1440,900)
	var scene:=Node3D.new()
	root.add_child(scene)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("b5a184")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("c0ccdf")
	env.environment.ambient_light_energy=.72
	scene.add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,35,0)
	sun.light_color=Color("ffe7c3")
	sun.light_energy=1.25
	sun.shadow_enabled=true
	scene.add_child(sun)
	var ground:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	shape.shape=BoxShape3D.new()
	shape.shape.size=Vector3(150,.2,150)
	shape.position.y=-.1
	ground.add_child(shape)
	var mesh:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(150,150)
	mesh.mesh=plane
	var finish:=StandardMaterial3D.new()
	finish.albedo_color=Color("454b50")
	finish.roughness=.86
	mesh.material_override=finish
	ground.add_child(mesh)
	scene.add_child(ground)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4.0
	scene.add_child(camera)
	camera.make_current()
	for id in CARS.IDS:
		var car:=VEHICLE.new()
		car.archetype=id
		car.vehicle_id="style_review_"+id
		car.paint_color=Color(str(CARS.spec(id).color))
		scene.add_child(car)
		car.set_physics_process(false)
		car.position=Vector3(0,.04,0)
		for i in 12:
			car.velocity=Vector3.DOWN
			car.move_and_slide()
			await physics_frame
		preload("res://activities/desert_drag/DragOpenRoster.gd").attach_number(car,27)
		camera.position=Vector3(1.8,2.4,6)
		camera.look_at(Vector3(0,.95,.8))
		camera.size=2.7
		await create_timer(.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(id+"-number.png"))
		car.free()
	print("NUMBER_CAPTURE ",output)
	quit()
