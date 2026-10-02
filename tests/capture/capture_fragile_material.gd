extends "res://tests/test_fragile_debris_physics.gd"
## Renderiza os materiais reais após o impacto; não é benchmark de FPS.
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var fragile = load("res://gameplay/street_physics/FragileProps3D.gd")
	var kit = load("res://world/city_look/CityPropKit.gd")
	var director := Director.new()
	root.add_child(director)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	root.add_child(sun)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.look_at_from_position(Vector3(7, 6, 12), Vector3(0, 0.5, 0))
	for i in 4:
		var kind: String = ["trash_can", "news_box", "mailbox", "hydrant"][i]
		var chunk := Node3D.new()
		root.add_child(chunk)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = kit.mesh(kind)
		multimesh.instance_count = 1
		multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(i * 2.0 - 3, 0, 0)))
		fragile.register_instance(kind, multimesh, 0, chunk)
	for list in fragile.cells.values():
		for item in list: fragile.hit(item, 8.0, Vector3.RIGHT, director)
	for body in director.get_children():
		if body is RigidBody3D:
			body.freeze = true
			body.rotation.z = -0.8
	await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://evidence/fragile-material"
	DirAccess.make_dir_recursive_absolute(output)
	var result := root.get_texture().get_image().save_png(output + "/after-hit.png")
	print("FRAGILE_CAPTURE result=", result)
	quit(result)
