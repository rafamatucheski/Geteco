extends SceneTree

const HARBOR_LIFE := preload("res://world/harbor/HarborLife.gd")
const LOOKUPS_PER_CASE := 50000

var failures: Array[String] = []
var timings: Dictionary = {}


class MissingKeyCatalog extends RefCounted:
	var records: Dictionary = {}

	func pending_materialization(_focus: Vector2, _limit: int, _owner: String = "", _minimum_radius: float = 0.0, kind: String = "") -> Array[Dictionary]:
		if kind == "traffic":
			return [{"key": "traffic:missing", "position": Vector2.ZERO}]
		return [{"key": "walker:missing", "position": Vector2.ZERO}]


func _initialize() -> void:
	for spec_count in [500, 1000, 5000]:
		measure_indexed_lookups(spec_count)
	check_stable_cost("traffic")
	check_stable_cost("walker")
	print("HARBOR_SPEC_INDEX failures=%s timings=%s" % [failures, timings])
	quit(1 if not failures.is_empty() else 0)


func measure_indexed_lookups(spec_count: int) -> void:
	var life := HARBOR_LIFE.new()
	for index in spec_count:
		var route := PackedVector2Array([
			Vector2(float(index), 10.0),
			Vector2(float(index) + 80.0, 10.0),
		])
		life._register_traffic_spec({
			"key": "traffic:%d" % index,
			"route_id": "traffic_route:%d" % index,
			"lane_id": "lane:%d" % index,
			"position": route[0],
			"ratio": 0.25,
			"serial": index,
		})
		life._register_walker_spec({
			"key": "walker:%d" % index,
			"route_id": "walker_route:%d" % index,
			"route_points": route,
			"position": route[0],
			"route_segment": index % 2,
			"route_direction": -1 if index % 2 else 1,
			"appearance_variant": index,
		})

	check(life._traffic_specs.size() == spec_count, "traffic registration keeps all %d ordered specs" % spec_count)
	check(life._walker_specs.size() == spec_count, "walker registration keeps all %d ordered specs" % spec_count)
	check(life._traffic_specs_by_key.size() == spec_count, "traffic index contains all %d identities" % spec_count)
	check(life._walker_specs_by_key.size() == spec_count, "walker index contains all %d identities" % spec_count)

	var last_index := spec_count - 1
	var traffic_key := "traffic:%d" % last_index
	var walker_key := "walker:%d" % last_index
	var traffic_spec: Dictionary = life._traffic_spec_for_key(traffic_key)
	var walker_spec: Dictionary = life._walker_spec_for_key(walker_key)
	check(int(traffic_spec.get("serial", -1)) == last_index, "traffic identity survives indexed lookup with %d specs" % spec_count)
	check(String(traffic_spec.get("route_id", "")) == "traffic_route:%d" % last_index, "traffic route survives indexed lookup with %d specs" % spec_count)
	check(String(walker_spec.get("route_id", "")) == "walker_route:%d" % last_index, "walker route survives indexed lookup with %d specs" % spec_count)
	check(walker_spec.get("route_points", PackedVector2Array()) == life._walker_specs[last_index].get("route_points"), "walker route geometry survives indexed lookup with %d specs" % spec_count)
	check(int(walker_spec.get("route_direction", 0)) == (-1 if last_index % 2 else 1), "walker route state survives indexed lookup with %d specs" % spec_count)

	# Reconciliation mutates a traffic spec with live catalog state. The index
	# must return the same Dictionary held by the ordered array, not a stale copy.
	traffic_spec["ratio"] = 0.73
	check(is_equal_approx(float(life._traffic_specs[last_index].get("ratio", 0.0)), 0.73), "traffic live state remains shared with its ordered spec")

	var children_before := life.get_child_count()
	var vehicles_before := life.vehicles.size()
	var walkers_before := life.walkers.size()
	check(life._traffic_spec_for_key("traffic:missing").is_empty(), "missing traffic identity returns empty with %d specs" % spec_count)
	check(life._walker_spec_for_key("walker:missing").is_empty(), "missing walker identity returns empty with %d specs" % spec_count)
	check(life.get_child_count() == children_before and life.vehicles.size() == vehicles_before and life.walkers.size() == walkers_before, "missing identities do not materialize actors with %d specs" % spec_count)
	var missing_catalog := MissingKeyCatalog.new()
	for key in life._traffic_specs_by_key:
		missing_catalog.records[key] = life._traffic_specs_by_key[key]
	for key in life._walker_specs_by_key:
		missing_catalog.records[key] = life._walker_specs_by_key[key]
	life._virtual_population_enabled = true
	var missing_result: Dictionary = life.reconcile_virtual_population(Vector2.ZERO, missing_catalog)
	check(int(missing_result.get("materialized", -1)) == 0, "reconciliation ignores absent identities with %d specs" % spec_count)
	check(life.get_child_count() == children_before and life.vehicles.size() == vehicles_before and life.walkers.size() == walkers_before, "absent reconciliation keys never spawn actors with %d specs" % spec_count)

	# Warm the interpreter and dictionary hash paths before the finite sample.
	for warmup in 1000:
		life._traffic_spec_for_key(traffic_key)
		life._walker_spec_for_key(walker_key)

	var started_usec := Time.get_ticks_usec()
	for lookup_index in LOOKUPS_PER_CASE:
		life._traffic_spec_for_key(traffic_key)
		life._traffic_spec_for_key("traffic:missing")
	var traffic_usec := Time.get_ticks_usec() - started_usec

	started_usec = Time.get_ticks_usec()
	for lookup_index in LOOKUPS_PER_CASE:
		life._walker_spec_for_key(walker_key)
		life._walker_spec_for_key("walker:missing")
	var walker_usec := Time.get_ticks_usec() - started_usec

	var traffic_avg := float(traffic_usec) / float(LOOKUPS_PER_CASE * 2)
	var walker_avg := float(walker_usec) / float(LOOKUPS_PER_CASE * 2)
	timings["traffic_%d" % spec_count] = traffic_avg
	timings["walker_%d" % spec_count] = walker_avg
	print("HARBOR_SPEC_INDEX_SCALE specs=%d lookups_per_kind=%d traffic_avg_usec=%.3f walker_avg_usec=%.3f" % [
		spec_count,
		LOOKUPS_PER_CASE * 2,
		traffic_avg,
		walker_avg,
	])
	life.free()


func check_stable_cost(kind: String) -> void:
	var smallest := float(timings.get("%s_500" % kind, INF))
	var largest := float(timings.get("%s_5000" % kind, INF))
	# Absolute slack absorbs timer noise below one microsecond; a linear scan
	# grows by roughly 10x over this population range and fails this contract.
	check(largest <= smallest * 3.0 + 0.25, "%s lookup cost stays stable from 500 to 5000 specs (%.3f -> %.3f usec)" % [kind, smallest, largest])


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
