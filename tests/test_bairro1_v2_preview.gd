extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://district/bairro1_v2/Bairro1V2Preview.tscn") as PackedScene
	assert(scene != null, "Bairro1V2 preview must load")
	var preview := scene.instantiate()
	root.add_child(preview)
	for _frame in range(8):
		await process_frame

	var district := preview.get_node_or_null("Bairro1V2") as Node2D
	var player := preview.get_node_or_null("Player") as CharacterBody2D
	var spawn := district.call("get_marker", &"PlayerSpawn") as Marker2D
	assert(player != null and spawn != null, "Preview must expose player and PlayerSpawn")
	assert(player.global_position.distance_to(spawn.global_position) < 0.1, "Preview player must start at PlayerSpawn")
	print("Bairro1V2 preview passed")
	quit(0)
