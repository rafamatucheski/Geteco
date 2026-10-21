extends "res://tests/test_vertice_depth.gd"
const PROP := preload("res://activities/desert_drag/DesertDragBoardProp.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(3))
	var dest := "res://evidence/drag-entrance-20261021/fixture"
	DirAccess.make_dir_recursive_absolute(dest)
	viewport=SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("89999d")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=.65
	environment.environment=env
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.shadow_enabled=true
	stage.add_child(sun)
	PROP.build_chunk(stage,Rect2(Vector2(-920,-1320),Vector2(40,40)))
	var board := stage.get_node("DragRivalsBoard")
	board.position=Vector3.ZERO
	G.box(stage,"Ground",Vector3(0,-.10,0),Vector3(30,.2,30),Color("918772"),true)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position=Vector3(9,6,11)
	camera.look_at(Vector3(0,1.4,1))
	camera.fov=50
	camera.current=true
	(await capture()).save_png(dest+"/canopy.png")
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player=player
		actor.controlled_automatically=true
		actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		for frame in 20: await process_frame
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		var who := "player" if player else "npc"
		for point in [Vector3(0,.04,4.5),Vector3(-1.8,.04,3),Vector3(0,.04,2.5)]:
			actor.position=point
			check(not actor.test_move(actor.global_transform,Vector3(0,0,-1.4)),who+" approach and circulation "+str(point))
		for setup in [{"p":Vector3(0,.04,1.2),"d":Vector3(0,0,-2)},{"p":Vector3(2.05,.04,3),"d":Vector3(0,0,-3)},{"p":Vector3(3.1,.04,4.6),"d":Vector3(0,0,-2)},{"p":Vector3(2.9,.04,2.5),"d":Vector3(-1.0,0,-1.0)}]:
			actor.position=setup.p
			check(actor.test_move(actor.global_transform,setup.d),who+" board/counter/post/corner solid "+str(setup.p))
		actor.position=Vector3(-1.6,.04,1.5)
		camera.position=Vector3(4,3,9)
		camera.look_at(Vector3(0,1.3,0))
		(await capture()).save_png(dest+"/"+who+"-inside.png")
		mask_meshes(actor.visual,diagnostic)
		for setup in [{"p":Vector3(0,.04,1.5),"id":"front"},{"p":Vector3(0,.04,-.6),"id":"behind"}]:
			actor.position=setup.p
			camera.position=Vector3(0,1.7,8)
			camera.look_at(Vector3(0,1,0))
			var actual := await capture()
			board.hide()
			var control := await capture()
			board.show()
			var visible := mask_count(actual)
			var unobstructed := mask_count(control)
			check(unobstructed>100,who+" positive depth control "+setup.id)
			check(visible>unobstructed*.8 if setup.id=="front" else visible<unobstructed*.65,who+" board occlusion "+setup.id)
			actual.save_png(dest+"/"+who+"-"+setup.id+".png")
		actor.free()
	FileAccess.open(dest+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("ENTRANCE_FIXTURE ",checks," checks; ",failures)
	stage.free()
	viewport.free()
	quit(0 if failures.is_empty() else 1)
