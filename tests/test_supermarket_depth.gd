extends "res://tests/test_vertice_depth.gd"
const MARKET := preload("res://world/places/supermarket/SupermarketPlace.gd")
var folder := "res://evidence/supermarket-20261002/depth"
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var market := MARKET.new()
	market.definition = MARKET.definition_data()
	stage.add_child(market)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = market.camera_size
	stage.add_child(camera)
	camera.position = market.camera_target+Vector3(0,18,15)
	camera.look_at(market.camera_target)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		mask_meshes(actor.visual,diagnostic)
		var who := "player" if player else "npc"
		for setup in [
			{"id":"gondola-front","point":Vector3(-1.6,.04,2.7),"behind":false},
			{"id":"gondola-back","point":Vector3(-1.6,.04,-4.0),"behind":true},
			{"id":"gondola-side","point":Vector3(0,.04,0),"behind":false},
			{"id":"checkout-front","point":Vector3(-5.4,.04,6.15),"behind":false},
			{"id":"checkout-back","point":Vector3(-5.4,.04,2.55),"behind":true},
			{"id":"checkout-side","point":Vector3(-4.15,.04,4.4),"behind":false}]:
			actor.position = setup.point
			actor.reset_physics_interpolation()
			market.show()
			var rendered := await capture()
			market.hide()
			var control := await capture()
			market.show()
			var pixels := mask_count(control)
			var ratio := float(mask_count(rendered))/maxf(pixels,1)
			check(pixels>100,who+" "+setup.id+" positive visible control")
			check(ratio>.9 if not setup.behind else ratio>.05 and ratio<.9,who+" "+setup.id+" correct depth ratio="+str(ratio))
			rendered.save_png(folder.path_join(who+"-"+setup.id+".png"))
			records.append({"actor":who,"pose":setup.id,"ratio":ratio,"control_pixels":pixels})
		actor.free()
	FileAccess.open(folder.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"\t"))
	stage.free()
	viewport.free()
	print("MARKET_DEPTH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
