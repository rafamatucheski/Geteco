extends "res://tests/test_vertice_depth.gd"
## Reuses the real rig mask/capture helper. This is a physical/depth fixture;
## the integrated Main run and streaming performance are measured separately.
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const SITES := preload("res://world/desert/expansion/DesertRelicsSites.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var destination := "res://evidence/desert-expansion-20261006/relic-depth"

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Relic depth requires the rendered .NET engine")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): destination=argument.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	viewport=SubViewport.new()
	viewport.size=Vector2i(960,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	G.box(stage,"Ground",Vector3(0,-.1,0),Vector3(100,.2,100),Color("b9a079"),true)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("c9b797")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=.72
	environment.environment=settings
	stage.add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees=Vector3(-48,-30,0)
	sunlight.light_energy=1.0
	stage.add_child(sunlight)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=150
	camera.current=true
	stage.add_child(camera)
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for location in RELICS.locations():
		var site := SITES.build(stage,location.id,Vector3.ZERO,613)
		await physics_frame
		for player in [true,false]:
			var actor := ACTOR.new()
			actor.is_player=player
			actor.controlled_automatically=true
			actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			stage.add_child(actor)
			actor.set_physics_process(false)
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			await physics_frame
			var who := "player" if player else "npc"
			# Long swept moves exercise actual collision response, not just probes.
			for solid in location.solids:
				actor.position=solid.start
				var collision := actor.move_and_collide(solid.motion)
				check(collision!=null,who+" "+location.id+" blocks "+solid.id)
				check(actor.position.distance_to(solid.start)<Vector3(solid.motion).length()-.25,who+" "+solid.id+" cannot tunnel through solid")
			actor.position=Vector3(location.approach[0])+Vector3(0,.04,0)
			check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" "+location.id+" entry has full-body clearance")
			for i in range(1,location.approach.size()):
				var target: Vector3=location.approach[i]+Vector3(0,.04,0)
				var collision := actor.move_and_collide(target-actor.position)
				check(collision==null and actor.position.distance_to(target)<.025,who+" "+location.id+" cache route segment "+str(i)+" is walkable")
			check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" "+location.id+" cache approach has full-body clearance")
			camera.size=float(location.camera_size)
			camera.position=Vector3(0,34,28)
			camera.look_at(Vector3(0,1,0))
			actor.reset_physics_interpolation()
			var natural := await capture()
			check(natural.save_png(destination.path_join(who+"-"+location.id+"-natural.png"))==OK,who+" "+location.id+" natural evidence")
			mask_meshes(actor.visual,diagnostic)
			for setup in _depth_setups(location.id):
				camera.size=13
				camera.position=setup.camera
				camera.look_at(setup.target)
				for pose in ["front","behind","side"]:
					actor.position=setup[pose]
					check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" "+location.id+" "+pose+" depth pose is outside solids")
					actor.reset_physics_interpolation()
					site.show()
					var rendered := await capture()
					var visible_pixels := mask_count(rendered)
					site.hide()
					var control := await capture()
					var control_pixels := mask_count(control)
					site.show()
					var id: String=who+"-"+location.id+"-"+pose
					check(control_pixels>150,id+" visible positive control")
					var ratio := float(visible_pixels)/maxf(float(control_pixels),1.0)
					if pose=="behind": check(ratio<.82,id+" native depth occludes lower/body pixels: "+str(ratio))
					else: check(ratio>.9,id+" front/side body remains visible: "+str(ratio))
					rendered.save_png(destination.path_join(id+".png"))
					control.save_png(destination.path_join(id+"-control.png"))
					records.append({"actor":who,"site":location.id,"pose":pose,"visible_pixels":visible_pixels,"control_pixels":control_pixels,"visible_ratio":ratio})
			actor.free()
		site.free()
		await physics_frame
	var report := FileAccess.open(destination.path_join("results.json"),FileAccess.WRITE)
	check(report!=null,"Relic collision/depth evidence report writable")
	if report: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"records":records},"\t"))
	print("DESERT_RELIC_DEPTH checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _depth_setups(id: String) -> Array[Dictionary]:
	match id:
		"station": return [{"camera":Vector3(0,7,13),"target":Vector3(0,1,-4.2),"front":Vector3(0,.04,-2.8),"behind":Vector3(0,.04,-5.1),"side":Vector3(7.5,.04,-4.2)}]
		"mine": return [{"camera":Vector3(13.2,5,17),"target":Vector3(13.2,.7,6),"front":Vector3(13.2,.04,7.2),"behind":Vector3(13.2,.04,5.2),"side":Vector3(11.6,.04,6)}]
		"wagon": return [{"camera":Vector3(0,7,14),"target":Vector3(0,1,-1.3),"front":Vector3(0,.04,4),"behind":Vector3(0,.04,-2.35),"side":Vector3(7,.04,0)}]
		"wreck": return [{"camera":Vector3(0,7,12),"target":Vector3(0,1,-.2),"front":Vector3(0,.04,3.6),"behind":Vector3(0,.04,-3.1),"side":Vector3(2.6,.04,-.2)}]
	return []
