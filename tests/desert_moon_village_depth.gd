extends "res://tests/test_vertice_depth.gd"
## Positive-control depth coverage for outdoor seats under the native camera.
const VILLAGE := preload("res://world/desert/DesertMoonVillage.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var destination := "res://evidence/desert-moon-village/depth"

func run() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("Village depth exceeded finite 120s budget"); quit(2))
	if DisplayServer.get_name()=="headless":
		push_error("Village depth requires rendered .NET Godot")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): destination=arg.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,480)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.position=-VILLAGE.CENTER
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	G.box(stage,"Ground",VILLAGE.CENTER+Vector3(0,-.1,0),Vector3(110,.2,110),Color("b9a079"),true)
	var art := Node3D.new()
	stage.add_child(art)
	for record in VILLAGE.records(): VILLAGE.build_record(art,record.data)
	VILLAGE.build_collision(stage,VILLAGE.BOUNDS)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("b9a079")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=.7
	environment.environment=settings
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-48,-30,0)
	light.light_energy=1.0
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8
	camera.far=150
	camera.current=true
	stage.add_child(camera)
	var mask := StandardMaterial3D.new()
	mask.albedo_color=Color(1,0,1)
	mask.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	await physics_frame
	var setups := [
		{"id":"courtyard_bench","camera":Vector3(-524,5,-828),"target":Vector3(-538,.8,-828),"front":Vector3(-536.6,.07,-828),"behind":Vector3(-539.1,.07,-828),"side":Vector3(-538,.07,-826)},
		# Foundation ends at x=-545.86; bench back starts at x=-545.13.
		# The 0.60 m capsule fits at the middle of this real 0.73 m gap.
		{"id":"porch_bench","camera":Vector3(-532.77,4.5,-838.92),"target":Vector3(-544.77,.8,-838.92),"front":Vector3(-543.35,.07,-838.92),"behind":Vector3(-545.50,.07,-838.92),"side":Vector3(-544.77,.07,-840.92)},
	]
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
		actor.position=setups[0].front
		camera.position=setups[0].camera
		camera.look_at(stage.to_global(setups[0].target))
		var natural := await capture()
		natural.save_png(destination.path_join(who+"-natural.png"))
		mask_meshes(actor.visual,mask)
		for setup in setups:
			camera.position=setup.camera
			camera.look_at(stage.to_global(setup.target))
			for pose in ["front","behind","side"]:
				actor.position=setup[pose]
				check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" "+setup.id+" "+pose+" has physical clearance")
				actor.reset_physics_interpolation()
				art.show()
				var shown := await capture()
				var visible_count := mask_count(shown)
				art.hide()
				var control := await capture()
				var control_count := mask_count(control)
				art.show()
				var ratio := float(visible_count)/maxf(float(control_count),1.0)
				var id: String=who+"-"+setup.id+"-"+pose
				check(control_count>150,id+" unoccluded actor is visible")
				if pose=="behind": check(ratio<.9,id+" bench occludes lower body "+str(ratio))
				else: check(ratio>.9,id+" front/side actor stays visible "+str(ratio))
				shown.save_png(destination.path_join(id+".png"))
				control.save_png(destination.path_join(id+"-control.png"))
				records.append({"id":id,"ratio":ratio,"visible":visible_count,"control":control_count})
		actor.free()
	var report := FileAccess.open(destination.path_join("results.json"),FileAccess.WRITE)
	if report: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"\t"))
	stage.free()
	viewport.free()
	print("DESERT_MOON_VILLAGE_DEPTH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
