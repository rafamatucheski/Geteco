extends SceneTree
const ACTOR := preload("res://scripts/Actor.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
const RESIDENT := preload("res://world/places/sewers/SewerResident.gd")
var viewport: SubViewport
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func capture() -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func mask_count(picture: Image) -> int:
	var count := 0
	for y in picture.get_height():
		for x in picture.get_width():
			var color := picture.get_pixel(x,y)
			if color.r > .55 and color.b > .55 and color.g < .2: count += 1
	return count
func mask_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.material_overlay = null
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): mask_meshes(child,material)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute("res://output/sewer-refresh/depth")
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for id in NETWORK.ids():
		var room = CATALOG.create_place(id)
		stage.add_child(room)
		# Isolate depth from the separate darkness CanvasLayer: its color tint must
		# not be mistaken for an occluded magenta diagnostic actor.
		for overlay in room.find_children("*","CanvasLayer",true,false):
			overlay.process_mode = Node.PROCESS_MODE_DISABLED
			overlay.hide()
		camera.size = room.camera_size
		camera.position = room.camera_target + Vector3(0,18,15)
		camera.look_at(room.camera_target)
		var prop: MeshInstance3D
		var selected_height := 0.0
		var bounds := AABB()
		var side_point := Vector3.ZERO
		for mesh in room.model.find_children("*","MeshInstance3D",true,false):
			var box: AABB = mesh.transform * mesh.get_aabb()
			if box.position.y > .8 or box.end.y < .35 or box.end.y > 1.3: continue
			if box.size.x < .5 or box.size.z < .4 or box.size.x > 4 or box.size.z > 3: continue
			var footprint := box
			for solid in room.solid_bounds:
				if Rect2(solid.position.x,solid.position.z,solid.size.x,solid.size.z).grow(.002).encloses(Rect2(box.position.x,box.position.z,box.size.x,box.size.z)):
					footprint = solid
					break
			if footprint.size.x > 4 or footprint.size.z > 3: continue
			if absf(footprint.position.z-.31) > room.definition.size.y*.5-.3: continue
			if absf(footprint.end.z+.31) > room.definition.size.y*.5-.3: continue
			var center: Vector3 = footprint.get_center()
			if not room.is_floor_clear(Vector3(center.x,0,footprint.position.z-.31),.3): continue
			if not room.is_floor_clear(Vector3(center.x,0,footprint.end.z+.31),.3): continue
			var side := Vector3(footprint.end.x+.31,.04,center.z)
			if not room.is_floor_clear(side,.3): side = Vector3(footprint.position.x-.31,.04,center.z)
			if not room.is_floor_clear(side,.3): continue
			if prop != null and box.end.y <= selected_height: continue
			prop = mesh
			selected_height = box.end.y
			bounds = footprint
			side_point = side
		check(prop != null, id + " objeto com frente/atrás acessíveis")
		if prop == null: room.free(); continue
		for player in [true,false]:
			var actor: CharacterBody3D
			if player:
				actor = ACTOR.new()
				actor.is_player = true
			else:
				actor = RESIDENT.new()
				actor.definition = room.definition.npcs[0]
			stage.add_child(actor)
			actor.set_physics_process(false)
			for i in 12: await process_frame
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			mask_meshes(actor.visual, diagnostic)
			var who := "dante" if player else "resident"
			var ratios := {}
			for setup in [
				{"id":"behind", "point":Vector3(bounds.get_center().x,.04,bounds.position.z-.31)},
				{"id":"front", "point":Vector3(bounds.get_center().x,.04,bounds.end.z+.31)},
				{"id":"side", "point":side_point}]:
				actor.position = setup.point
				actor.reset_physics_interpolation()
				var actual := await capture()
				room.hide()
				var control := await capture()
				room.show()
				var pixels := mask_count(control)
				var ratio := float(mask_count(actual))/maxi(1,pixels)
				ratios[setup.id] = ratio
				check(pixels > 35, id + " " + who + " " + setup.id + " controle positivo")
				check(ratio > .2, id + " " + who + " " + setup.id + " ator legível " + str(ratio))
				actual.save_png("res://output/sewer-refresh/depth/%s-%s-%s.png" % [id,who,setup.id])
			check(ratios.front > .8 and ratios.behind < ratios.front, id + " " + who + " profundidade real do móvel")
			actor.free()
		room.free()
	FileAccess.open("res://output/sewer-refresh/depth/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("SEWER_DEPTH checks=", checks, " failures=", failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
