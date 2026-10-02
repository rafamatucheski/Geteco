extends "res://tests/test_vertice_depth.gd"
const DEST := "res://evidence/port-lockpick-20260928/depth"
var output_dir := DEST
var cache_warm := false
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	cache_warm = "--cache-warm" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="): output_dir = argument.trim_prefix("--out-dir=")
	if output_dir.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	viewport = SubViewport.new()
	viewport.size = Vector2i(640,480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	if cache_warm:
		var primer := preload("res://world/regions/LootablePortContainer.gd").new()
		stage.add_child(primer)
		primer.build(Vector3.ZERO,Vector2(20.625,4.0625))
		# O primeiro corpo aquece a mesma chave. Deixa as fontes queued saírem
		# e remove o corpo antes de capturar a segunda instância independente.
		await process_frame
		primer.free()
	var cargo := preload("res://world/regions/LootablePortContainer.gd").new()
	stage.add_child(cargo)
	cargo.build(Vector3.ZERO,Vector2(20.625,4.0625))
	var roof_batches := {}
	preload("res://world/city_look/CityChunkDressing.gd")._other_roofs(stage,roof_batches)
	check(roof_batches.is_empty(),"City dressing does not add a second static roof above walk-in cargo")
	cargo.apply_state({"opened":true,"looted":false})
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	stage.add_child(camera)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for cycle in 3:
		cargo.apply_state({"opened":true,"looted":false,"cycle":cycle})
		var chest: Vector3 = cargo.contents.position
		for player in [true,false]:
			var actor := ACTOR.new()
			actor.is_player = player
			stage.add_child(actor)
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			mask_meshes(actor.visual,diagnostic)
			var who := ("player" if player else "npc")+"-layout-"+str(cycle)
			# Look along the aisle at the chest, then from the outside at a solid wall.
			for setup in [
				{"id":"chest","camera":chest+Vector3(5,2.5,0),"target":chest+Vector3(0,.7,0),"front":chest+Vector3(1.2,.03,0),"behind":chest+Vector3(-.95,.03,0),"side":chest+Vector3(0,.03,1.1 if chest.z < 0 else -1.1)},
				{"id":"wall","camera":Vector3(0,2,8),"target":Vector3(0,1,0),"front":Vector3(0,.03,3),"behind":Vector3(0,.03,0),"side":Vector3(0,.03,3)}]:
				camera.position = setup.camera
				camera.look_at(setup.target)
				for pose in ["front","behind","side"]:
					actor.position = setup[pose]
					cargo.show()
					var actual := await capture()
					cargo.hide()
					var control := await capture()
					var count := mask_count(control)
					var ratio := float(mask_count(actual))/maxf(1,count)
					check(count > 150,who+" "+setup.id+" "+pose+" positive control")
					check(ratio > .9 if pose != "behind" else (ratio < .1 if setup.id == "wall" else ratio > .1 and ratio < .9),who+" "+setup.id+" "+pose+" depth ratio="+str(ratio))
					actual.save_png(output_dir+"/"+who+"-"+setup.id+"-"+pose+".png")
					cargo.show()
			actor.free()
	# Explicitly test Mobile renderer fade and restoration, not just state flags.
	camera.position = Vector3(15,18,15)
	camera.look_at(Vector3.ZERO)
	cargo.set_revealed(true,camera)
	await create_timer(.4).timeout
	var roof_meshes := cargo.roof.find_children("*","MeshInstance3D",true,false)
	check(not roof_meshes.is_empty(),"Roof includes actual meshes")
	for mesh in roof_meshes: check(not mesh.visible,"Occupied roof is actually hidden in Mobile")
	cargo.set_revealed(false,camera)
	await create_timer(.4).timeout
	for mesh in roof_meshes:
		check(mesh.visible and is_equal_approx(mesh.material_override.albedo_color.a,1) and mesh.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,"Exterior restores opaque roof")
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cache_warm":cache_warm}))
	print("PORT_CONTAINER_DEPTH: ",checks," checks; failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
