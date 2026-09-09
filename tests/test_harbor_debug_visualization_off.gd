extends SceneTree

## Confirms the harbor preview never renders lane/junction debug art in normal
## play. HarborRoadNetwork.gd inherits UnifiedRoadNetwork2D's show_junction_debug
## export (default false, only ever drawing a diagnostic junction dot when an
## engineer explicitly enables it) without overriding it, so this is a
## regression guard rather than new behavior — mirrors the same check already
## made for Bairro1V2 in test_bairro1_v2_presentation.gd.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://world/harbor/HarborPreview.tscn") as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for _frame in 3:
		await process_frame
	var network := scene.get_node_or_null("RoadNetwork")
	var failures: Array[String] = []
	if network == null:
		failures.append("Scene must contain RoadNetwork")
	elif network.get("show_junction_debug") != false:
		failures.append("show_junction_debug must default to false in HarborPreview")
	for failure in failures:
		push_error("HARBOR_DEBUG_VIS: " + failure)
	print("HARBOR_DEBUG_VIS_RESULT failures=%d" % failures.size())
	scene.queue_free()
	quit(0 if failures.is_empty() else 1)
