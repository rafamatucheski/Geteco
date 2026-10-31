extends "res://tests/test_vertice_depth.gd"
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const DEST := "res://output/culvert-review-20261011/depth"
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node3D.new()
	scene.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(scene)
	var room = PLACES.create_place("desert_under_culvert")
	scene.add_child(room)
	# Desliga só o clima de espaço de tela nesta fixture de diagnóstico com máscara de cor.
	# As capturas do Main mantêm o clima e a iluminação de produção.
	for child in room.model.get_children():
		if child is CanvasLayer:
			child.set_process(false)
			child.hide()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.5
	scene.add_child(camera)
	camera.position = Vector3(12,18.7,15)
	camera.look_at(Vector3(12,.7,0))
	camera.current = true
	var mask := StandardMaterial3D.new()
	mask.albedo_color = Color(1,0,1)
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		scene.add_child(actor)
		actor.set_physics_process(false)
		await physics_frame
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var who := "player" if is_player else "npc"
		actor.position = Vector3(12.6,.04,.8)
		check(actor.test_move(actor.global_transform, Vector3(0,0,2)), who+" swept bench collision")
		actor.position = Vector3(14.3,.04,.8)
		check(not actor.test_move(actor.global_transform, Vector3(0,0,2)), who+" passage beside bench")
		mask_meshes(actor.visual,mask)
		for pair in [["front",Vector3(12.6,.04,2.9)],["behind",Vector3(12.6,.04,1.24)],["side",Vector3(14.3,.04,2)]]:
			actor.position = pair[1]
			actor.reset_physics_interpolation()
			room.show()
			var rendered := await capture()
			var visible_pixels := mask_count(rendered)
			rendered.save_png(DEST.path_join(who+"-"+pair[0]+".png"))
			room.hide()
			var control := await capture()
			var full_pixels := mask_count(control)
			check(full_pixels > 150,who+" "+pair[0]+" positive visibility control")
			var ratio := float(visible_pixels)/maxf(1.0,float(full_pixels))
			if pair[0] == "behind": check(ratio > .05 and ratio < .95,who+" legs occluded behind bench, upper body visible: "+str(ratio))
			else: check(ratio > .9,who+" visible "+pair[0]+": "+str(ratio))
			room.show()
		actor.free()
	print("CULVERT_DEPTH checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
