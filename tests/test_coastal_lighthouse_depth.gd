extends "res://tests/test_vertice_depth.gd"
## Rigs reais de ator e os materiais de produção do farol. Os controles com a arquitetura
## escondida distinguem atores visíveis de um corte que esconde tudo.
const SITE = preload("res://world/places/coastal_lookout/CoastalLookout.gd")
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	create_timer(100).timeout.connect(func(): quit(3))
	var folder := FIXTURE.output_dir("coastal-lighthouse-depth")
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var site := SITE.new()
	stage.add_child(site)
	# Misturar primitivas indexadas de append_from com triângulos manuais deixava antes
	# a cúpula curva inteira órfã enquanto as nervuras ainda renderizavam.
	var roof := site.get_node("Lighthouse_lighthouse_roof") as MeshInstance3D
	var roof_arrays := roof.mesh.surface_get_arrays(0)
	check(roof_arrays[Mesh.ARRAY_INDEX]==null or roof_arrays[Mesh.ARRAY_INDEX].is_empty(),"Curved roof and primitive details share non-indexed batches")
	check(roof_arrays[Mesh.ARRAY_VERTEX].size()>3000,"Curved roof faces remain in the rendered batch")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = preload("res://scripts/CameraRig.gd").WALK_SIZE_CLOSE
	stage.add_child(camera)
	camera.make_current()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1,0,1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var points: Array[Vector3] = []
	var route := SITE.lighthouse_route_points()
	for i in range(0,route.size(),maxi(1,int(route.size()/12.0))): points.append(route[i])
	points.append(SITE.summit_position())
	points.append(SITE.binocular_interaction_position())
	var revealed := 0
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		for frame in 15: await process_frame
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		mask_meshes(actor.visual,material)
		var who := "player" if is_player else "npc"
		for i in points.size():
			actor.position = points[i]+Vector3.UP*.04
			actor.reset_physics_interpolation()
			camera.position = actor.position+Vector3(0,25.3,25.3)
			camera.look_at(actor.position)
			site.configure_lighthouse_player(null)
			var opaque := await capture()
			site.configure_lighthouse_player(actor)
			var actual := await capture()
			site.hide()
			var control := await capture()
			site.show()
			var total := mask_count(control)
			var shown := mask_count(actual)
			var blocked := mask_count(opaque)
			var ratio := float(shown)/maxi(total,1)
			check(total>40,who+" positive actor control at "+str(i))
			check(ratio>.65,who+" readable during climb at %d ratio=%.3f"%[i,ratio])
			if shown>blocked+20: revealed+=1
			records.append({"who":who,"index":i,"point":str(points[i]),"opaque":blocked,"actual":shown,"control":total,"ratio":ratio})
			actual.save_png(folder.path_join("%s-%02d.png"%[who,i]))
			if ratio<.65: opaque.save_png(folder.path_join("%s-%02d-opaque.png"%[who,i]))
		actor.free()
	check(revealed>0,"local cutaway reveals real architectural occlusion")
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	print("COASTAL_LIGHTHOUSE_DEPTH ",folder," checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
