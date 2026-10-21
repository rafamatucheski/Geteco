@tool
extends RefCounted
## Decode/upload small tiles between frames; the previous complete 2D map stays
## available until this revision has finished importing.
static func run(reference: WeakRef, response: Dictionary, tree: SceneTree) -> void:
	var panel = reference.get_ref()
	if not is_instance_valid(panel): return
	var generation: int = panel.revision
	var epoch: int = panel.assembly_epoch
	var tiles: Array = []
	var began := Time.get_ticks_usec()
	for tile: Dictionary in response.get("topography",[]):
		var image := Image.load_from_file(str(tile.get("path","")))
		if image != null and not image.is_empty():
			var loaded := tile.duplicate(true)
			loaded.coverage_radius = int(response.get("radius",0))
			loaded.texture = ImageTexture.create_from_image(image)
			tiles.append(loaded)
		if Time.get_ticks_usec()-began >= 3000:
			await tree.process_frame
			panel = reference.get_ref()
			if not is_instance_valid(panel) or not panel.is_inside_tree() or panel.revision != generation or panel.assembly_epoch != epoch: return
			began = Time.get_ticks_usec()
	panel = reference.get_ref()
	if not is_instance_valid(panel) or panel.revision != generation or panel.assembly_epoch != epoch: return
	var area := str(response.get("area",""))
	var signature := str(response.get("terrain_revision",""))
	if int(response.get("radius",0)) < 0 and not tiles.is_empty():
		# One complete revision per region is enough here; the UI owns its own
		# small undo/navigation cache and keeps any textures it still needs.
		for key in panel.topography_cache.keys():
			if str(key).begins_with(area+"/"): panel.topography_cache.erase(key)
		panel.topography_cache[area+"/"+signature] = tiles
	panel.topo_ready.emit(area,signature,tiles)
