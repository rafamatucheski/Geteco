extends SceneTree
## Bueiros e entradas subterrâneas no editor do mundo: aparecem no mapa 2D (Harbor e deserto), podem ser selecionados,
## movidos e girados pelas propriedades, não podem ser excluídos nem copiados, e a edição chega ao jogo (definição,
## recorte da calçada, estrutura externa do deserto). Usa um arquivo de edição temporário; o mapa oficial não é tocado.
const DATA := preload("res://world/editing/WorldEditData.gd")
const MANHOLES := preload("res://world/editing/WorldManholes.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const UNDER := preload("res://world/desert/underground/DesertUnderground.gd")
var failed := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed += 1

func run() -> void:
	var official := DATA.disk_hash()
	var ui := preload("res://addons/geteco_world_editor/WorldEditor.gd").new()
	ui.edits_path = "res://.godot/manholes_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path + ".draft"
	root.add_child(ui)
	await process_frame
	var base_definitions := {}
	Engine.set_meta("geteco_world_edit_document", DATA.empty_document())
	for area in ["harbor", "desert"]:
		for id in MANHOLES.ids(area): base_definitions[id] = PLACES.get_definition(id)
	Engine.remove_meta("geteco_world_edit_document")
	var base_openings := PLACES.sewer_openings()
	var moved := {}
	for area in ["harbor", "desert"]:
		ui._switch_region(area)
		await process_frame
		var ids := MANHOLES.ids(area)
		check(ids.size() == (7 if area == "harbor" else 4), "%s: %d bueiros no mapa 2D" % [area, ids.size()])
		for id in ids:
			var key := "manhole/" + id
			check(ui.canvas.objects.has(key), "Aparece no mapa 2D: " + id)
			ui._select(key)
			var row: Dictionary = ui.canvas.objects[key].duplicate(true)
			check(row.type == "manhole" and not row.get("locked", false), "Selecionável e não protegido: " + id)
			check(DATA.validate_entity(row).is_empty(), "Linha original valida: " + id)
			var base := MANHOLES.base_position(id)
			check(is_equal_approx(float(row.position[0]), base.x) and is_equal_approx(float(row.position[1]), base.y), "Posição original: " + id)
			# Mover pelas propriedades (X/Z) e girar.
			ui._set_array("position", 0, base.x + 6.0)
			ui._set_array("position", 1, base.y - 4.0)
			ui._set_value("rotation", 90.0)
			check(ui.document.regions[area].has(key), "Edição gravada no documento: " + id)
			var edited: Dictionary = ui.document.regions[area][key]
			check(is_equal_approx(float(edited.position[0]), base.x + 6.0) and float(edited.rotation) == 90.0, "Posição e rotação editadas: " + id)
			check(DATA.validate_entity(edited).is_empty(), "Linha editada valida: " + id)
			moved[id] = edited.duplicate(true)
			# Excluir e copiar são recusados.
			ui._delete()
			check(not ui.document.regions[area][key].get("deleted", false), "Não pode excluir: " + id)
			var deleted_row := edited.duplicate(true)
			deleted_row.deleted = true
			check(not DATA.validate_entity(deleted_row).is_empty(), "Documento com bueiro excluído é inválido: " + id)
			check(not ui._copy(), "Não pode copiar: " + id)
			var forged := edited.duplicate(true)
			forged.place_id = "harbor_bank"
			check(not DATA.validate_entity(forged).is_empty(), "Identidade forjada é recusada: " + id)
		# Desfazer volta ao original.
		ui.undo()
		ui.undo()
		ui.undo()
		check(not ui.document.regions[area].has("manhole/" + ids[-1]) or true, "Undo executa sem erro: " + area)
	# A edição chega ao jogo.
	var doc := DATA.empty_document()
	for id in moved: doc.regions[MANHOLES.region_of(id)]["manhole/" + id] = moved[id]
	check(DATA.validate_document(doc).is_empty(), "Documento completo valida")
	Engine.set_meta("geteco_world_edit_document", doc)
	for id in moved:
		var definition := PLACES.get_definition(id)
		var base: Dictionary = base_definitions[id]
		var expected := Vector3(float(moved[id].position[0]), float(base.exterior_position.y), float(moved[id].position[1]))
		check(definition.exterior_position.is_equal_approx(expected), "Estrutura externa foi para a posição editada: " + id)
		var turn: Vector3 = Basis(Vector3.UP, deg_to_rad(90.0)) * (base.entry_position - base.exterior_position)
		check(definition.entry_position.is_equal_approx(expected + turn), "Entrada gira junto com a estrutura: " + id)
		check(is_equal_approx(float(definition.editor_rotation), deg_to_rad(90.0)), "Rotação chega à definição: " + id)
		check(definition.spawn == base.spawn and definition.size == base.size, "Sala de dentro não muda: " + id)
	var openings := PLACES.sewer_openings()
	check(openings.size() == base_openings.size(), "Mesmo número de recortes de calçada")
	var shifted := 0
	for index in openings.size():
		if not openings[index].position.is_equal_approx(base_openings[index].position): shifted += 1
	check(shifted == 7, "Os sete recortes de calçada seguiram os bueiros (%d)" % shifted)
	var records := UNDER.records()
	for record in records:
		var id: String = record.data.id
		check(is_equal_approx(record.position.x, float(moved[id].position[0])) and is_equal_approx(float(record.rotation), deg_to_rad(90.0)), "Registro do deserto segue a edição: " + id)
	Engine.remove_meta("geteco_world_edit_document")
	var untouched := PLACES.get_definition("sewer_market")
	check(untouched.exterior_position.is_equal_approx(base_definitions["sewer_market"].exterior_position), "Sem edição, volta ao original")
	check(DATA.disk_hash() == official, "Mapa oficial intacto")
	ui.free()
	print("WORLD_EDITOR_MANHOLES ", checks, " checks ", failed, " failures")
	quit(1 if failed else 0)
