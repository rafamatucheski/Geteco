extends SceneTree
## Showroom photograph of the production ice-cream attachment and saved courier.
## Not a driving test or performance capture.
class PhotoVan extends CharacterBody3D:
	var visual: Node3D
	var archetype := "courier_van"
	var vehicle_id := "street_icecream_photo"
	var traffic := true
	var controlled := false
	var health := 100.0
	var engine_disabled := false

func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1600,1000)
	Engine.max_fps=60
	var folder:="res://evidence/fleet-redesign-20261011/utility/icecream"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var world:=Node3D.new()
	root.add_child(world)
	var environment:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("86969e")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c4d4de")
	env.ambient_light_energy=.65
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=env
	world.add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_color=Color("ffe2b8")
	sun.light_energy=1.6
	sun.shadow_enabled=true
	world.add_child(sun)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(200,200)
	ground.mesh=plane
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("545c60")
	mat.roughness=.88
	ground.material_override=mat
	world.add_child(ground)
	var camera:=Camera3D.new()
	camera.fov=34
	camera.near=.05
	world.add_child(camera)
	camera.make_current()
	var car:=PhotoVan.new()
	world.add_child(car)
	car.visual=preload("res://runtime/FleetCatalog.gd").create("courier_van")
	car.add_child(car.visual)
	var paint:=preload("res://runtime/VehiclePaint.gd").new()
	paint.bind(car.visual,"courier_van")
	paint.apply(Color.WHITE)
	var ambient:=AudioServer.get_bus_index("Ambient")
	if ambient>=0: AudioServer.set_bus_mute(ambient,true)
	preload("res://gameplay/icecream/IceCreamVan.gd").attach(car)
	for view in [{"id":"front","at":Vector3(-6.6,3.2,-7.8),"target":Vector3(0,1.23,0)}, {"id":"rear","at":Vector3(6.6,3.2,7.8),"target":Vector3(0,1.23,0)}, {"id":"roof","at":Vector3(-3.5,3.2,-3.3),"target":Vector3(0,2.02,.5)}]:
		camera.position=view.at
		camera.look_at(view.target)
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+str(view.id)+".png")
	print("ICECREAM_PHOTO ",folder)
	world.free()
	quit()
