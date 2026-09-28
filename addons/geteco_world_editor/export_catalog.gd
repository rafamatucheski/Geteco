extends SceneTree
## Build the catalog with the same constructors used by the production world.
const DATA := preload("res://world/editing/WorldEditData.gd")
const CONTEXT := preload("res://addons/geteco_world_editor/WorldContextCatalog.gd")
const SESSION_CONTEXT := preload("res://addons/geteco_world_editor/WorldSessionContext.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	if "--session-only" in OS.get_cmdline_user_args():
		var supplement := SESSION_CONTEXT.build(root)
		if not write_document(supplement,SESSION_CONTEXT.PATH): quit(1); return
		print("WORLD_EDITOR_SESSION_CONTEXT_OK ",supplement.context.size())
		for frame in 3: await process_frame
		quit()
		return
	var result := {"version":2,"regions":{}}
	for id in ["harbor","mountain"]:
		var region = load("res://world/editing/EditableRegion.gd").build_region(id)
		root.add_child(region)
		region.set_process(false)
		region.release_chunks()
		await process_frame
		var entries: Array = []
		for entry in region.entries:
			for field in ["entry_position","return_position","position"]:
				if entry.get(field) is Vector3: entries.append(DATA.xy(entry[field]))
		var context: Dictionary = await CONTEXT.build(region)
		var polygons: Array = []
		for poly in region.extra_land:
			var points: Array = []
			for p in poly: points.append([p.x,p.y])
			polygons.append(points)
		result.regions[id] = {"objects":DATA.catalog(region),"context":context.objects,"entries":entries,"spawn":DATA.xy(region.spawn_position),"land_polygons":polygons,"coverage":{"record_count":context.record_count,"covered_records":context.covered_records,"kind_counts":context.kind_counts},"terrain":[]}
		if id == "harbor":
			var transit := preload("res://runtime/UrbanTransitPresentation.gd").new()
			transit.configure(null,false)
			root.add_child(transit)
			for definition in transit.definitions:
				var art: Node3D = transit.build_geometry(transit,definition)
				var transit_id := "context/harbor/transit/"+str(definition.id)
				result.regions[id].context[transit_id] = CONTEXT.from_node(art,transit_id,definition.name,"transit",definition.position)
			transit.free()
			preload("res://runtime/UrbanTransitPresentation.gd").upgrade_editor_catalog(result.regions)
			result.regions[id]["land"] = region.source_data.harbor_land
			var connection := preload("res://world/regions/WorldConnection3D.gd").new()
			root.add_child(connection)
			var connection_id := "context/harbor/world_connection"
			result.regions[id].context[connection_id] = CONTEXT.from_node(connection,connection_id,"Ponte e túnel da montanha","connection",Vector3(500,0,-285))
			connection.free()
			var supplement := SESSION_CONTEXT.build(root)
			result.regions[id].context.merge(supplement.context,true)
			result.regions[id]["session_context_version"] = SESSION_CONTEXT.VERSION
			result.regions[id].coverage["session_objects"] = supplement.context.size()
		else:
			var min_cell := Vector2i(100000,100000)
			var max_cell := Vector2i(-100000,-100000)
			for key in region.records:
				min_cell = min_cell.min(key)
				max_cell = max_cell.max(key)
			for x in range(min_cell.x,max_cell.x+1):
				for z in range(min_cell.y,max_cell.y+1):
					if not region._mountain_owns_terrain(Vector2i(x,z)): continue
					var h: float = region.terrain.surface_height_at(Vector2((x+.5)*64,(z+.5)*64))
					var color := Color("334e3e").lerp(Color("abb7b2"),clampf(h/30.0,0,1))
					result.regions[id].terrain.append([x*64,z*64,64,64,color.to_html(false)])
		region.free()
		await process_frame
	if not write_document(result,"res://addons/geteco_world_editor/base_catalog.json"): quit(1); return
	print("WORLD_EDITOR_CATALOG_OK ",JSON.stringify({"harbor":result.regions.harbor.coverage,"mountain":result.regions.mountain.coverage}))
	quit()

func write_document(document: Dictionary,default_path: String) -> bool:
	var output := default_path
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível exportar o catálogo.")
		return false
	file.store_string(JSON.stringify(document))
	file.close()
	return true
