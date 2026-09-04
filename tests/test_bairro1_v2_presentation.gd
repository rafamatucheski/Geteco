extends SceneTree

## Garante a apresentação do jogo, independente dos gizmos do editor.
## A rede de navegação continua presente, mas suas curvas/linhas técnicas não
## podem ser CanvasItems visíveis acima das ruas e dos landmarks.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://district/bairro1_v2/Bairro1V2.tscn") as PackedScene
	assert(scene != null, "Bairro1V2 scene must load")
	var district := scene.instantiate()
	root.add_child(district)
	for _frame in range(20):
		await process_frame

	var layout := district.get_node_or_null("LayoutV2") as Node2D
	var network := layout.get_node_or_null("RoadNetwork") as Node2D
	var landmarks := district.get_node_or_null("LandmarksV2") as Node2D
	var gameplay := district.get_node_or_null("GameplayV2") as Node2D
	assert(network != null, "Integrated layout must contain RoadNetwork")
	assert(network.get("show_junction_debug") == false, "Junction debug must be disabled by default")
	assert(layout.z_index == 0, "Road layer must be the base world layer")
	assert(landmarks.z_index > layout.z_index, "Landmarks must render above roads")
	assert(gameplay.z_index > landmarks.z_index, "Gameplay markers must render above landmarks")
	for route_path in network.find_children("", "Path2D", true, false):
		assert(not (route_path as CanvasItem).visible, "Navigation guide must not render in normal play: %s" % route_path.get_path())

	print("Bairro1V2 presentation contract passed")
	quit(0)
