extends SceneTree

const HARBOR_SCENE: PackedScene = preload("res://district/harbor_preview/HarborGame.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = HARBOR_SCENE.instantiate()
	root.add_child(world)
	current_scene = world

	for f in 8:
		await physics_frame

	paused = false
	var arrival = world.get_node_or_null("ArrivalMission")
	if arrival: arrival.queue_free()

	for f in 5:
		await physics_frame

	var player = world.get_node_or_null("Player") as CharacterBody2D
	player.show()
	player.set_physics_process(true)
	player.is_control_disabled = false
	player.is_in_dialogue = false

	player.global_position = Vector2(1720, 1150)
	var cam = player.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.zoom = Vector2(7.0, 7.0) # Zoom bem próximo
		cam.position_smoothing_enabled = false

	player.active_weapon_id = "pistol"
	player._update_equipped_weapon_3d_mesh()
	player.model_root.rotation.y = PI # Frente

	for f in 10:
		await physics_frame

	var img_front = root.get_viewport().get_texture().get_image()
	img_front.save_png("res://tests/dante_closeup_front.png")

	player.model_root.rotation.y = PI * 0.8
	for f in 10:
		await physics_frame

	var img_angle = root.get_viewport().get_texture().get_image()
	img_angle.save_png("res://tests/dante_closeup_angle.png")

	var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/ac7b8daf-4790-408c-8376-3690d7044e34"
	var d := DirAccess.open(artifact_dir)
	if d:
		d.copy("res://tests/dante_closeup_front.png", artifact_dir + "/dante_closeup_front.png")
		d.copy("res://tests/dante_closeup_angle.png", artifact_dir + "/dante_closeup_angle.png")

	quit(0)
