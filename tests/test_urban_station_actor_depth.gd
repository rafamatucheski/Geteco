extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func shot(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func difference(a: Image, b: Image, region: Rect2i) -> int:
	var count := 0
	region = region.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var p := a.get_pixel(x,y)
			var q := b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)+absf(p.a-q.a)>0.15: count += 1
	return count
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This test requires rendered depth")
		quit(2)
		return
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var station = load("res://world/harbor/urban_transit/UrbanTubeStop.gd").new()
	station.terminal = true
	station.position = Vector2(500,450)
	world.add_child(station)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = station.position
	camera.make_current()
	for identity in [-1,0]:
		var actor = load("res://Player.gd").new() if identity == -1 else load("res://world/harbor/urban_transit/UrbanPassenger.gd").new()
		if identity == -1:
			var follow := Camera2D.new()
			follow.name = "Camera"
			actor.add_child(follow)
		actor.position = Vector2(-1000,-1000)
		world.add_child(actor)
		actor.set_physics_process(false)
		camera.make_current()
		await process_frame
		actor.position = station.to_global(Vector2(-65,-130))
		station._actor_entered(actor)
		var p = station.presentations[actor]
		station.view.on_screen = true
		station.view.request_redraw()
		# Hide other actors' world-independent shadows; compare the same rig and
		# pose with/without foreground architecture, not a permanently hidden actor.
		var foreground: Array[Node] = []
		for mesh in station.view.model.get_children():
			if mesh is MeshInstance3D: foreground.append(mesh)
		check(not foreground.is_empty(), "ticket office provides a real foreground control")
		for location in [Vector2(-65,-130),Vector2(40,-85)]:
			actor.global_position = station.to_global(location)
			p._update_scale()
			var region := Rect2()
			var first := true
			for mesh in actor.model_root.find_children("*","MeshInstance3D",true,false):
				for corner in 8:
					var pixel: Vector2 = station.view.camera_3d.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
					if first:
						region = Rect2(pixel,Vector2.ZERO)
						first = false
					else: region = region.expand(pixel)
			# Ignore unrelated shadow-cache changes elsewhere in the station;
			# the property under test is visibility at the actual actor pixels.
			var actor_region := Rect2i(region.grow(2))
			actor.model_root.hide()
			for i in 3: await shot(station.view.viewport_3d)
			var empty := await shot(station.view.viewport_3d)
			actor.model_root.show()
			var full := await shot(station.view.viewport_3d)
			var covered := difference(empty,full,actor_region)
			for mesh in foreground: mesh.hide()
			actor.model_root.hide()
			empty = await shot(station.view.viewport_3d)
			actor.model_root.show()
			full = await shot(station.view.viewport_3d)
			var clear := difference(empty,full,actor_region)
			print("DEPTH identity=",identity," point=",location," covered=",covered," clear=",clear)
			check(clear > 100, "positive control renders player/NPC")
			if location.x < 0: check(covered < clear * 0.8, "office occludes actor behind it")
			else: check(covered > clear * 0.8, "actor beside office remains visible")
			for mesh in foreground: mesh.show()
		station._actor_exited(actor)
		actor.free()
	station.free()
	await process_frame
	print("URBAN_STATION_ACTOR_DEPTH failures=",failures)
	quit(0 if failures.is_empty() else 1)
