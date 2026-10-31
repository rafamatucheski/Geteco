@tool
extends RefCounted
## JSON compartilhado por editor e produção; sem nós de editor nem laço por quadro no jogo.
const PATH := "res://world/editing/world_edits.json"
const TYPES := ["tree", "building", "road", "light", "prop", "piece", "ground", "manhole", "terrain"]
const PROP_TYPES := ["pallet", "pallet_stack", "crate", "barrel", "dumpster", "trash_bags", "bin", "barrier", "footbridge", "desert_cactus", "desert_rock"]
const BUILDING_TYPES := ["office", "brownstone", "warehouse", "corner_shop", "cobra_house", "l_shaped_block"] + preload("res://world/urban_detail/UrbanSkylineCatalog.gd").TYPES + preload("res://world/urban_detail/UrbanLowriseCatalog.gd").TYPES
const BUILDING_LABELS := ["Comercial","Residencial","Galpão","Loja","Casa dos Cobra","Prédio em L"] + preload("res://world/urban_detail/UrbanSkylineCatalog.gd").LABELS + preload("res://world/urban_detail/UrbanLowriseCatalog.gd").LABELS
# Nada é travado desde 10/10/2026; a lista segue só para avisar na interface (aviso, não bloqueio).
const LOCKED_BUILDINGS := ["Garage", "NorthFrontage0", "NorthFrontage2", "NorthFrontage3", "NorthFrontage4", "Police", "Clinic", "NorthFireStation", "CanalHomesWest", "NorthgateAuto"]

static func empty_document() -> Dictionary:
	return {"version": 1, "regions": {"harbor": {}, "mountain": {}, "desert": {}}, "interiors":{}}

static func read_document(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {"document": empty_document(), "error": ""}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"document": {}, "error": "JSON inválido: " + parser.get_error_message()}
	var error := validate_document(parser.data)
	if error.is_empty() and not parser.data.regions.has("desert"): parser.data.regions.desert = {}
	return {"document": parser.data if error.is_empty() else {}, "error": error}

static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for item in value:
		if not number(item) or absf(float(item)) > 10000.0: return false
	return true

static func validate_entity(row: Variant) -> String:
	if not row is Dictionary: return "Objeto inválido."
	if row.get("type", "") not in TYPES: return "Tipo de objeto inválido."
	if not row.get("id", "") is String or row.get("id", "").is_empty(): return "ID ausente."
	if not row.get("deleted", false) is bool: return "Exclusão inválida."
	if row.has("interior_floor") and (not number(row.interior_floor) or float(row.interior_floor) < 0 or floorf(float(row.interior_floor)) != float(row.interior_floor)): return "O andar do interior deve ser um inteiro a partir de zero."
	if row.type == "piece":
		if not str(row.id).begins_with("piece/") or not row.get("source_record", "") is String or str(row.get("source_record", "")).is_empty(): return "Peça sem origem."
	if row.type == "manhole":
		if not row.get("place_id","") is String or not preload("res://world/editing/WorldManholes.gd").is_editable(str(row.place_id)): return "Bueiro desconhecido."
		if str(row.id) != "manhole/"+str(row.place_id): return "Identidade do bueiro alterada."
	if row.get("deleted", false): return ""
	if row.type == "terrain": return preload("res://world/editing/WorldTerrainEdits.gd").validate_row(row)
	if row.get("service_building",false):
		var base: Variant = row.get("service_base")
		if row.type != "building" or not base is Dictionary or not vector(base.get("position"),2) or not vector(base.get("size"),2) or not number(base.get("height")) or base.height <= 0: return "Prédio especial sem referência original."
		if not vector(row.get("size"),2) or not number(row.get("height")): return "Dimensões inválidas."
		if row.get("model") != base.get("model"): return "Preserve a identidade do estabelecimento."
		for i in 2:
			if base.size[i] <= 0 or row.size[i] <= .5 or row.size[i] > 1000: return "Dimensão do prédio especial inválida."
		if row.height <= .5 or row.height > 1000: return "Altura do prédio especial inválida."
	if row.has("paving") and not row.paving is bool: return "Origem do piso inválida."
	if row.get("paving",false):
		if row.type != "ground" or not str(row.id).begins_with("paving/"): return "Piso existente sem origem."
		if row.get("rotation",0) != 0 or row.has("outline"): return "Pisos existentes são retangulares: ajuste posição e tamanho."
		if row.get("surface","") not in ["concrete","pavers"]: return "Acabamento de calçada inválido."
	if row.has("stretch"):
		if row.type != "piece" or not vector(row.stretch,2) or row.stretch[0] < .02 or row.stretch[1] < .02 or row.stretch[0] > 30 or row.stretch[1] > 30: return "Escala da peça: 0,02 a 30 por eixo."
	if row.has("clone_of") and (row.type != "piece" or not row.clone_of is String or not str(row.clone_of).begins_with("piece/") or not str(row.id).begins_with("piece/clone/")): return "Cópia de peça inválida."
	if row.has("height_stretch") and (row.type != "piece" or not number(row.height_stretch) or row.height_stretch < .02 or row.height_stretch > 30): return "Altura da peça: 0,02 a 30 vezes."
	if row.has("lift") and (row.type != "piece" or not number(row.lift) or absf(row.lift) > 3000): return "Elevação da peça: até 3000 m."
	if row.has("outline"):
		if row.type not in ["piece","ground"]: return "Este objeto não tem contorno editável."
		if row.type == "piece" and not preload("res://world/editing/WorldEditPieces.gd").is_shape_editable(str(row.get("clone_of",row.id))): return "Esta peça não permite mudar o contorno."
		var shape_error := validate_outline(row.outline)
		if not shape_error.is_empty(): return shape_error
	if row.type == "road":
		if not row.get("points") is Array or row.points.size() < 2 or row.points.size() > 2048: return "Rua precisa de 2 a 2048 pontos."
		if not row.get("pathway",false) is bool: return "Tipo de caminho inválido."
		var minimum := .5
		if not number(row.get("width")) or row.width < minimum or row.width > 120.0: return "Largura de via inválida."
		if row.has("lanes_per_direction"):
			if not number(row.lanes_per_direction) or (float(row.lanes_per_direction) != 1.0 and float(row.lanes_per_direction) != 2.0): return "Use uma ou duas faixas por sentido."
			if int(row.lanes_per_direction)==2 and (row.get("pathway",false) or row.width < 12): return "Quatro faixas exigem ao menos 12 m de pista."
		for i in row.points.size():
			if not vector(row.points[i], 2): return "Ponto de rua inválido."
			if i > 0 and point(row.points[i]).distance_to(point(row.points[i-1])) < .25: return "Pontos consecutivos precisam de 25 cm de distância."
		if row.get("surface", "asphalt") not in ["asphalt", "earth"]: return "Piso inválido."
		for field in ["sidewalk_width","crossing_offset","crossing_depth"]:
			if row.has(field) and (not number(row[field]) or row[field] < 0 or row[field] > 10): return "Ajuste de calçada/faixa: 0 a 10 m."
		if row.has("crossings") and not row.crossings is bool: return "Opção de faixas inválida."
		if row.has("crossing_entries"):
			if not row.crossing_entries is Dictionary or row.crossing_entries.size() > 1024: return "Entradas de cruzamento inválidas."
			for key in row.crossing_entries:
				var entry: Variant = row.crossing_entries[key]
				if not key is String or key.length() > 4096 or not entry is Dictionary: return "Entrada de cruzamento inválida."
				if entry.get("mode","auto") not in ["auto","on","off"]: return "Opção de faixa inválida."
				if not entry.get("stop",true) is bool: return "Linha de parada inválida."
				if not number(entry.get("offset",0)) or entry.get("offset",0) < 0 or entry.get("offset",0) > 10: return "Afastamento da faixa: 0 a 10 m."
				if not number(entry.get("depth",1.875)) or entry.get("depth",1.875) < .5 or entry.get("depth",1.875) > 5: return "Profundidade da faixa: 0,5 a 5 m."
		if row.has("crossing_depth") and (row.crossing_depth < .5 or row.crossing_depth > 5): return "Profundidade da faixa: 0,5 a 5 m."
	else:
		if not vector(row.get("position"), 2): return "Posição inválida."
		if not number(row.get("rotation")): return "Rotação inválida."
		if row.type == "ground":
			if row.get("surface", "") not in ["grass","earth","sand","gravel","concrete","asphalt","pavers"]: return "Piso inválido."
			var minimum := .25
			var maximum := 2000.0
			if not vector(row.get("size"),2) or row.size[0] < minimum or row.size[1] < minimum or row.size[0] > maximum or row.size[1] > maximum: return "Dimensões do piso fora do limite."
		elif row.type == "prop":
			if row.get("model", "") not in PROP_TYPES and row.get("model", "") != "static_snapshot": return "Modelo de objeto inválido."
			if row.get("model", "") == "static_snapshot" and not preload("res://world/editing/WorldStaticSnapshots.gd").valid_id(row.get("snapshot_id")): return "Cópia estática sem recurso válido."
			if not vector(row.get("size"),2) or row.size[0] <= 0 or row.size[1] <= 0: return "Dimensões de objeto inválidas."
			if not number(row.get("scale")) or row.scale < .05 or row.scale > 30: return "Escala do objeto: 0,05 a 30."
			if row.model == "footbridge" and (row.size[0] < .8 or row.size[0] > 30 or row.size[1] < 14 or row.size[1] > 300): return "Passarela: largura 0,8 a 30 m, comprimento 14 a 300 m."
		elif row.type == "tree":
			if not number(row.get("scale")) or row.get("scale", 1.0) < .05 or row.get("scale", 1.0) > 30.0: return "Escala da árvore: 0,05 a 30."
			if not number(row.get("variant")) or row.get("variant", 0) < 0 or row.get("variant", 0) > 7: return "Variante da árvore inválida."
			if not row.get("snow") is bool: return "Neve inválida."
		elif row.type == "building":
			if not row.get("model") is String or row.model.is_empty(): return "Modelo de prédio ausente."
			if not vector(row.get("size"), 2) or row.size[0] < 1 or row.size[1] < 1 or row.size[0] > 1000 or row.size[1] > 1000: return "Dimensões do prédio: 1 a 1000 m."
			if not number(row.get("height")) or row.get("height", 7.5) < 1 or row.get("height", 7.5) > 1000: return "Altura do prédio: 1 a 1000 m."
		elif row.type == "light":
			for field in ["energy", "range", "height"]:
				if not number(row.get(field)): return "Valor de luz inválido."
			if row.energy < 0 or row.energy > 100 or row.range < .5 or row.range > 500 or row.height < .5 or row.height > 200: return "Luz: energia 0–100, alcance 0,5–500 m e altura 0,5–200 m."
		if row.type in ["building","light"] and not row.has("color"): return "Cor ausente."
		if row.has("color") and (not row.color is String or not Color.html_is_valid(row.color)): return "Cor inválida."
	return ""

static func validate_outline(value: Variant) -> String:
	if not value is Array or value.size() < 3 or value.size() > 256: return "Contorno precisa de 3 a 256 pontos."
	var polygon := PackedVector2Array()
	for item in value:
		if not vector(item,2) or absf(float(item[0])) > 2000 or absf(float(item[1])) > 2000: return "Ponto fora do limite do contorno."
		polygon.append(point(item))
	var area := 0.0
	for i in polygon.size():
		var next := (i+1)%polygon.size()
		if polygon[i].distance_to(polygon[next]) < .05: return "Pontos precisam de pelo menos 5 cm de distância."
		area += polygon[i].cross(polygon[next])
		for j in range(i+1,polygon.size()):
			var end := (j+1)%polygon.size()
			if j == next or end == i: continue
			if Geometry2D.segment_intersects_segment(polygon[i],polygon[next],polygon[j],polygon[end]) != null: return "As bordas do contorno não podem se cruzar."
	if absf(area) < .02 or Geometry2D.triangulate_polygon(polygon).is_empty(): return "Contorno sem área válida."
	return ""

static func validate_document(doc: Variant) -> String:
	if not doc is Dictionary or doc.get("version") != 1 or not doc.get("regions") is Dictionary: return "Formato de mundo incompatível."
	if not doc.regions.has("harbor") or not doc.regions.has("mountain"): return "Faltam regiões no documento."
	for region in doc.regions:
		if region not in ["harbor", "mountain", "desert"] or not doc.regions[region] is Dictionary: return "Região inválida."
		for id in doc.regions[region]:
			var row: Variant = doc.regions[region][id]
			var error := validate_entity(row)
			if not error.is_empty(): return str(id) + ": " + error
			if row.id != id: return "ID da chave não corresponde ao objeto."
			if row.type == "terrain" and not row.get("deleted",false):
				var expected_region := "harbor" if row.target == "motocross" else "mountain"
				if region != expected_region: return "O pincel pertence ao terreno de outra região."
	var interiors: Variant = doc.get("interiors",{})
	if not interiors is Dictionary: return "Interiores inválidos."
	for place in interiors:
		if not place is String or place.is_empty() or place.length() > 256 or not interiors[place] is Dictionary: return "Identidade do interior inválida."
		for id in interiors[place]:
			var row: Variant = interiors[place][id]
			if not row is Dictionary or row.get("type","") not in ["prop","tree","ground","light","building","piece"]: return "Objeto não permitido em interior."
			var error := validate_entity(row)
			if not error.is_empty(): return str(place)+" / "+str(id)+": "+error
			if row.id != id: return "ID do objeto interior não corresponde à chave."
			if row.type == "piece" and (not str(id).begins_with("piece/interior/"+place+"/") or not str(row.get("source_record","")).begins_with("interior/"+place+"/")): return "Peça de interior sem origem correspondente."
	return ""

static func disk_hash(path: String = PATH) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

static func save_document(doc: Dictionary, expected_hash: String, path: String = PATH) -> String:
	var error := validate_document(doc)
	if not error.is_empty(): return error
	if disk_hash(path) != expected_hash: return "Arquivo mudou fora do editor. Reabra o editor antes de salvar; suas alterações continuam na tela."
	var temporary := path + "." + str(OS.get_process_id()) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Não foi possível gravar: " + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(doc, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return "Falha de gravação: " + error_string(write_error)
	if disk_hash(path) != expected_hash: return "Arquivo mudou durante a gravação. Nada foi substituído."
	if FileAccess.file_exists(path):
		var backup := DirAccess.copy_absolute(path, path + ".bak")
		if backup != OK: return "Não foi possível guardar a cópia anterior."
	var result := DirAccess.rename_absolute(temporary, path)
	return "" if result == OK else "Falha ao salvar: " + error_string(result)

static func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func xyz(value: Array) -> Vector3:
	return Vector3(float(value[0]), 0, float(value[1]))

static func xy(value: Vector3) -> Array:
	return [value.x, value.z]

static func record_id(record: Dictionary) -> String:
	match str(record.kind):
		"building": return "building/" + str(record.data.id)
		"harbor_prop":
			if record.data.kind in ["tree", "lamp"]: return "harbor_prop/%s/%.5f/%.5f" % [record.data.kind, record.position.x, record.position.z]
		"tree", "mountain_road_lamp":
			return "%s/%.5f/%.5f" % [record.kind, record.position.x, record.position.z]
	return ""

static func normalize_catalog_heights(regions: Dictionary) -> void:
	# Catálogos antigos em cache usavam 7.5 para todo prédio sem sobreposição. Atualiza só
	# linhas base; edições salvas do usuário mantêm as alturas autoradas explicitamente.
	for area in regions.values():
		for row in area.get("objects",{}).values():
			if row.get("type","") != "building" or row.get("height_resolved",false): continue
			var source := {"id":str(row.id).trim_prefix("building/"),"kind":row.model}
			if not is_equal_approx(float(row.height),7.5): source.height_override = row.height
			row.height = preload("res://world/urban_detail/UrbanBuildingFactory.gd").resolved_height(source)
			row.height_resolved = true
	for area in regions.values():
		for row in area.get("objects",{}).values(): preload("res://world/editing/WorldServiceBuildings.gd").upgrade(row)

static func catalog(region: Node) -> Dictionary:
	var result := {}
	if region.region_id == "harbor": result.merge(preload("res://world/editing/WorldPaving.gd").catalog())
	result.merge(preload("res://world/editing/WorldManholes.gd").catalog(str(region.region_id)))
	for road in region.roads:
		var points: Array = []
		for p in road.points: points.append(xy(p))
		var id := "road/" + str(road.id)
		result[id] = {"id": id, "type": "road", "points": points, "width": road.width, "surface": road.get("surface", "asphalt")}
		result[id].lanes_per_direction = int(road.get("lanes_per_direction",1))
	for rows in region.records.values():
		for row in rows:
			var id := record_id(row)
			if id.is_empty(): continue
			if row.kind == "harbor_prop":
				if row.data.kind == "tree":
					result[id] = {"id":id,"type":"tree","position":xy(row.position),"variant":row.data.style,"scale":row.data.scale_factor,"color":row.data.color,"tree_model":"harbor","snow":false,"rotation":0.0}
				else:
					result[id] = {"id":id,"type":"light","position":xy(row.position),"height":4.0,"energy":1.15,"range":10.0,"color":"ffe0ab","rotation":0.0}
			elif row.kind == "building":
				var b: Dictionary = row.data
				result[id] = {"id": id, "type": "building", "position": xy(b.position), "size": [b.size.x, b.size.y], "height": preload("res://world/urban_detail/UrbanBuildingFactory.gd").resolved_height(b), "height_resolved": true, "rotation": 0.0, "model": b.get("kind", "office"), "color": b.get("color", "8b8d80"), "locked": b.id in LOCKED_BUILDINGS or b.get("kind", "") in ["garage", "hospital", "weapons", "police_precinct", "fire_station"]}
			elif row.kind == "tree":
				result[id] = {"id": id, "type": "tree", "position": xy(row.position), "variant": row.variant, "snow": row.snow, "scale": 1.0, "rotation": 0.0}
			elif row.kind == "mountain_road_lamp":
				result[id] = {"id": id, "type": "light", "position": xy(row.position), "height": 3.45, "energy": 1.15, "range": 10.0, "color": "ffe0ab", "rotation": 0.0}
	result.merge(preload("res://world/editing/WorldEditRoads.gd").catalog_walkways(region))
	for row in result.values(): preload("res://world/editing/WorldServiceBuildings.gd").upgrade(row)
	return result

static func effective(base: Dictionary, changes: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for id in changes:
		if changes[id].get("deleted", false): result.erase(id)
		else: result[id] = changes[id].duplicate(true)
	return result

static func new_entity(type: String, position: Vector2) -> Dictionary:
	if type == "terrain": return preload("res://world/editing/WorldTerrainEdits.gd").new_brush(position)
	var id := "new/" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(randi())
	var row := {"id": id, "type": type, "position": [position.x, position.y], "rotation": 0.0}
	match type:
		"ground": row.merge({"size":[8.0,8.0], "surface":"grass"})
		"prop": row.merge({"model":"pallet", "scale":1.0, "size":[1.2,1.0], "color":"a98857"})
		"tree": row.merge({"variant": 0, "snow": false, "scale": 1.0})
		"building": row.merge({"size": [10.0, 10.0], "height": 7.5, "model": "office", "color": "8b8d80"})
		"light": row.merge({"height": 4.0, "energy": 1.15, "range": 10.0, "color": "ffe0ab"})
		"road":
			row.erase("position")
			row.merge({"points": [[position.x-10, position.y], [position.x+10, position.y]], "width": 7.5, "surface": "asphalt"})
	return row
