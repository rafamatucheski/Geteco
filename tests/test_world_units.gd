extends SceneTree
## Peças automáticas do editor de mundo: tudo que o cenário constrói (pedra, poste, fio,
## mobiliário) precisa ser listável, movível e removível sem tocar nos geradores.
## Uso: --script res://tests/test_world_units.gd -- --no-save [--explore]
const DATA := preload("res://world/editing/WorldEditData.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
const HARBOR := preload("res://world/editing/EditableRegion.gd")
const DESERT := preload("res://world/editing/EditableDesertRegion.gd")
const PLACEMENTS := preload("res://world/editing/WorldPlacements.gd")
const SESSION := preload("res://world/editing/WorldSessionEdits.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FALHOU: " + label)
	else: print("ok  ", label)

func build(area: String, focus: Vector3, document: Dictionary, preview: bool) -> Node3D:
	Engine.set_meta("geteco_live_preview_build", preview)
	Engine.set_meta("geteco_world_edit_document", document)
	var region: Node3D = DESERT.build_region(area, focus) if area == "desert" else HARBOR.build_region(area, focus)
	root.add_child(region)
	for i in 1800:
		await process_frame
		if region.is_streaming_idle(): break
	if preview: PLACEMENTS.explode_preview(region)
	return region

func summarize(rows: Array) -> Dictionary:
	var kinds := {}
	for row in rows:
		var bits := str(row.id).split("/")
		var key := "unit" if str(row.id).begins_with("piece/unit/") else bits[1] + "/" + bits[2]
		kinds[key] = int(kinds.get(key, 0)) + 1
	return kinds

func group_of(region: Node, id: String) -> Node3D:
	for group in PIECES.collect(region):
		if "piece/" + str(group.get_meta("world_edit_piece_id")) == id: return group
	return null

func authored(row: Dictionary, extra := {}) -> Dictionary:
	var result := {"id": row.id, "type": "piece", "position": row.position, "rotation": 0.0, "source_record": row.source_record}
	result.merge(extra, true)
	return result

## Peças automáticas mais as de catálogo (deserto), que já nascem como peças.
func rows_of(region: Node) -> Array:
	var rows := UNITS.manifest(region)
	for group in PIECES.collect(region):
		if group.has_meta("world_edit_auto") or not group.has_meta("world_edit_base"): continue
		var base: Dictionary = group.get_meta("world_edit_base")
		rows.append({"id": "piece/" + str(group.get_meta("world_edit_piece_id")), "label": str(group.get_meta("world_edit_label")), "position": base.pivot, "source_record": "catalogo"})
	return rows

## Prévia -> escolhe uma peça -> reconstrói sem prévia com a edição -> confere.
func cycle(area: String, focus: Vector3, wanted: String) -> void:
	var region := await build(area, focus, DATA.empty_document(), true)
	var rows := rows_of(region)
	var chosen := {}
	for row in rows:
		if wanted.to_lower() in str(row.label).to_lower() and (chosen.is_empty() or Vector2(row.position[0], row.position[1]).distance_to(Vector2(focus.x, focus.z)) < Vector2(chosen.position[0], chosen.position[1]).distance_to(Vector2(focus.x, focus.z))): chosen = row
	check(not chosen.is_empty(), "%s: achou peça '%s' na prévia" % [area, wanted])
	if chosen.is_empty():
		region.free()
		return
	var before := group_of(region, chosen.id)
	var origin := before.global_position
	check(before != null and not before.get_meta("world_edit_locked", false), "%s: %s está destravada" % [area, chosen.id.substr(0, 70)])
	region.free()
	await process_frame
	var target := [float(chosen.position[0]) + 6.0, float(chosen.position[1]) - 4.0]
	var document := DATA.empty_document()
	document.regions[area][chosen.id] = authored(chosen, {"position": target, "rotation": 30.0, "stretch": [1.5, 1.5], "height_stretch": 2.0, "lift": 0.5})
	check(DATA.validate_document(document).is_empty(), "%s: documento válido (%s)" % [area, DATA.validate_document(document)])
	region = await build(area, focus, document, false)
	var moved := group_of(region, chosen.id)
	check(moved != null, "%s: peça editada existe no jogo (sem prévia)" % area)
	if moved != null:
		check(absf(moved.global_position.x - target[0]) < .05 and absf(moved.global_position.z - target[1]) < .05, "%s: foi para a nova posição (%s)" % [area, str(moved.global_position)])
		check(moved.global_position.distance_to(origin) > 5.0, "%s: saiu do lugar original" % area)
	region.free()
	await process_frame
	document.regions[area][chosen.id] = authored(chosen, {"deleted": true})
	region = await build(area, focus, document, false)
	check(group_of(region, chosen.id) == null, "%s: excluída some do jogo" % area)
	region.free()
	await process_frame

## Cópia: a peça-mãe e a cópia existem; excluir a mãe mantém a cópia.
func clone_cycle(area: String, focus: Vector3, wanted: String) -> void:
	var region := await build(area, focus, DATA.empty_document(), true)
	var rows := rows_of(region)
	var chosen := {}
	for row in rows:
		if wanted.to_lower() in str(row.label).to_lower(): chosen = row; break
	check(not chosen.is_empty(), "%s: achou '%s' para copiar" % [area, wanted])
	if chosen.is_empty():
		region.free()
		return
	var origin := group_of(region, chosen.id).global_position
	region.free()
	await process_frame
	var copy_id := "piece/clone/test_%d" % randi()
	var document := DATA.empty_document()
	document.regions[area][copy_id] = {"id": copy_id, "type": "piece", "clone_of": chosen.id, "source_record": chosen.source_record, "position": [chosen.position[0] + 7.0, chosen.position[1]], "rotation": 90.0}
	check(DATA.validate_document(document).is_empty(), "%s: documento com cópia é válido (%s)" % [area, DATA.validate_document(document)])
	region = await build(area, focus, document, false)
	var mother := group_of(region, chosen.id)
	var copy := group_of(region, copy_id)
	check(mother != null and copy != null, "%s: mãe e cópia existem no jogo" % area)
	if mother != null and copy != null:
		check(mother.global_position.distance_to(origin) < .05, "%s: a mãe ficou onde estava" % area)
		check(absf(copy.global_position.x - (origin.x + 7.0)) < .1, "%s: a cópia está 7 m ao lado (%s)" % [area, str(copy.global_position)])
		check(copy.find_children("*", "MeshInstance3D", true, false).size() == mother.find_children("*", "MeshInstance3D", true, false).size(), "%s: a cópia tem as mesmas malhas" % area)
	region.free()
	await process_frame
	document.regions[area][chosen.id] = authored(chosen, {"deleted": true})
	region = await build(area, focus, document, false)
	check(group_of(region, chosen.id) == null and group_of(region, copy_id) != null, "%s: excluir a mãe mantém a cópia" % area)
	region.free()
	await process_frame

## Mobiliário em lote: a lista de colocações recebe a edição antes do MultiMesh nascer.
func placements() -> void:
	var region := await build("harbor", Vector3(45, 0, 110), DATA.empty_document(), true)
	var rows := UNITS.manifest(region)
	var found := {}
	for row in rows:
		if str(row.id).begins_with("piece/pl/"): found[row.label] = int(found.get(row.label, 0)) + 1
	print("   mobiliário editável na prévia: ", found)
	check(not found.is_empty(), "harbor: mobiliário em lote virou peças na prévia")
	check(found.has("Poste de calçada"), "harbor: poste de calçada é peça")
	var lamp := {}
	for row in rows:
		if str(row.id).begins_with("piece/pl/") and row.label == "Poste de calçada": lamp = row; break
	region.free()
	await process_frame
	if lamp.is_empty(): return
	var sample := Transform3D(Basis(Vector3.UP, .4), Vector3(float(lamp.position[0]), .012, float(lamp.position[1])))
	var chunk := Node3D.new()
	chunk.name = "Chunk_%s" % str(lamp.id).get_slice("/", 3)
	var fake := HARBOR.new()
	fake.region_id = "harbor"
	fake._piece_changes = {lamp.id: authored(lamp, {"position": [float(lamp.position[0]) + 4.0, float(lamp.position[1]) - 2.0], "rotation": 45.0, "lift": 1.0})}
	Engine.set_meta("geteco_live_preview_build", false)
	var batches := {"hydrant": [sample]}
	var edited: Array = PLACEMENTS._edit(fake, chunk, "sidewalk_lamp", [sample])
	check(edited.size() == 1 and absf(edited[0].origin.x - (sample.origin.x + 4.0)) < .01 and absf(edited[0].origin.y - 1.012) < .01, "placement: poste editado vai para a nova posição e sobe 1 m")
	fake._piece_changes = {lamp.id: authored(lamp, {"deleted": true})}
	check(PLACEMENTS._edit(fake, chunk, "sidewalk_lamp", [sample]).is_empty(), "placement: poste excluído sai da lista")
	var copy_id := "piece/clone/placement_test"
	fake._piece_changes = {copy_id: {"id": copy_id, "type": "piece", "clone_of": lamp.id, "source_record": "x", "position": [float(lamp.position[0]) + 3.0, float(lamp.position[1])], "rotation": 0.0}}
	check(PLACEMENTS._edit(fake, chunk, "sidewalk_lamp", [sample]).size() == 2, "placement: cópia acrescenta uma instância e mantém a original")
	fake.free()
	chunk.free()

## Mobília quebrável registrada no ponto original acompanha a peça movida.
func fragile() -> void:
	var FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
	var chunk := Node3D.new()
	root.add_child(chunk)
	var lamp := Node3D.new()
	lamp.position = Vector3(10, 0, 10)
	chunk.add_child(lamp)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	lamp.add_child(mesh)
	FRAGILE.register_node("trash_can", lamp, chunk)
	var group := PIECES.group(chunk, [lamp], "test/fragile", "Teste")
	var row := {"id": "piece/test/fragile", "type": "piece", "position": [30.0, 10.0], "rotation": 0.0, "source_record": "x"}
	PIECES.apply_one(group, {row.id: row}, Callable())
	check(FRAGILE.query(Vector3(30, 0, 10), 1.0).size() == 1, "fragile: o registro acompanha a peça movida (ponto novo)")
	check(FRAGILE.query(Vector3(10, 0, 10), 1.0).is_empty(), "fragile: nada fica registrado no ponto velho")
	chunk.free()
	FRAGILE.cells.clear()

## Lugar da sessão: o nó do lugar faz o papel de chunk.
func session() -> void:
	var node: Node3D = load("res://gameplay/urban_v1/VerticeCompany.gd").new()
	node.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(node)
	check(SESSION.place_of(node) == ["harbor", "vertice"], "sessão: Vértice é reconhecida pelo script")
	Engine.set_meta("geteco_live_preview_build", true)
	UNITS.finalize_session(node, "harbor", "vertice", {}, Callable())
	var rows := UNITS.manifest(node)
	print("   peças do Vértice: ", rows.size(), " ex.: ", rows[0].id if not rows.is_empty() else "", " @ ", rows[0].position if not rows.is_empty() else "")
	check(rows.size() > 3, "sessão: o Vértice virou várias peças")
	var chosen: Dictionary = rows[0] if not rows.is_empty() else {}
	node.free()
	await process_frame
	if chosen.is_empty(): return
	Engine.set_meta("geteco_live_preview_build", false)
	var node2: Node3D = load("res://gameplay/urban_v1/VerticeCompany.gd").new()
	node2.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(node2)
	var changes := {chosen.id: authored(chosen, {"position": [chosen.position[0] + 5.0, chosen.position[1]]})}
	UNITS.finalize_session(node2, "harbor", "vertice", changes, Callable())
	var moved := group_of(node2, chosen.id)
	check(moved != null and absf(moved.global_position.x - (chosen.position[0] + 5.0)) < .05, "sessão: peça do Vértice foi 5 m para o lado")
	node2.free()
	await process_frame

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if "--explore" in OS.get_cmdline_user_args():
		await explore()
	elif "--only-session" in OS.get_cmdline_user_args():
		await session()
		await fragile()
	else:
		await cycle("desert", Vector3(354.5, 0, -740), "Saguaro")
		await cycle("desert", Vector3(354.5, 0, -740), "Utility Pole")
		await cycle("harbor", Vector3(45, 0, 110), "Harbor Restaurant")
		await cycle("mountain", Vector3(700, 0, -260), "Rocks")
		await clone_cycle("desert", Vector3(354.5, 0, -740), "Saguaro")
		await clone_cycle("harbor", Vector3(45, 0, 110), "Harbor Restaurant")
		await placements()
		await fragile()
		await session()
	print("RESULT checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)

func explore() -> void:
	var document := DATA.empty_document()
	var areas := {"desert": Vector3(354.5, 0, -740), "harbor": Vector3(45, 0, 110), "mountain": Vector3(700, 0, -260)}
	for only in ["--only-desert", "--only-harbor", "--only-mountain"]:
		if only in OS.get_cmdline_user_args(): areas = {only.trim_prefix("--only-"): areas[only.trim_prefix("--only-")]}
	for area in areas:
		var began := Time.get_ticks_msec()
		var region := await build(area, areas[area], document, true)
		var rows := UNITS.manifest(region)
		print("[", area, "] peças automáticas: ", rows.size(), " em ", Time.get_ticks_msec() - began, " ms")
		var kinds := summarize(rows)
		var names := {}
		for row in rows: names[row.label] = int(names.get(row.label, 0)) + 1
		print("   tipos: ", kinds)
		print("   rótulos: ", names)
		var every := PIECES.collect(region)
		print("   grupos totais (inclui catálogo): ", every.size())
		check(rows.size() > 0, area + ": há peças automáticas")
		region.free()
		await process_frame
