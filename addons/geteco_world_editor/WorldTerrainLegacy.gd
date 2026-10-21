@tool
extends RefCounted
## Old 2D catalogs contain flat terrain without terrain markers. Replace only
## known owners with real remaining scenery; individually indexed units stay
## in their own editable rows, and unrepresented props remain in foreground.
static func catalogs(area: String) -> Dictionary:
	var rows := {}
	for path in ["res://addons/geteco_world_editor/base_catalog.json","res://.godot/world_editor_catalog.json"]:
		var data: Dictionary = preload("res://addons/geteco_world_editor/WorldPreviewProtocol.gd").read(path).data
		var regions: Dictionary = data.get("regions",data)
		rows.merge(regions.get(area,{}).get("context",{}),true)
	return rows

static func bind(source: Node3D, area: String, tiles: Array, units: Array, known: Dictionary = {}) -> void:
	if tiles.is_empty() or units.is_empty(): return
	var rows := known if not known.is_empty() else catalogs(area)
	var provided := {}
	for row: Dictionary in units: provided[str(row.id)] = true
	var foreground: Dictionary = tiles[0].get("foreground",{})
	if area == "harbor":
		var course: Node3D
		var pending: Array[Node] = [source]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			if node is Node3D and str(node.get_meta("world_unit_session_source","")) == "motocross": course = node; break
			for child in node.get_children(): pending.append(child)
		if course != null:
			var remaining := remaining_parts(course,provided)
			for id: String in rows:
				if rows[id].get("kind","") != "motocross_course": continue
				foreground[id] = {"id":id,"parts":remaining}
				for tile: Dictionary in tiles:
					for owner in tile.get("source_ids",[]):
						if "/s_motocross/" in str(owner):
							if id not in tile.source_ids: tile.source_ids.append(id)
							break
		# The shipped woodland catalog also predates ownership of its physical
		# floor moving to NativeRegion. Its two old green triangles can cover the
		# entire course even after the course's own legacy owner is replaced.
		for id: String in rows:
			if rows[id].get("kind","") != "woodland": continue
			var owner := find_owner(source,id)
			if owner == null: continue
			var parts: Array = []
			var has_batches := false
			for property: Dictionary in owner.get_property_list():
				if str(property.name) == "editor_batches": has_batches = true; break
			if has_batches:
				preload("res://addons/geteco_world_editor/WorldSessionContext.gd")._collect_woodland(owner,parts,owner.get("editor_batches"))
			else: parts = remaining_parts(owner,provided)
			foreground[id] = {"id":id,"parts":parts}
	elif area == "desert":
		var chunks: Dictionary = source.get("chunks")
		for id: String in rows:
			if not id.begins_with("context/desert/terrain/"): continue
			var key := Vector2i(id.get_slice("/",3).to_int(),id.get_slice("/",4).to_int())
			var chunk := chunks.get(key) as Node3D
			if chunk == null: continue
			var cell := Rect2(Vector2(key)*96.0,Vector2.ONE*96.0)
			var covered := false
			for tile: Dictionary in tiles:
				var at: Array = tile.bounds
				if Rect2(at[0],at[1],at[2],at[3]).intersects(cell):
					covered = true
					if id not in tile.source_ids: tile.source_ids.append(id)
			if covered: foreground[id] = {"id":id,"parts":remaining_parts(chunk,provided)}
	tiles[0]["foreground"] = foreground

static func find_owner(source: Node, id: String) -> Node3D:
	var pending: Array[Node] = [source]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Node3D and str(node.get_meta("editor_id","")) == id: return node
		for child in node.get_children(): pending.append(child)
	return null

static func remaining_parts(source: Node, provided: Dictionary) -> Array:
	var parts: Array = []
	var pending: Array[Node] = [source]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Node3D and not node.visible: continue
		if node.has_meta("world_edit_piece_id") and provided.has("piece/"+str(node.get_meta("world_edit_piece_id"))): continue
		if node is MeshInstance3D and node.mesh != null:
			if not node.get_meta("editor_terrain_surface",false) and not node.get_meta("desert_base_ground",false):
				var material: Material = node.material_override
				if material == null and node.mesh.get_surface_count() > 0: material = node.get_active_material(0)
				preload("res://addons/geteco_world_editor/WorldContextCatalog.gd").part(node.mesh,node.global_transform,material,parts)
		elif node is MultiMeshInstance3D:
			preload("res://addons/geteco_world_editor/WorldContextCatalog.gd").collect(node,parts,false,true)
			continue
		for child in node.get_children(): pending.append(child)
	parts.sort_custom(func(a,b): return float(a[4]) < float(b[4]))
	return parts
