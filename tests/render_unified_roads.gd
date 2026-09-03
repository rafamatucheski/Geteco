extends SceneTree

const OUTPUT_PATH := "res://../artifacts/unified-road-network-preview.png"


func _initialize() -> void:
	call_deferred("_render_preview")


func _render_preview() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1050)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var preview_root := Node2D.new()
	viewport.add_child(preview_root)
	var district_scene := load("res://district/borough_one/DistrictOneComplete.tscn") as PackedScene
	var district := district_scene.instantiate()
	preview_root.add_child(district)
	for child_name in [
		"Bairro1ProgressionConnections", "DistrictOneMissionAnchors",
		"Bairro1UrbanDensity", "Bairro1CivicServices", "DistrictOnePopulation",
	]:
		var child := district.get_node_or_null(child_name) as CanvasItem
		if child != null:
			child.visible = false
	for provider_name in ["Bairro1Expansion", "Bairro1RoadNetwork"]:
		var provider := district.get_node_or_null(provider_name)
		if provider != null:
			for child in provider.get_children():
				if child is CanvasItem:
					(child as CanvasItem).visible = false

	var camera := Camera2D.new()
	camera.position = Vector2(1600, 2380)
	camera.zoom = Vector2(0.43, 0.43)
	camera.enabled = true
	viewport.add_child(camera)

	for frame in range(12):
		await process_frame
	var graph := district.get_node_or_null("UnifiedRoadNetwork")
	if graph == null:
		push_error("UnifiedRoadNetwork is missing from DistrictOneComplete")
		quit(3)
		return
	var graph_data: Dictionary = graph.get_graph_data()
	if not (graph_data.validation_errors as Array).is_empty():
		push_error("Unified road validation failed: %s" % graph_data.validation_errors)
		quit(4)
		return
	print("UNIFIED_ROAD_AUDIT: %s" % graph.get_validation_summary())
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("Rendering driver did not provide a viewport image")
		quit(2)
		return
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Could not save unified road preview: %s" % error_string(error))
		quit(1)
		return
	print("UNIFIED_ROAD_PREVIEW: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	quit()
