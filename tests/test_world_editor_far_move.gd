extends "res://tests/test_world_units.gd"
func far_move() -> void:
	var focus := Vector3(354.5,0,-740)
	var region := await build("desert",focus,DATA.empty_document(),true)
	var chosen := {}
	for row in UNITS.manifest(region):
		if "saguaro" in str(row.label).to_lower(): chosen = row; break
	region.free()
	await process_frame
	check(not chosen.is_empty(),"far: source cactus exists")
	if chosen.is_empty(): return
	print("FAR_SOURCE ",JSON.stringify(chosen))
	var target := [float(chosen.position[0]),float(chosen.position[1])-400.0]
	var document := DATA.empty_document()
	document.regions.desert[chosen.id] = authored(chosen,{"position":target})
	region = await build("desert",Vector3(target[0],0,target[1]),document,false)
	var moved := group_of(region,chosen.id)
	if moved == null:
		print("FAR_STATE chunks=",region.chunks.keys()," pending=",region.pending," jobs=",region.build_jobs.size()," pull=",region._pull)
		for cell in region.records:
			for record in region.records[cell]:
				if PIECES.record_key(record) == chosen.source_record: print("FAR_RECORD cell=",cell," record=",record)
		for row in UNITS.manifest(region):
			if "saguaro" in str(row.label).to_lower(): print("FAR_RUNTIME ",JSON.stringify(row))
	check(moved != null and absf(moved.global_position.z-target[1])<.1,"far: remote cactus exists when only destination is loaded")
	region.free()
	await process_frame
func run() -> void:
	var official := DATA.disk_hash()
	await far_move()
	check(DATA.disk_hash() == official,"far: moving a remote object never saves official world")
	print("WORLD_EDITOR_FAR_MOVE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
