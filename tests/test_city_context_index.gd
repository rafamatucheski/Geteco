extends SceneTree
## Regressão funcional preparada; executar somente na janela coordenada.
const REGION := preload("res://world/regions/NativeRegion.gd")
const GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const EDITS := preload("res://world/editing/WorldEditRuntime.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_adversarial()
	_concentrated()
	_real_edits()
	_initial_prepare()
	print("%s CITY_CONTEXT_INDEX checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CITY_CONTEXT_INDEX: " + label)


# Oráculo literal da seleção anterior: não usa bins nem helpers do candidato.
func _linear(region: Node3D, rect: Rect2) -> Dictionary:
	var grown := rect.grow(16.0)
	var roads: Array = []
	var junctions: Array = []
	var geometry = region.get("harbor_road_geometry")
	if geometry != null:
		for road in geometry._roads:
			var points: PackedVector2Array = road.points
			var bounds := Rect2(points[0], Vector2.ZERO)
			for point in points: bounds = bounds.expand(point)
			if bounds.grow(float(road.width)).intersects(grown): roads.append(road)
		for junction in geometry._junctions:
			if grown.has_point(junction.position): junctions.append(junction)
	var buildings: Array = []
	for building in region.get("buildings"):
		var center := Vector2(building.position.x, building.position.z)
		var footprint := Rect2(center - building.size * 0.5, building.size)
		if footprint.grow(4.0).intersects(grown): buildings.append({"rect": footprint, "data": building})
	return {"roads": roads, "junctions": junctions, "buildings": buildings}


func _compare(region: Node3D, rect: Rect2, label: String) -> void:
	var expected := _linear(region, rect)
	var actual := DRESSING._context(region, rect)
	for kind in ["roads", "junctions", "buildings"]:
		var correct: bool = actual[kind].size() == expected[kind].size()
		if correct:
			for ordinal in expected[kind].size():
				if kind == "buildings":
					correct = correct and actual[kind][ordinal].rect == expected[kind][ordinal].rect and is_same(actual[kind][ordinal].data, expected[kind][ordinal].data)
				else:
					correct = correct and is_same(actual[kind][ordinal], expected[kind][ordinal])
		_check(correct, label + "/" + kind + "/conteúdo e ordem")
	_check(actual.region == region and actual.rect == rect and actual.geometry == region.harbor_road_geometry and actual.lamps.is_empty(), label + "/shape")


func _road(id: String, points: Array, width := 7.5) -> Dictionary:
	var packed := PackedVector3Array()
	for point in points: packed.append(Vector3(point.x, 0, point.y))
	return {"id": id, "points": packed, "width": width, "surface": "asphalt"}


func _building(id: String, position: Vector2, size := Vector2(10, 10)) -> Dictionary:
	return {"id": id, "position": Vector3(position.x, 0, position.y), "size": size, "kind": "office", "color": "8b8d80"}


func _adversarial() -> void:
	var region := REGION.new() # Fora da árvore: sem _ready nem mundo renderizado.
	var sources: Array[Dictionary] = [
		_road("same", [Vector2(200, 200), Vector2(264, 264)]),
		_road("same", [Vector2(-128, -128), Vector2(128, 128)]),
		_road("gap", [Vector2(-200, -200), Vector2(-200, 200), Vector2(200, 200)]),
		_road("wide", [Vector2(90, -128), Vector2(90, 128)], 30.0),
		_road("edge_v", [Vector2(80, -128), Vector2(80, 128)]),
		_road("edge_h", [Vector2(-128, 80), Vector2(128, 80)]),
		_road("huge", [Vector2(-10000, -10000), Vector2(10000, 10000)]),
	]
	region.harbor_road_geometry = GEOMETRY.new()
	region.harbor_road_geometry.configure(sources, false)
	region.buildings.append(_building("same", Vector2(72, 72)))
	region.buildings.append(_building("same", Vector2(-64, -64)))
	region.buildings.append(_building("border", Vector2(89, 20))) # footprint.grow(4) começa em x=80.
	for x in range(-3, 4):
		for y in range(-3, 4):
			_compare(region, Rect2(Vector2(x * 64, y * 64), Vector2(64, 64)), "grid/%d/%d" % [x, y])
	_compare(region, Rect2(Vector2.ZERO, Vector2.ZERO), "rect zero")
	_compare(region, Rect2(Vector2(-20000, -20000), Vector2(40000, 40000)), "query ampla")
	var context := DRESSING._context(region, Rect2(Vector2.ZERO, Vector2(64, 64)))
	_check(context.roads.any(func(row): return row.id == "gap"), "AABB inteira mantém lacuna distante dos segmentos")
	_check(context.roads.any(func(row): return row.id == "wide"), "margem da via é largura inteira")
	_check(region.harbor_road_geometry._junctions.any(func(row): return row.position.is_equal_approx(Vector2(80, 80))), "fixture contém junction na borda exclusiva")
	_check(context.junctions.all(func(row): return row.position.x < 80 and row.position.y < 80), "junction direita/baixo exclusivos")
	_check(not context.buildings.any(func(row): return row.data.id == "border"), "intersects não inclui apenas borda")
	var broad := DRESSING._context(region, Rect2(Vector2(-300, -300), Vector2(600, 600)))
	_check(broad.roads.filter(func(row): return row.id == "same").size() == 2, "IDs duplicados conservados")
	_check(region.get_meta(DRESSING.CONTEXT_META)._roads.overflow.size() > 0, "caixa enorme usa overflow sem expandir grade")
	var cache = region.get_meta(DRESSING.CONTEXT_META)
	_compare(region, Rect2(Vector2.ZERO, Vector2(64, 64)), "cache reutilizado")
	_check(is_same(cache, region.get_meta(DRESSING.CONTEXT_META)), "consulta reutiliza índice")
	if not context.buildings.is_empty(): context.buildings[0].rect = Rect2()
	_compare(region, Rect2(Vector2.ZERO, Vector2(64, 64)), "wrapper independente")
	# Mesma quantidade de vias, posições diferentes: tamanho não basta para invalidar.
	for source in sources:
		for i in source.points.size(): source.points[i] += Vector3(1024, 0, 1024)
	region.harbor_road_geometry.configure(sources, false)
	_compare(region, Rect2(Vector2.ZERO, Vector2(64, 64)), "reconfigure remove vias antigas")
	_compare(region, Rect2(Vector2(1024, 1024), Vector2(64, 64)), "reconfigure adiciona vias novas")
	_check(not is_same(cache, region.get_meta(DRESSING.CONTEXT_META)), "reconfigure troca índice")
	cache = region.get_meta(DRESSING.CONTEXT_META)
	var old_revision: int = region.harbor_road_geometry.context_revision
	region.harbor_road_geometry = GEOMETRY.new()
	region.harbor_road_geometry.configure([], false)
	region.harbor_road_geometry.configure([], false)
	_check(region.harbor_road_geometry.context_revision == old_revision, "fixture troca geometria na mesma revisão")
	_compare(region, Rect2(Vector2.ZERO, Vector2(64, 64)), "replacement geometry")
	_check(not is_same(cache, region.get_meta(DRESSING.CONTEXT_META)), "troca de geometria invalida mesmo com revisão igual")
	region.free()


func _concentrated() -> void:
	var region := REGION.new()
	for ordinal in 200:
		region.buildings.append(_building(str(ordinal), Vector2(16, 16)))
	var rect := Rect2(Vector2(4096, 4096), Vector2(64, 64))
	_compare(region, rect, "catálogo concentrado/célula distante vazia")
	var index = region.get_meta(DRESSING.CONTEXT_META)
	var candidates: Array = index._candidate_ordinals(index._buildings, rect.grow(16.0))
	_check(candidates.is_empty(), "consulta local vazia não varre 200 entradas em outra célula")
	_check(index._buildings.cells.size() == 1, "fixture mantém 200 entradas em uma célula")
	region.free()


func _real_edits() -> void:
	var saved_hash := FileAccess.get_sha256(DATA.PATH)
	var had_meta := Engine.has_meta("geteco_world_edit_document")
	var previous = Engine.get_meta("geteco_world_edit_document") if had_meta else null
	var region := REGION.new()
	region.buildings.append(_building("edit_me", Vector2.ZERO))
	region._record(Vector3.ZERO, {"kind": "building", "data": region.buildings[0]})
	region.roads.append(_road("edit_road", [Vector2(-20, 0), Vector2(20, 0)]))
	region.harbor_road_geometry = GEOMETRY.new()
	region.harbor_road_geometry.configure(region.roads, false)
	_compare(region, Rect2(Vector2(-32, -32), Vector2(64, 64)), "antes editor")
	var cache = region.get_meta(DRESSING.CONTEXT_META)
	var changes := {
		"building/edit_me": {"id": "building/edit_me", "type": "building", "position": [128.0, 128.0], "size": [20.0, 10.0], "height": 8.0, "model": "office", "rotation": 0.0, "color": "8b8d80"},
		"new/index_building": {"id": "new/index_building", "type": "building", "position": [0.0, 0.0], "size": [10.0, 10.0], "height": 7.5, "model": "office", "rotation": 0.0, "color": "8b8d80"},
		"road/edit_road": {"id": "road/edit_road", "type": "road", "points": [[108.0, 128.0], [148.0, 128.0]], "width": 12.0, "surface": "asphalt"},
	}
	var doc := DATA.empty_document()
	doc.regions.harbor = changes
	_check(DATA.validate_document(doc).is_empty(), "documento real de edição válido")
	Engine.set_meta("geteco_world_edit_document", doc)
	EDITS.apply(region)
	_check(not region.has_meta(DRESSING.CONTEXT_META), "apply real remove índice antes das mutações")
	# Cadeia produtiva de EditableRegion: apply, depois configure.
	region.harbor_road_geometry.configure(region.roads, false)
	_compare(region, Rect2(Vector2(-32, -32), Vector2(64, 64)), "editor origem")
	_compare(region, Rect2(Vector2(96, 96), Vector2(64, 64)), "editor destino")
	_check(not is_same(cache, region.get_meta(DRESSING.CONTEXT_META)), "editor reconstrói cache")
	_check(region.buildings.size() == 2 and region.buildings[0].position == Vector3(128, 0, 128), "editor aplicou mover/adicionar")
	_check(region.roads[0].width == 12.0 and region.roads[0].points[0].x > 100, "editor aplicou mudança real de via")
	# A exclusão na mesma instância usa identidade de origem do prédio base.
	# O editor produtivo reaplica new/* recriando EditableRegion a cada reload.
	doc.regions.harbor = {"building/edit_me": {"id": "building/edit_me", "type": "building", "deleted": true}}
	Engine.set_meta("geteco_world_edit_document", doc)
	EDITS.apply(region)
	_compare(region, Rect2(Vector2.ZERO, Vector2(256, 256)), "editor exclusão")
	_check(region.buildings.size() == 1 and region.buildings[0].editor_id == "new/index_building", "editor excluiu prédio base e preservou o novo não alterado")
	if had_meta: Engine.set_meta("geteco_world_edit_document", previous)
	else: Engine.remove_meta("geteco_world_edit_document")
	_check(FileAccess.get_sha256(DATA.PATH) == saved_hash, "arquivo oficial de edição preservado")
	region.free()


func _initial_prepare() -> void:
	var region := REGION.new()
	_compare(region, Rect2(Vector2.ZERO, Vector2(64, 64)), "região antes prepare")
	var cache = region.get_meta(DRESSING.CONTEXT_META)
	region.prepare_data() # Método produtivo, fora da árvore; não chama _ready.
	_check(region.data_prepared and not region.buildings.is_empty(), "prepare populou dados reais")
	for x in range(0, 10):
		for y in range(0, 10):
			_compare(region, Rect2(Vector2(x * 64, y * 64), Vector2(64, 64)), "dados reais/%d/%d" % [x, y])
	_check(not is_same(cache, region.get_meta(DRESSING.CONTEXT_META)), "prepare invalida cache anterior vazio")
	region.free()
