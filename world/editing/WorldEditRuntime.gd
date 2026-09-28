extends RefCounted
const DATA := preload("res://world/editing/WorldEditData.gd")

static func apply(region: Node) -> void:
	var loaded := DATA.read_document()
	if not loaded.error.is_empty():
		push_error("Editor de mundo: " + loaded.error)
		return
	var doc: Dictionary = Engine.get_meta("geteco_world_edit_document", loaded.document)
	var changes: Dictionary = doc.get("regions", {}).get(region.region_id, {})
	if changes.is_empty(): return
	var base := DATA.catalog(region)
	var accepted := {}
	for id in changes:
		var row: Dictionary = changes[id]
		if row.get("type", "") == "piece": continue # WorldEditPieces owns authored groups.
		var error := DATA.validate_entity(row)
		if not error.is_empty() or (not base.has(id) and not str(id).begins_with("new/")):
			push_error("Editor de mundo: alteração inválida ou origem ausente: " + str(id))
			continue
		if base.has(id) and (base[id].get("locked", false) or row.type != base[id].type):
			push_error("Editor de mundo: objeto protegido: " + str(id))
			continue
		if base.get(id,{}).get("service_building",false) and (row.get("deleted",false) or not row.get("service_building",false) or row.get("model","") != base[id].model):
			push_error("Editor de mundo: preserve a identidade do prédio com serviço: "+str(id))
			continue
		if row.type == "building" and not row.get("deleted", false) and row.get("model", "office") not in DATA.BUILDING_TYPES and not base.has(id):
			push_error("Editor de mundo: modelo de prédio inválido.")
			continue
		accepted[id] = row
	if accepted.is_empty(): return
	if region.region_id == "harbor": preload("res://world/editing/WorldPaving.gd").apply(region.harbor_urban_surface,accepted)
	var roads_changed := false
	for row in accepted.values():
		if row.type == "road": roads_changed = true
	var original_buildings := {}
	for b in region.buildings: original_buildings["building/" + str(b.id)] = b
	for key in region.records:
		region.records[key] = region.records[key].filter(func(row):
			if row.kind == "road": return not roads_changed
			return not accepted.has(DATA.record_id(row)))
	if roads_changed:
		var edited := DATA.effective(base, accepted)
		preload("res://world/editing/WorldEditRoads.gd").rebuild(region,edited)
	region.buildings = region.buildings.filter(func(b): return not accepted.has("building/" + str(b.id)))
	for id in accepted:
		var row: Dictionary = accepted[id]
		if row.get("deleted", false) or row.type == "road" or row.get("paving",false): continue
		var position := DATA.xyz(row.position)
		match str(row.type):
			"tree":
				if row.get("tree_model","pine") == "harbor":
					region._record(position, {"kind":"harbor_prop","position":position,"editor_id":id,"editor_rotation":deg_to_rad(float(row.rotation)),"data":{"kind":"tree","point":Vector2(position.x,position.z)*16.0,"style":int(row.variant),"scale_factor":float(row.scale),"color":row.get("color","446b53"),"source_id":"world_editor"}})
					continue
				region._record(position, {"kind": "tree", "position": position, "variant": int(row.variant), "snow": row.snow, "editor_scale": float(row.scale), "editor_rotation": deg_to_rad(float(row.rotation)), "editor_id": id})
			"building":
				var data: Dictionary = original_buildings.get(id, {}).duplicate(true)
				var source: Dictionary = data.duplicate(true)
				data.merge({"id": data.get("id", str(id).replace("/", "_")), "position": position, "size": DATA.point(row.size), "kind": row.model, "color": row.color, "height_override": float(row.height), "editor_rotation": deg_to_rad(float(row.rotation)), "editor_id": id, "original_name": data.get("original_name", "")}, true)
				if base.get(id,{}).get("service_building",false):
					data.size = source.size
					data.kind = source.kind
					data.color = source.get("color","8b8d80")
					data.height_override = preload("res://world/urban_detail/UrbanBuildingFactory.gd").resolved_height(source)
					data.editor_service = row.duplicate(true)
				region.buildings.append(data)
				region._record(position, {"kind": "building", "data": data})
			"ground":
				var ground := preload("res://world/editing/WorldGroundFactory.gd")
				var area := ground.bounds(row)
				var masks: Array = []
				# Saved IDs preserve creation order; newer patches replace old surfaces.
				for other in accepted.values():
					if other.type == "ground" and not other.get("deleted",false) and str(other.id) > str(id) and area.intersects(ground.bounds(other)):
						var polygon := ground.footprint(other)
						if other.has("outline"):
							if Geometry2D.is_polygon_clockwise(polygon): polygon.reverse()
							var indices := Geometry2D.triangulate_polygon(polygon)
							for i in range(0,indices.size(),3): masks.append(PackedVector2Array([polygon[indices[i]],polygon[indices[i+1]],polygon[indices[i+2]]]))
						else: masks.append(polygon)
				for x in range(floori(area.position.x/64),ceili(area.end.x/64)):
					for z in range(floori(area.position.y/64),ceili(area.end.y/64)):
						var clip := Rect2(Vector2(x,z)*64,Vector2.ONE*64)
						region._record(Vector3(x*64+32,0,z*64+32),{"kind":"editor_ground","data":row,"clip":clip,"masks":masks})
			"prop": region._record(position, {"kind":"editor_prop", "position":position, "data":row})
			"light": region._record(position, {"kind": "editor_light", "position": position, "data": row})
	# Keep forest outside authored roads after a move/widen, without reseeding.
	if roads_changed:
		for key in region.records:
			region.records[key] = region.records[key].filter(func(row):
				if row.kind != "tree": return true
				for road in region.roads+region.walkways:
					for i in range(road.points.size()-1):
						var near := Geometry3D.get_closest_point_to_segment(row.position, road.points[i], road.points[i+1])
						if near.distance_to(row.position) < float(road.width)*.5 + .6: return false
				return true)

static func clearings(region: Node) -> Array:
	var result: Array = []
	for b in region.buildings:
		if not b.has("editor_id"): continue
		# Circumscribed square reserves the whole rotated footprint and its access.
		var radius: float = b.size.length()*.5 + 2.0
		result.append(Rect2(Vector2(b.position.x, b.position.z)-Vector2.ONE*radius, Vector2.ONE*radius*2))
	return result

static func build_light(region: Node, chunk: Node3D, record: Dictionary) -> void:
	var row: Dictionary = record.data
	var lamp := Node3D.new()
	lamp.name = "EditorLamp"
	lamp.set_meta("editor_id", row.id)
	lamp.position = record.position
	if region.terrain != null: lamp.position.y = region.terrain.surface_height_at(Vector2(lamp.position.x, lamp.position.z))
	chunk.add_child(lamp)
	region._box(lamp, "Pole", Vector3(0, row.height*.5, 0), Vector3(.18, row.height, .18), Color("403e37"), true)
	var glass: MeshInstance3D = region._box(lamp, "Lamp", Vector3(0, row.height, 0), Vector3(.5, .3, .5), Color(row.color))
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position.y = float(row.height)
	light.light_color = Color(row.color)
	light.omni_range = float(row.range)
	light.light_energy = float(row.energy)
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	lamp.add_child(light)
