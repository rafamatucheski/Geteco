extends SceneTree

## Escritórios A/B/C em Harbor (pacotes escritorio-a/b/c no modo alto do
## PaintedFacadeKit): estilo importado com as medidas do pacote (térreo 4 m, andar
## 3 m, topo 3 m, módulo 12 m, lateral 6 m), interruptor GETECO_PAINTED_OFFICES,
## largura limitada a 1,15x o módulo, soleira da porta da frente na calçada sem
## afundar mais que o embasamento pintado, noite acendendo, e no prédio do jogo:
## kit único sem o casco antigo, largura/cobertura do catálogo iguais à casca e a
## entrada de verdade no vão pintado.
## Não olha a imagem nem mede desempenho (capturas: tests/capture/capture_painted_offices_ingame.gd).

const TALL := preload("res://world/urban_detail/PaintedTallBuildings.gd")
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const OFFICES := {"BridgeCourtEast": "escritorio-a", "NorthFrontage5": "escritorio-b", "NorthbankFront2": "escritorio-c"}
## Embasamento pintado abaixo da soleira, medido nas imagens do térreo (A 0,21 m,
## C 0,19 m, B 0): afundar mais que isso enterraria a vitrine.
const MAX_SINK := 0.25
var failures: Array = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func _init() -> void:
	OS.set_environment("GETECO_PAINTED_TALL", "1")
	OS.set_environment("GETECO_PAINTED_OFFICES", "0")
	for id in OFFICES:
		check(TALL.style_for(id).is_empty(), "%s: GETECO_PAINTED_OFFICES=0 não desligou" % id)
		check(is_equal_approx(TALL.footprint_width(id, 15.0), 15.0), "%s: largura mudou desligado" % id)
	check(TALL.style_for("CivicTower") == "torre-civica", "interruptor dos escritórios desligou a CivicTower")
	OS.set_environment("GETECO_PAINTED_OFFICES", "1")
	for id in OFFICES:
		var style: String = OFFICES[id]
		check(TALL.style_for(id) == style, "%s: style_for=%s" % [id, TALL.style_for(id)])
		check(PaintedHarborHouses.style_for(id, "office") == style, "%s: PaintedHarborHouses não devolve %s" % [id, style])
		_check_style(style)
		await _check_kit(style)
		await _check_game_building(id, style)
	print("PAINTED_OFFICES checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)


func _check_style(style: String) -> void:
	check(PaintedFacadeKit.is_tall(style), "%s não é alto" % style)
	var data := PaintedFacadeKit.style_data(style)
	var floors: Array = data.get("floors", [])
	check(floors.size() == 3 and is_equal_approx(float(floors[0]), 4.0) and is_equal_approx(float(floors[1]), 3.0) and is_equal_approx(float(floors[2]), 3.0), "%s: floors %s" % [style, floors])
	var natural := PaintedFacadeKit.natural_size(style)
	check(is_equal_approx(natural.x, 12.0) and is_equal_approx(natural.z, 6.0), "%s: módulo %s" % [style, natural])
	for side in ["front", "back"]:
		check(PaintedFacadeKit.openings(style, side).size() == 1, "%s: %d vãos em %s" % [style, PaintedFacadeKit.openings(style, side).size(), side])
	PaintedWindow.set_night(1.0)
	for side in ["front", "side", "back"]:
		for piece in ["ground", "floor", "top"]:
			var part: String = side + "_" + piece
			var mat := PaintedFacadeKit.material(style, part)
			check(mat.albedo_texture != null, "%s/%s sem textura" % [style, part])
			check(mat.emission_enabled and mat.emission_texture != null and mat.emission_energy_multiplier > 1.0, "%s/%s não acende à noite" % [style, part])
		# Emenda vertical do andar repetido: só informa (o pacote registra que não é
		# perfeita; a captura em jogo é quem julga).
		var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/facades/%s/%s_floor.jpg" % [style, side]))
		if image != null and not image.is_empty():
			var steps: Array[float] = []
			for y in image.get_height() - 1: steps.append(_row_diff(image, y, y + 1))
			steps.sort()
			print("emenda %s/%s_floor: borda=%.4f p90=%.4f" % [style, side, _row_diff(image, image.get_height() - 1, 0), steps[int(steps.size() * 0.9)]])
	PaintedWindow.set_night(0.0)
	for part in ["roof", "door_front", "door_front_inside", "door_back", "door_back_inside"]:
		check(ResourceLoader.exists(PaintedFacadeKit.ROOT + style + "/" + part + ".jpg"), "%s/%s.jpg ausente" % [style, part])


func _row_diff(image: Image, a: int, b: int) -> float:
	var total := 0.0
	var samples := 0
	for x in range(0, image.get_width(), 3):
		var p := image.get_pixel(x, a)
		var q := image.get_pixel(x, b)
		total += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
		samples += 1
	return total / float(samples)


func _check_kit(style: String) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var solid := Node3D.new()
	holder.add_child(solid)
	var rect: Array = PaintedFacadeKit.openings(style, "front")[0].rect
	var width := 13.8
	var kit := PaintedFacadeKit.build(holder, style, Vector3(width, 10.0, 11.0), solid, width * (float(rect[0]) + float(rect[2])) * 0.5 - width * 0.5)
	await process_frame
	check(int(kit.get_meta("tall_floors", -1)) == 1, "%s: %s andares em 10 m" % [style, kit.get_meta("tall_floors", -1)])
	var sink := float(kit.get_meta("ground_sink", 0.0))
	check(sink <= MAX_SINK, "%s: afunda %.2f m (embasamento pintado ≤ %.2f)" % [style, sink, MAX_SINK])
	var walk_ins := 0
	for anchor: Node3D in kit.find_children("Doorway_*", "Node3D", false, false):
		if String(anchor.name).begins_with("Doorway_front"):
			var sill: float = anchor.global_position.y - holder.global_position.y
			check(absf(sill) <= 0.08, "%s %s: soleira a %.2f m da calçada" % [style, anchor.name, sill])
		if anchor.get_meta("walk_in", false): walk_ins += 1
	check(walk_ins == 1, "%s: %d entradas de verdade" % [style, walk_ins])
	holder.queue_free()
	await process_frame


func _check_game_building(id: String, style: String) -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var row := {}
	for r in rows:
		if str(r.get("id", "")) == id: row = r
	check(not row.is_empty(), "%s fora de OriginalWorldData" % id)
	if row.is_empty(): return
	var original_w := float(row.size[0]) / 16.0
	var building: Node3D = UrbanBuildingFactory.build_building(row)
	root.add_child(building)
	await process_frame
	check(is_equal_approx(building.building_size.x, minf(original_w, 12.0 * 1.15)), "%s: largura %.2f (lote %.2f)" % [id, building.building_size.x, original_w])
	var kits := building.find_children("PaintedFacade_" + style, "Node3D", true, false)
	check(kits.size() == 1, "%s: %d kits" % [id, kits.size()])
	check(building.find_children("CommercialBody", "", true, false).is_empty(), "%s: casco antigo junto com o pintado" % id)
	if kits.size() != 1:
		building.queue_free()
		return
	var kit: Node3D = kits[0]
	var def: Dictionary = CATALOG.for_source(id)
	check(not def.is_empty(), "%s fora do catálogo" % id)
	if not def.is_empty():
		check(absf(float(def.size.x) - float(building.building_size.x)) < 0.01, "%s: largura catálogo %s != prédio %s" % [id, def.size.x, building.building_size.x])
		var height := float(kit.get_meta("painted_height", 0.0)) - float(kit.get_meta("ground_sink", 0.0))
		check(absf(float(def.roof_height) - (height + 0.1)) < 0.02, "%s: cobertura do catálogo %.2f, casca %.2f" % [id, def.roof_height, height])
		check(float(def.storey_height) * int(def.floor_count) <= height + 0.01, "%s: interior (%d x %.2f) acima da casca %.2f" % [id, def.floor_count, def.storey_height, height])
		# Centro do vão (porta simples ou dupla): ombreira + metade da largura pintada.
		var entry_x: float = (def.entrance_local as Vector3).x
		var rect: Array = PaintedFacadeKit.openings(style, "front")[0].rect
		var opening_w: float = (float(rect[2]) - float(rect[0])) * float(building.building_size.x)
		var found := false
		for anchor: Node3D in kit.find_children("Doorway_front*", "Node3D", false, false):
			if not anchor.get_meta("walk_in", false): continue
			found = true
			check(anchor.get_node_or_null("Door") != null, "%s: entrada sem folha" % id)
			var center: float = anchor.position.x + opening_w * 0.5
			check(absf(center - entry_x) <= 0.5, "%s: entrada do catálogo x=%.2f, vão em %.2f" % [id, entry_x, center])
			check(absf(anchor.global_position.y - building.global_position.y) <= 0.08, "%s: soleira fora da calçada" % id)
			print("%s: vão %.2f m, porta %s, entrada x=%.2f" % [id, opening_w, "dupla" if anchor.get_node_or_null("Door2") != null else "simples", entry_x])
		check(found, "%s: nenhuma folha walk_in na frente" % id)
	building.queue_free()
	await process_frame
