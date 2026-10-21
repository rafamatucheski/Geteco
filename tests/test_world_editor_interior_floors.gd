extends "res://tests/test_world_editor_interiors.gd"
func run() -> void:
	Engine.set_meta("geteco_live_preview_build",true)
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	var official := DATA.disk_hash()
	var definition := {}
	for row in CATALOG.definitions():
		if int(row.get("floor_count",0)) > 1: definition = row; break
	check(not definition.is_empty(),"Actual catalog contains a multiple-storey building")
	if definition.is_empty(): quit(1); return
	var id: String = definition.id
	var host := Node3D.new()
	root.add_child(host)
	var lower := CATALOG.build_preview(host,id,0)
	var upper := CATALOG.build_preview(host,id,1)
	var roof := CATALOG.build_preview(host,id,int(definition.floor_count))
	var rows0 := EDITS.manifest(lower.place,id)
	var rows1 := EDITS.manifest(upper.place,id)
	var roof_rows := EDITS.manifest(roof.place,id)
	check(not rows0.is_empty() and not rows1.is_empty() and not roof_rows.is_empty(),"Ground floor, upper floor and rooftop expose their actual furniture")
	check(rows0.all(func(value): return value.interior_floor == 0) and rows1.all(func(value): return value.interior_floor == 1),"Every piece identifies its own storey")
	var ids0 := rows0.map(func(value): return value.id)
	check(rows1.all(func(value): return not value.id in ids0),"Equal layouts on different floors have separate identities")
	var crate := DATA.new_entity("prop",Vector2(0,-2))
	crate.model = "crate"
	crate.interior_floor = 1
	var doc := DATA.empty_document()
	doc.interiors = {id:{crate.id:crate}}
	var path := "res://.godot/interior_floor_%d.json" % OS.get_process_id()
	check(DATA.save_document(doc,DATA.disk_hash(path),path).is_empty(),"Explicit Save persists an interior draft to isolated document")
	var loaded := DATA.read_document(path)
	check(str(loaded.error).is_empty() and loaded.document.interiors[id][crate.id].interior_floor == 1,"Saved interior additions preserve floor and independent object data")
	EDITS.prepare(lower.place,id,loaded.document)
	EDITS.prepare(upper.place,id,loaded.document)
	check(EDITS.content(lower.place,id).get_node("WorldInteriorAdded").get_child_count() == 0,"Upper floor addition never leaks onto ground floor")
	check(EDITS.content(upper.place,id).get_node("WorldInteriorAdded").get_child_count() == 1,"Upper floor addition appears on selected floor")
	var target := EDITS.content(upper.place,id)
	var added: Node3D = target.get_node("WorldInteriorAdded").get_child(0)
	check(absf(added.global_position.y-target.global_position.y) < .001,"Addition uses floor-local height without duplicating floor elevation")
	var jump := {}
	for row in roof_rows:
		if str(row.label) == "RoofJumpGate": jump = row; break
	check(not jump.is_empty(),"Rooftop jump gate is individually selectable")
	if not jump.is_empty():
		var room := EDITS.content(roof.place,id)
		var original: Vector3 = room.jump_point
		var change := {"id":jump.id,"type":"piece","source_record":jump.source_record,"position":[jump.position[0]+.5,jump.position[1]],"rotation":0,"interior_floor":int(definition.floor_count)}
		var roof_doc := DATA.empty_document()
		roof_doc.interiors = {id:{jump.id:change}}
		EDITS.prepare(roof.place,id,roof_doc)
		check(room.jump_point.distance_to(original+Vector3(.5,0,0)) < .001,"Rooftop vault interaction follows its moved gate")
		EDITS.prepare(roof.place,id,DATA.empty_document())
		check(room.jump_point.is_equal_approx(original),"Undo restores rooftop vault interaction")
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var restored := CATALOG.build_preview(host,id,1)
	check(EDITS.content(restored.place,id).get_node_or_null("WorldInteriorAdded") != null,"Runtime construction consumes saved upper-floor edits through admission hook")
	host.free()
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path+".bak"): DirAccess.remove_absolute(path+".bak")
	check(DATA.disk_hash() == official,"All interior tests preserve official world document")
	Engine.remove_meta("geteco_live_preview_build")
	Engine.remove_meta("geteco_world_edit_document")
	print("INTERIOR FLOORS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
