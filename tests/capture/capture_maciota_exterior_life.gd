extends SceneTree
## Isolated facade review while the shared V2 world is under concurrent edits.
## This fixture checks the structural collision contract and captures real pixels.

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var facade := load("res://assets/maciota/GarageFacade.gd").new() as Node3D
	root.add_child(facade)
	var solids := 0
	for child in facade.get_children():
		if child is MeshInstance3D and child.has_meta("interior_solid_id"):
			solids += 1
	assert(solids == 4, "Original garage and neighbor solids must remain unchanged")
	var details := facade.get_node_or_null("MaciotaExteriorDetails") as MeshInstance3D
	var sign := facade.get_node_or_null("MaciotaName") as Label3D
	assert(details != null and details.mesh != null and not details.has_meta("interior_solid_id"))
	assert(sign != null and sign.text == "MACIOTA")
	assert(facade.get_node_or_null("MaciotaWorkLampLeft") != null)
	assert(facade.get_node_or_null("MaciotaWorkLampRight") != null)
	print("MACIOTA_EXTERIOR_LIFE structure PASS solids=", solids)
	if "--undressed" in OS.get_cmdline_user_args():
		for child in facade.get_children():
			if child.name == "MaciotaExteriorDetails" or child.name == "MaciotaName" or str(child.name).begins_with("MaciotaWorkLamp"):
				facade.remove_child(child)
				child.free()
	if DisplayServer.get_name() == "headless":
		quit()
		return
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 17)
	floor.mesh = plane
	floor.position = Vector3(.4, -.04, 6)
	var pavement := StandardMaterial3D.new()
	pavement.albedo_color = Color("8d9089")
	floor.material_override = pavement
	root.add_child(floor)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-55, -28, 0)
	sunlight.light_energy = 1.8
	root.add_child(sunlight)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	camera.position = Vector3(.4, 13, 21)
	root.add_child(camera)
	camera.look_at(Vector3(.4, 2.8, 5.7))
	camera.current = true
	for frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://isolated-maciota-after.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			path = argument.trim_prefix("--output=")
	var error := root.get_texture().get_image().save_png(path)
	assert(error == OK, "Could not save facade capture: %d" % error)
	print("MACIOTA_EXTERIOR_LIFE capture ", path)
	quit()
