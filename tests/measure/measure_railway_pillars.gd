extends "res://tests/measure/measure_railway.gd"

func sample(id: String) -> void:
	if not await prepare_station("desert_copper"):
		push_error("Pillar review could not reach desert station")
		quit(1)
		return
	var center := Vector3(-72, 3, -875.125)
	world.camera.set_process(false)
	world.camera.global_position = center + Vector3(30, 32, 40)
	world.camera.look_at(center)
	world.camera.size = 65
	await create_timer(8).timeout
	await capture("street-pillar")
	await super.sample(id)

func capture(id: String) -> void:
	var railway = world.session.railway_world
	var regions: Dictionary = world.production._region_cache.duplicate()
	regions.merge(world.production.regions, true)
	var all_roads: Array[Dictionary] = []
	for region in regions.values():
		all_roads.append_array(region.roads)
		if region.get("walkways") is Array: all_roads.append_array(region.walkways)
	var omitted: Array[Dictionary] = []
	var original: Array[Dictionary] = railway._source_roads.duplicate()
	for descriptors in railway._descriptors.values():
		for segment in descriptors:
			if not segment.pillar: continue
			var point: Vector3 = (segment.a + segment.b) * .5
			var allowed: bool = railway._pillar_clear(point)
			railway._source_roads = all_roads
			var expected: bool = railway._pillar_clear(point)
			railway._source_roads = original
			if allowed and not expected: omitted.append({"point":str(point), "line":segment.id})
	report.pillar_audit = {"cached_roads":original.size(), "actual_roads":all_roads.size(), "missed":omitted}
	print("PILLAR_AUDIT ", JSON.stringify(report.pillar_audit))
	await super.capture(id)
