extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	var stage:=Node3D.new()
	root.add_child(stage)
	current_scene=stage
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("303c42")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=.65
	environment.environment=settings
	stage.add_child(environment)
	var lamp:=DirectionalLight3D.new()
	lamp.rotation_degrees=Vector3(-50,-40,0)
	stage.add_child(lamp)
	for side in [-1,1]:
		var actor:=preload("res://gameplay/urban_v1/CobraLocalGuard.gd").new()
		actor.position=Vector3(side*.6,0,0)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.visual.rotation.y=PI if side==1 else 0
	var car:=preload("res://scripts/Vehicle.gd").new()
	car.archetype="cobra_v8"
	car.vehicle_id="cobra_patrol_preview"
	car.paint_color=Color("202d26")
	car.position=Vector3(3,0,1)
	car.rotation.y=-.3
	stage.add_child(car)
	car.set_physics_process(false)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=7
	camera.position=Vector3(4,4,-7)
	stage.add_child(camera)
	camera.look_at(Vector3(1.3,.6,0))
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/cobra-neighborhood-1002/uniform-preview.png")
	quit()
