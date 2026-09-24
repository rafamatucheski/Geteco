extends "res://tests/visual_depth.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	await create_timer(1).timeout
	var native: bool = world.production != null
	var prefix := "native-v2-depth" if native else "v2-depth"
	if native:
		for i in 240:
			if world.session.ready_for_play: break
			await physics_frame
		assert(await world.session.enter_place("maciota",false))
	else: assert(world.session.transition(true,false))
	await create_timer(.4).timeout
	world.hud.hide()
	world.player.set_physics_process(false)
	for mesh in world.player.find_children("*","GeometryInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.camera.set_process(false)
	var desk: Array[Node3D] = []
	for child in world.maciota_place.room.get_children():
		if child is MeshInstance3D and child.position.x > 3.5 and child.position.x < 5.5 and child.position.z > -2.3 and child.position.z < -1.3 and child.position.y < 1.5:
			desk.append(child)
	assert(desk.size() > 3,"Find original desk meshes")
	var samples := {}
	for entry in [{"name":"front","point":Vector3(4.2,0,-.65)}, {"name":"behind","point":Vector3(5.22,0,-2.56)}, {"name":"beside","point":Vector3(3.1,0,-.55)}]:
		var point: Vector3 = world.maciota_place.interior_origin+entry.point+Vector3.UP*.04
		var clear: bool = world.session.position_clear(point) if native else world.session.checkpoint_clear(point)
		if not clear: failures.append("Depth sample inside solid "+entry.name)
		world.player.teleport(world.maciota_place.interior_origin+entry.point)
		world.player.visual.show()
		var visible_image := await picture(prefix+"-"+entry.name)
		world.player.visual.hide()
		var background := await picture("")
		var with_desk := actor_pixels(visible_image,background)
		for mesh in desk: mesh.hide()
		world.player.visual.show()
		var unobstructed := await picture("")
		world.player.visual.hide()
		var clear_background := await picture("")
		var without_desk := actor_pixels(unobstructed,clear_background)
		for mesh in desk: mesh.show()
		samples[entry.name] = {"with_desk":with_desk,"without_desk":without_desk,"ratio":float(with_desk)/maxi(1,without_desk)}
		if without_desk < 100: failures.append("Positive control missing "+entry.name)
	if samples.behind.ratio > .92 or samples.behind.ratio < .03: failures.append("Desk must partially occlude behind")
	if samples.front.ratio < .95 or samples.beside.ratio < .95: failures.append("Front and beside must stay visible")
	var report := {"samples":samples,"failures":failures}
	var file := FileAccess.open("res://evidence/"+prefix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("V2_DEPTH ",JSON.stringify(report))
	world.free()
	quit(0 if failures.is_empty() else 1)
