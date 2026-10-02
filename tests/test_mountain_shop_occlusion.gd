extends SceneTree
## Rendered native player silhouette, with the same blocking furniture hidden as
## positive control. Headless cannot certify this test.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const ACTOR = preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var folder := "res://evidence/mountain-shops-20261002/occlusion"

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("SHOP_OCCLUSION PASS " if ok else "SHOP_OCCLUSION FAIL ") + label)
	if not ok: failures.append(label)

func capture(label: String) -> int:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(label + ".png"))
	var pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.r > .75 and color.b > .75 and color.g < .25: pixels += 1
	return pixels

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(960, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	stage.add_child(camera)
	camera.position = Vector3(0, 18, 15)
	camera.look_at(Vector3(0, .7, 0))
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	stage.add_child(sun)
	for id in ["mountain_outfitters", "mountain_boutique", "mountain_village_outfitters"]:
		var room = PLACES.create_place(id)
		stage.add_child(room)
		for is_player in [true, false]:
			var actor = ACTOR.new()
			actor.is_player = is_player
			actor.input_locked = true
			stage.add_child(actor)
			actor.set_physics_process(false)
			await physics_frame
			if not is_player:
				var old_model: Node = actor.visual.get_child(0)
				actor.visual.remove_child(old_model)
				old_model.free()
				actor.visual.add_child(preload("res://world/places/OriginalResidents.gd").create_model(room.definition.npcs[0]))
			var role: String = "player" if is_player else "staff"
			var silhouette := StandardMaterial3D.new()
			silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			silhouette.albedo_color = Color(1, 0, 1)
			for mesh in actor.find_children("*", "MeshInstance3D", true, false): mesh.material_override = silhouette
			# Keep the identical pose for the visible/hidden furniture pair: idle
			# animation must not change the silhouette between control captures.
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			var counter: Vector2 = room.model.counter
			var blockers: Array[Node3D] = []
			for mesh in room.model.find_children("*", "MeshInstance3D", true, false):
				if str(mesh.get_meta("interior_solid_id", "")) == "Checkout": blockers.append(mesh)
			var side_x := counter.x - 2.0 if counter.x > 0 else counter.x + 2.0
			var poses := {"front": Vector3(counter.x, 0, counter.y + 1.15), "back": Vector3(counter.x, 0, -3.85), "side": Vector3(side_x, 0, counter.y)}
			for pose in poses:
				actor.teleport(room.to_global(poses[pose]))
				var visible := await capture(id + "-" + role + "-" + pose)
				for mesh in blockers: mesh.hide()
				var control := await capture(id + "-" + role + "-" + pose + "-control")
				for mesh in blockers: mesh.show()
				check(control > 100, id + " " + role + " " + pose + " positive visible control pixels=" + str(control))
				if pose == "back": check(visible < control * .96 and visible > 0, id + " " + role + " furniture partially occludes legs %d/%d" % [visible, control])
				else: check(visible > control * .85, id + " " + role + " " + pose + " remains visible %d/%d" % [visible, control])
			actor.queue_free()
		room.queue_free()
		await process_frame
	print("SHOP_OCCLUSION failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
