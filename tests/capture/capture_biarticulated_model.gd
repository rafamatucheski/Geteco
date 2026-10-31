extends SceneTree
## Inspeção externa independente do Main; não certifica FPS de jogo.
const MODEL := preload("res://runtime/transit/BiarticulatedModel.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1440,900)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fadb5")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cadce6")
	env.environment.ambient_light_energy = .65
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42,-35,0)
	sun.light_energy = 1.8; sun.shadow_enabled = true
	scene.add_child(sun)
	MODEL.box(scene,Vector3(0,-.12,7),Vector3(80,.2,80),"floor")
	var models := []
	for index in 3:
		var section := Node3D.new()
		section.position.z = [0.0,7.95,15.4][index]
		scene.add_child(section)
		var result := MODEL.build(section,[7.8,6.8,6.8][index],index)
		assert(result.doors.size()==2,"Two moving door leaves per section")
		assert(result.wheels.size()==(8 if index==0 else 4),"Original wheel transforms preserved")
		assert(is_equal_approx(result.door_z,-[7.8,6.8,6.8][index]*.5+1.2),"Doorway remains in original position")
		models.append(result)
	for z in [4.075,11.525]:
		for rib in 9:
			MODEL.box(scene,Vector3(0,1.72,z+(rib-4)*.08),Vector3(2.39,2.58,.045),"rubber" if rib%2 else "metal")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true; camera.far = 150
	scene.add_child(camera)
	var folder := "res://evidence/biarticulated/model-20261010"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for shot in [
		{"id":"front","position":Vector3(-22,15,-23),"target":Vector3(0,1.4,7),"size":20.0},
		{"id":"rear","position":Vector3(22,13,38),"target":Vector3(0,1.4,7),"size":20.0},
		{"id":"front_detail","position":Vector3(-7,5,-13),"target":Vector3(0,1.6,-2.4),"size":8.5},
		{"id":"rear_detail","position":Vector3(7,5,28),"target":Vector3(0,1.7,17),"size":8.5},
		{"id":"advert","position":Vector3(-14,3.2,7.95),"target":Vector3(0,1.7,7.95),"size":8.5},
		{"id":"doors_open","position":Vector3(23,9,-5),"target":Vector3(0,1.4,7),"size":20.0}]:
		if shot.id=="doors_open":
			for result in models:
				for index in 2: result.doors[index].position.z = result.door_z+(-1 if index==0 else 1)*.93
		camera.size = shot.size
		camera.position = shot.position; camera.look_at(shot.target)
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+shot.id+".png")
	print("BIARTICULATED_MODEL: 9 checks passed; 6 rendered exterior views saved")
	scene.queue_free()
	await process_frame
	quit()
