extends SceneTree
var world
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func picture(path: String) -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	if not path.is_empty(): result.save_png("res://evidence/"+path+".png")
	return result

func actor_pixels(with_actor: Image, without_actor: Image) -> int:
	var feet: Vector2 = world.camera.unproject_position(world.player.position)
	var head: Vector2 = world.camera.unproject_position(world.player.position+Vector3.UP*1.9)
	var count := 0
	for y in range(maxi(0,int(head.y)-10),mini(with_actor.get_height(),int(feet.y)+10)):
		for x in range(maxi(0,int(feet.x)-45),mini(with_actor.get_width(),int(feet.x)+45)):
			var a := with_actor.get_pixel(x,y)
			var b := without_actor.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.10: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Depth validation requires rendering")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	await create_timer(2.0).timeout
	await picture("world-start")
	world.player.teleport(Vector3(-8.3,0.04,-8.5))
	world.camera.target_size = 23
	world.camera.heading = -PI/6
	await create_timer(1.0).timeout
	await picture("world-street")
	world.camera.target_size = 50
	world.player.teleport(Vector3(0,0.04,0))
	await create_timer(1.0).timeout
	await picture("world-overview")
	world.hud.hide()
	world.camera.set_process(false)
	world.camera.position = Vector3(-10,12,12)
	world.camera.look_at(Vector3(-10,0,2))
	world.camera.size = 9
	world.player.set_physics_process(false)
	for resident in world.people:
		resident.set_physics_process(false)
		resident.hide()
	var samples: Dictionary = {}
	for entry in [{"name":"front","position":Vector3(-10,0,3.2)},{"name":"behind","position":Vector3(-10,0,0.9)},{"name":"beside","position":Vector3(-8.5,0,2)}]:
		world.player.teleport(entry.position)
		world.player.visual.show()
		var visible_image := await picture("depth-"+entry.name)
		world.player.visual.hide()
		var background := await picture("")
		var with_crate := actor_pixels(visible_image,background)
		world.street.get_node("box_9c764e").hide()
		world.street.get_node("box_6b5138").hide()
		world.player.visual.show()
		var unobstructed := await picture("")
		world.player.visual.hide()
		var clear_background := await picture("")
		var without_crate := actor_pixels(unobstructed,clear_background)
		world.street.get_node("box_9c764e").show()
		world.street.get_node("box_6b5138").show()
		samples[entry.name] = {"with_crate":with_crate,"without_crate":without_crate,"visible_ratio":float(with_crate)/maxi(1,without_crate)}
		if without_crate < 150: failures.append("Actor missing from positive control: "+entry.name)
	if samples.behind.visible_ratio > 0.90 or samples.behind.visible_ratio < 0.05:
		failures.append("Behind crate must partially occlude the actor")
	if samples.front.visible_ratio < 0.95 or samples.beside.visible_ratio < 0.95:
		failures.append("Front and beside must remain visible")
	var report := {"samples":samples,"failures":failures}
	var file := FileAccess.open("res://evidence/depth.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DEPTH ",JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
