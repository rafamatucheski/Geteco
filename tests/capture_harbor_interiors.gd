extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size

	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene

	for frame in 30:
		await physics_frame

	var player := scene.get_node("Player") as CharacterBody2D
	var camera := scene.get_node("OverviewCamera") as Camera2D
	camera.make_current()

	var interiors_node := scene.get_node("Interiors")

	var interior_targets = [
		["garage", interiors_node.garage_interior, "Westgate Motor Co. (Jäger & Tito)"],
		["police", interiors_node.police_interior, "Harbor Patrol (Sgt Morales)"],
		["clinic", interiors_node.clinic_interior, "Bay Medical Clinic (Enfermeira Clara)"],
		["workshop", interiors_node.workshop_interior, "Northgate Auto (Mestre Arnaldo)"],
		["firehouse", interiors_node.fire_station_interior, "Northgate Fire Station (Capitão Rocha)"]
	]

	for target in interior_targets:
		var key: String = target[0]
		var interior: Node2D = target[1]
		var title: String = target[2]

		camera.global_position = interior.global_position
		camera.zoom = Vector2(1.1, 1.1)
		player.global_position = interior.global_position + Vector2(0, 50)
		player.velocity = Vector2.ZERO

		if key == "garage" and interior.jager_npc != null:
			interior.jager_npc._open_dialogue()
		elif key == "police" and interior.sergeant_npc != null:
			interior.sergeant_npc._open_dialogue()
		elif key == "clinic" and interior.nurse_npc != null:
			interior.nurse_npc._open_dialogue()
		elif key == "workshop" and interior.mechanic_npc != null:
			interior.mechanic_npc._open_dialogue()
		elif key == "firehouse" and interior.captain_npc != null:
			interior.captain_npc._open_dialogue()

		for frame in 45:
			await physics_frame

		var path := "D:/geteco/harbor_interior_%s.png" % key
		await _save(path)
		print("INTERIOR_CAPTURE %s -> %s" % [title, path])

		if key == "garage" and interior.jager_npc != null:
			interior.jager_npc._close_dialogue()
		elif key == "police" and interior.sergeant_npc != null:
			interior.sergeant_npc._close_dialogue()
		elif key == "clinic" and interior.nurse_npc != null:
			interior.nurse_npc._close_dialogue()
		elif key == "workshop" and interior.mechanic_npc != null:
			interior.mechanic_npc._close_dialogue()
		elif key == "firehouse" and interior.captain_npc != null:
			interior.captain_npc._close_dialogue()

	var ammu = load("res://world/harbor/interiors/HarborAmmunationInterior.gd").new()
	ammu.global_position = Vector2(30000, 20000)
	root.add_child(ammu)
	camera.global_position = ammu.global_position
	camera.zoom = Vector2(1.1, 1.1)
	ammu.gunsmith_npc._open_dialogue()
	for frame in 45:
		await physics_frame
	await _save("D:/geteco/harbor_interior_ammunation.png")
	print("INTERIOR_CAPTURE Ammu-Nation (Vance) -> D:/geteco/harbor_interior_ammunation.png")
	ammu.queue_free()

	var morgue = load("res://world/harbor/interiors/HarborMorgueInterior.gd").new()
	morgue.global_position = Vector2(32000, 20000)
	root.add_child(morgue)
	camera.global_position = morgue.global_position
	camera.zoom = Vector2(1.1, 1.1)
	morgue.pathologist_npc._open_dialogue()
	for frame in 45:
		await physics_frame
	await _save("D:/geteco/harbor_interior_morgue.png")
	print("INTERIOR_CAPTURE Morgue / IML (Dr. Silveira) -> D:/geteco/harbor_interior_morgue.png")
	morgue.queue_free()

	quit(0)

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img = root.get_texture().get_image()
	assert(img.save_png(path) == OK, "Failed to save PNG")
	print("SAVED: " + path)
