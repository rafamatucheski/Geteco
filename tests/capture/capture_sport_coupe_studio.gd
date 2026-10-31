extends SceneTree
## Evidência em ângulo correspondente da fábrica de frota de produção, nunca uma imagem conceitual.
var label := "before"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
	var folder := "res://evidence/sport-coupe-redesign/"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size=Vector2i(1600,900)
	var fleet := preload("res://runtime/FleetCatalog.gd")
	if label=="before": fleet.all()["sport_coupe"].scene="res://evidence/sport-coupe-redesign/baseline/sport_coupe.scn"
	elif label=="candidate": fleet.all()["sport_coupe"].scene="res://evidence/sport-coupe-redesign/candidate.scn"
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("86969e")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c4d4de")
	env.ambient_light_energy=.65
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	we.environment=env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_color=Color("ffe2b8")
	sun.light_energy=1.6
	sun.shadow_enabled=true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(200,200)
	ground.mesh=plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color("545c60")
	mat.roughness=.88
	ground.material_override=mat
	world.add_child(ground)
	var model: Node3D=fleet.create("sport_coupe")
	world.add_child(model)
	var camera := Camera3D.new()
	camera.fov=34
	camera.near=.05
	world.add_child(camera)
	camera.make_current()
	for view in [{"id":"front","at":Vector3(-5.7,3.0,-6.7)},{"id":"rear","at":Vector3(5.7,2.9,6.7)},{"id":"side","at":Vector3(8,1.65,0)},{"id":"top","at":Vector3(.1,9,1.0)}]:
		camera.position=view.at
		camera.look_at(Vector3(0,.57,0))
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("studio-"+str(view.id)+".png"))
	print("SPORT_GT_STUDIO ",folder)
	world.free()
	await process_frame
	quit()
