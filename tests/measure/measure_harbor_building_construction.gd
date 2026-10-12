extends SceneTree
## CPU construction attribution only. No Main, no gameplay/FPS claim.
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACE := preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd")
const TILES := preload("res://world/places/ShopInteriorMaterials.gd")
const TRACE := preload("res://runtime/StallWorkTrace.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("BUILDING_CONSTRUCTION timeout"); quit(3))
	var destination := ""
	var label := "building-construction"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): destination = argument.trim_prefix("--out=")
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	if destination.is_empty():
		push_error("Pass --out=<new JSON path> for CPU construction evidence")
		quit(2)
		return
	if FileAccess.file_exists(destination):
		push_error("Refusing to overwrite existing evidence")
		quit(2)
		return
	var definition := CATALOG.find("harbor_customs_house")
	if definition.is_empty(): quit(4); return
	var stage := Node3D.new()
	root.add_child(stage)
	await process_frame
	var rows: Array[Dictionary] = []
	for index in 2:
		var cached_textures := TILES._textures.keys()
		var model_cached := ResourceLoader.has_cached(str(definition.model))
		TRACE.take()
		TRACE.enabled = true
		var began := Time.get_ticks_usec()
		var room := PLACE.new()
		room.definition = definition
		room.position = definition.exterior_position
		room.rotation.y = definition.exterior_rotation
		var add_began := Time.get_ticks_usec()
		stage.add_child(room)
		var ended := Time.get_ticks_usec()
		TRACE.enabled = false
		var spans := TRACE.take()
		rows.append({"visit":index, "model_resource_previously_cached":model_cached,
			"textures_previously_cached":cached_textures, "construct_usec":ended-began,
			"add_child_usec":ended-add_began, "nodes":1+room.find_children("*", "", true, false).size(),
			"solids":room.floor_room.solid_bodies.size(), "rewards":room.reward_points.size(), "spans":spans})
		room.queue_free()
		await process_frame
		await process_frame
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null: quit(5); return
	output.store_string(JSON.stringify({"label":label, "place":definition.id, "samples":rows,
		"engine":Engine.get_version_info(), "display":DisplayServer.get_name(),
		"scope":"Isolated synchronous construction CPU wall time. Two visits in one process; first-use cache status recorded, caches never cleared. Nested spans must not be summed with their parents. No Main, no residents admitted, no FPS or physical/visual approval."}, "\t"))
	output.close()
	print("BUILDING_CONSTRUCTION_FINISHED ", label, " ", destination)
	quit()
