@tool
extends RefCounted
const PATH := "res://addons/geteco_world_editor/desert_catalog.json"
const REGION_PATH := "res://world/editing/EditableDesertRegion.gd"
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const CONTEXT := preload("res://addons/geteco_world_editor/WorldContextCatalog.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const LABELS := {"water_tower":"Caixa d’água", "rest_bench":"Banco do Horizonte", "bitrem":"Caminhão estacionado", "truck_stop":"Posto Horizonte", "abandoned_site":"Construção abandonada", "drag_line":"Arrancada", "moon_village":"Santa Lua", "utility_pole":"Poste de energia", "utility_span":"Rede elétrica", "utility_service":"Ramal elétrico", "lamp":"Iluminação do deserto"}

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if value is Dictionary: add_locations(value)
	return value if value is Dictionary else {}

static func add_locations(catalog: Dictionary) -> void:
	if not catalog.has("context"): return
	var relief: Rect2 = preload("res://world/desert/DesertTerrainRelief.gd").BOUNDS
	var mining: Rect2 = preload("res://world/mining/MiningLayout.gd").BOUNDS
	var sites := [["mining","Mineração",mining.get_center(),mining.size], ["canyon","Cânion",relief.get_center(),relief.size]]
	for site in preload("res://world/desert/expansion/DesertRelics.gd").sites():
		var label: String = {"station":"Estação abandonada","mine":"Mina abandonada","wagon":"Vagão descarrilado","wreck":"Caminhonete abandonada"}.get(site.id,site.id)
		sites.append([site.id,label,site.position,Vector2.ONE*float(site.radius)*2])
	for site in sites:
		var id := "context/desert/site/"+str(site[0])
		catalog.context[id] = {"id":id,"type":"context","kind":"location","label":site[1],"locked":true,"position":[site[2].x,site[2].y],"size":[site[3].x,site[3].y],"parts":[]}

static func build(parent: Node) -> Dictionary:
	var region_script = load(REGION_PATH)
	if region_script == null or not region_script.can_instantiate():
		push_error("Não foi possível construir o deserto; corrija os erros do cenário antes de atualizar a base.")
		return {}
	var region: Node3D = region_script.new()
	# No gameplay actors or ambient life are required to export geometry.
	parent.add_child(region)
	region.release_chunks()
	region.process_mode = Node.PROCESS_MODE_DISABLED
	await parent.get_tree().process_frame
	var result := {"objects":{},"context":{},"entries":[],"terrain":[],"spawn":DATA.xy(region.LAYOUT.TOWN),"coverage":{}}
	var bounds: Rect2 = region.LAYOUT.BOUNDS
	result.terrain.append([bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y,"b9a079"])
	for entry in region.entries:
		for field in ["position","return_position"]:
			if entry.get(field) is Vector3: result.entries.append(DATA.xy(entry[field]))
	for road in region.roads:
		var points: Array = []
		for point in road.points: points.append(DATA.xy(point))
		var id := "road/"+str(road.id)
		result.objects[id] = {"id":id,"type":"road","points":points,"width":road.width,"surface":"earth" if road.get("surface","")=="dirt" else "asphalt","locked":true}
	var count := 0
	for records in region.records.values():
		for record in records:
			var holder := Node3D.new()
			region.add_child(holder)
			region._build_record(holder,record)
			var groups := PIECES.collect(holder)
			if not groups.is_empty():
				var group: Node3D = groups[0]
				var id: String = "piece/"+region.piece_key(record)
				var label := str(LABELS.get(record.kind,str(record.kind).capitalize()))
				if record.has("data") and record.data.has("id"):
					label = str(record.data.get("name",""))
					if label.is_empty(): label = str(record.data.id).replace("desert_home_","Casa do deserto ").replace("santa_lua_home_","Casa de Santa Lua ").replace("_"," ").capitalize()
				var row := CONTEXT.from_node(group,id,label,record.kind,group.global_position)
				row.merge({"type":"piece","position":DATA.xy(group.global_position),"rotation":0.0,"source_record":PIECES.record_key(record),"locked":not region.editable_record(record)},true)
				result.context[id] = row
			count += 1
			holder.free()
	# Export the chunk-owned scenery too: relief, mine, railway, flora and ruins.
	# Coarse silhouettes bound the map cost; 3D always uses the exact production meshes.
	var cell_count := 0
	for x in range(floori(bounds.position.x/region.CELL),ceili(bounds.end.x/region.CELL)):
		for z in range(floori(bounds.position.y/region.CELL),ceili(bounds.end.y/region.CELL)):
			var rect := Rect2(Vector2(x,z)*region.CELL,Vector2.ONE*region.CELL).intersection(bounds)
			var holder := Node3D.new()
			region.add_child(holder)
			region._build_surfaces(holder,rect)
			region._dress(holder,rect,Vector2i(x,z))
			for stage in region.EXPANSION.STAGES: region.EXPANSION.build_stage(holder,rect,stage,region._ground_height,region._decoration_clear)
			region.MINING_ART.build_chunk(holder,rect)
			var id := "context/desert/terrain/%d/%d"%[x,z]
			var row := CONTEXT.from_node(holder,id,"Deserto %d, %d"%[x,z],"terrain",Vector3(rect.get_center().x,0,rect.get_center().y))
			row.parts = coarse(row.parts,8.0)
			result.context[id] = row
			holder.free()
			cell_count += 1
			if cell_count%12 == 0:
				print("DESERT_CATALOG_CELLS ",cell_count)
				await parent.get_tree().process_frame
	result.coverage = {"records":count,"cells":cell_count}
	add_locations(result)
	region.free()
	return result

static func coarse(parts: Array, cell: float) -> Array:
	var cells := {}
	for part in parts:
		for x in range(floori(float(part[0])/cell),floori((float(part[0])+float(part[2]))/cell)+1):
			for z in range(floori(float(part[1])/cell),floori((float(part[1])+float(part[3]))/cell)+1):
				var key := Vector2i(x,z)
				if not cells.has(key) or float(cells[key][4])<float(part[4]): cells[key] = [x*cell,z*cell,cell,cell,part[4],part[5]]
	return cells.values()
