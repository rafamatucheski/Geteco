extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)

	print("Instantiating REAL Player.gd...")
	var player_script = load("res://Player.gd")
	if not player_script:
		print("ERROR: Could not load Player.gd")
		quit(1)
		return

	var real_player = player_script.new()
	real_player.name = "RealPlayer"
	scene.add_child(real_player)

	for i in range(10):
		await process_frame

	print("Real player instantiated successfully!")
	print("  model_root:", real_player.model_root)
	print("  viewport_3d:", real_player.viewport_3d)
	print("  sprite_3d_display:", real_player.sprite_3d_display)
	print("  combat_pose:", real_player.combat_pose)

	quit(0)
