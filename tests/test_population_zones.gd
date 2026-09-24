extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := preload("res://systems/PopulationZoneManager.gd").new()
	check(catalog.zone_for_position(Vector2(0, 0)) == Vector2i(0, 0), "origin zone")
	check(catalog.zone_for_position(Vector2(1024, -1)) == Vector2i(1, -1), "boundary zone")
	var near_key := catalog.register_virtual({"key": "near", "position": Vector2(100, 100), "kind": "pedestrian"})
	var far_key := catalog.register_virtual({"key": "far", "position": Vector2(5000, 5000), "kind": "pedestrian"})
	check(near_key == "near" and far_key == "far", "stable keys")
	check(catalog.pending_materialization(Vector2.ZERO, 4).size() == 1, "only near records materialize")
	check(catalog.pending_materialization(Vector2.ZERO, 4, "", 150.0).is_empty(), "minimum spawn radius rejects near record")
	check(catalog.pending_materialization(Vector2.ZERO, 4, "", 50.0).size() == 1, "minimum spawn radius keeps valid ring record")
	var fake := Node2D.new()
	fake.global_position = Vector2(120, 100)
	check(catalog.register_actor(fake, "near") == "near", "actor registration")
	check(catalog.count_materialized("pedestrian") == 1, "materialized count")
	check(catalog.pending_materialization(Vector2.ZERO, 4).is_empty(), "materialized actor leaves the pending index")
	var state := catalog.capture_actor(fake, {"route_id": "test_route", "route_progress": 0.25})
	check(not bool(state.get("materialized", true)), "capture virtualizes actor")
	check(state.get("route_id", "") == "test_route", "capture preserves route state")
	check(catalog.pending_materialization(Vector2.ZERO, 4).size() == 1, "captured actor is demand candidate")
	fake.global_position = Vector2(3000, 0)
	catalog.update_actor(fake)
	check(catalog.pending_materialization(Vector2.ZERO, 4).is_empty(), "actor update removes a captured identity from the virtual index")
	var moved_state := catalog.capture_actor(fake, {"route_id": "test_route", "route_progress": 0.5})
	check(moved_state.get("key", "") == "near" and catalog.pending_materialization(Vector2(3000, 0), 4).size() == 1, "capture reindexes the same identity at its live position")
	fake.free()
	check_index_lifecycle()
	measure_query_scale()
	print("POPULATION_ZONES failures=%s snapshot=%s" % [failures, catalog.snapshot()])
	quit(1 if not failures.is_empty() else 0)

func measure_query_scale() -> void:
	for population_size in [500, 1000, 5000]:
		var catalog := preload("res://systems/PopulationZoneManager.gd").new()
		for index in population_size:
			var position := Vector2(100.0 + float(index) * 10.0, 100.0) if index < 8 else Vector2(50000.0 + float(index % 5) * 20000.0, float(index % 31) * 8.0)
			catalog.register_virtual({
				"key": "scale_%d_%d" % [population_size, index],
				"position": position,
				"owner": "scale_test",
				"kind": "pedestrian",
			})
		var started_usec := Time.get_ticks_usec()
		var result: Array[Dictionary] = []
		for query_index in 200:
			result = catalog.pending_materialization(Vector2.ZERO, 2, "scale_test", 0.0, "pedestrian")
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		var stats: Dictionary = catalog.last_query_stats()
		var snapshot_started_usec := Time.get_ticks_usec()
		var snapshot: Dictionary = catalog.snapshot()
		var snapshot_usec := Time.get_ticks_usec() - snapshot_started_usec
		check(result.size() == 2, "scale query returns the per-tick limit for %d records" % population_size)
		check(int(stats.get("examined_records", -1)) == 8, "local query examines only eight nearby records with %d total" % population_size)
		check(int(stats.get("visited_cells", -1)) == 16, "local query visits a fixed cell window with %d total" % population_size)
		check(int(stats.get("indexed_virtual", -1)) == population_size, "all %d virtual records remain indexed" % population_size)
		check(int(snapshot.get("virtual", -1)) == population_size and int(snapshot.get("indexed_virtual", -1)) == population_size, "snapshot remains coherent with %d records" % population_size)
		print("POPULATION_ZONE_SCALE records=%d queries=200 avg_query_usec=%.2f examined=%d cells=%d snapshot_usec=%d" % [population_size, float(elapsed_usec) / 200.0, int(stats.get("examined_records", -1)), int(stats.get("visited_cells", -1)), snapshot_usec])

func check_index_lifecycle() -> void:
	var catalog := preload("res://systems/PopulationZoneManager.gd").new()
	catalog.register_virtual({"key": "moving", "position": Vector2(9000, 9000), "owner": "harbor", "kind": "pedestrian", "route_progress": 0.4})
	check(catalog.pending_materialization(Vector2.ZERO, 2, "harbor", 0.0, "pedestrian").is_empty(), "distant virtual record is absent from the local cell window")
	catalog.register_virtual({"key": "moving", "position": Vector2(200, 0), "owner": "harbor", "kind": "pedestrian", "route_progress": 0.4})
	var moved: Array[Dictionary] = catalog.pending_materialization(Vector2.ZERO, 2, "harbor", 0.0, "pedestrian")
	check(moved.size() == 1 and moved[0].get("key", "") == "moving", "re-registering an identity moves it between indexed cells")
	check(is_equal_approx(float(moved[0].get("route_progress", -1.0)), 0.4), "indexed move preserves virtual state")
	catalog.materialize("moving")
	check(catalog.pending_materialization(Vector2.ZERO, 2, "harbor", 0.0, "pedestrian").is_empty(), "materialization removes an identity from the virtual index")
	catalog.register_virtual({"key": "pinned", "position": Vector2(50000, 50000), "owner": "harbor", "kind": "traffic", "pinned": true})
	var pinned: Array[Dictionary] = catalog.pending_materialization(Vector2.ZERO, 2, "harbor", 1000.0, "traffic")
	check(pinned.size() == 1 and pinned[0].get("key", "") == "pinned", "pinned identity remains globally eligible")
	var snapshot: Dictionary = catalog.snapshot()
	check(int(snapshot.get("total", -1)) == 2 and int(snapshot.get("materialized", -1)) == 1 and int(snapshot.get("virtual", -1)) == 1, "snapshot preserves materialized and virtual totals")
	check(int(snapshot.get("indexed_virtual", -1)) == 1, "snapshot reports index occupancy")
	check(int(snapshot.get("last_query", {}).get("pinned_examined", -1)) == 1, "snapshot exposes last query attribution")
	catalog.forget("pinned")
	check(int(catalog.snapshot().get("indexed_virtual", -1)) == 0, "forget removes the identity from the index")
	var boundaries := preload("res://systems/PopulationZoneManager.gd").new()
	boundaries.register_virtual({"key": "nearest", "position": Vector2(100, 0), "owner": "harbor", "kind": "pedestrian"})
	boundaries.register_virtual({"key": "edge", "position": Vector2(boundaries.ACTIVE_RADIUS, 0), "owner": "harbor", "kind": "pedestrian"})
	boundaries.register_virtual({"key": "outside", "position": Vector2(boundaries.ACTIVE_RADIUS + 0.1, 0), "owner": "harbor", "kind": "pedestrian"})
	boundaries.register_virtual({"key": "other_owner", "position": Vector2(50, 0), "owner": "mountain", "kind": "pedestrian"})
	boundaries.register_virtual({"key": "other_kind", "position": Vector2(25, 0), "owner": "harbor", "kind": "traffic"})
	var ordered: Array[Dictionary] = boundaries.pending_materialization(Vector2.ZERO, 2, "harbor", 0.0, "pedestrian")
	check(ordered.size() == 2 and ordered[0].get("key", "") == "nearest" and ordered[1].get("key", "") == "edge", "query preserves radius boundary, filters and nearest-first limit")

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
