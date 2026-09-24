extends SceneTree

class ReadyGroupedActor:
	extends Node2D
	var primary_group: StringName
	var secondary_group: StringName

	func _ready() -> void:
		add_to_group(primary_group)
		if not secondary_group.is_empty():
			add_to_group(secondary_group)


class PopulationRegion:
	extends Node
	var reconcile_calls := 0

	func _ready() -> void:
		add_to_group(&"population_region")

	func reconcile_virtual_population(_focus: Vector2, _catalog: RefCounted) -> void:
		reconcile_calls += 1


class CatalogProbe:
	extends "res://world/harbor/ContinuousWorld.gd"
	var observed_group_queries := 0
	var activity_updates := 0

	func _population_group_nodes(group_name: StringName) -> Array[Node]:
		observed_group_queries += 1
		return super._population_group_nodes(group_name)

	func _update_population_activity(_point: Vector2) -> void:
		activity_updates += 1


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if value: return
	failures.append(message)
	push_error(message)


func run() -> void:
	for population_size in [500, 1000, 5000]:
		await _check_scale(population_size)
	print("CONTINUOUS_WORLD_POPULATION_CATALOG failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)


func _check_scale(population_size: int) -> void:
	var fixture := Node2D.new()
	fixture.name = "CatalogScale%d" % population_size
	root.add_child(fixture)
	var harbor := Node2D.new()
	harbor.name = "Harbor"
	fixture.add_child(harbor)
	var mountain := Node2D.new()
	mountain.name = "Mountain"
	fixture.add_child(mountain)
	var stream := CatalogProbe.new()
	stream.name = "ContinuousWorld"
	stream.set_process(false)
	fixture.add_child(stream)
	var region := PopulationRegion.new()
	fixture.add_child(region)
	await process_frame
	await process_frame
	var bootstrap_queries := stream.observed_group_queries
	check(bootstrap_queries == 4, "%d: bootstrap performs one four-group reconciliation" % population_size)

	var actors: Array[Node] = []
	var expected_cars := 0
	var expected_walkers := 0
	for index in population_size:
		var actor := ReadyGroupedActor.new()
		actor.name = "ScaleActor_%d" % index
		actor.position = Vector2(float(index % 100) * 40.0, float(index / 100) * 40.0)
		if index % 2 == 0:
			actor.primary_group = &"modern_traffic"
			expected_cars += 1
		else:
			actor.primary_group = &"pedestrian"
			if index % 5 == 0:
				actor.secondary_group = &"authored_sidewalk_pedestrian"
			expected_walkers += 1
		harbor.add_child(actor)
		actors.append(actor)
	await process_frame
	await process_frame

	var stats: Dictionary = stream.get_population_catalog_stats()
	check(int(stats.get("cars", -1)) == expected_cars, "%d: every ready-grouped car is incrementally cataloged" % population_size)
	check(int(stats.get("walkers", -1)) == expected_walkers, "%d: pedestrian groups are deduplicated" % population_size)
	check(int(stats.get("regions", -1)) == 1, "%d: population region is incrementally cataloged" % population_size)
	check(stream.population_zones.count_materialized() == population_size, "%d: zone manager owns every live identity once" % population_size)

	var normal_query_baseline := stream.observed_group_queries
	var normal_started_usec := Time.get_ticks_usec()
	for tick in 200:
		stream._budget_traffic(Vector2(float(tick), 0.0))
	var normal_usec := Time.get_ticks_usec() - normal_started_usec
	check(stream.observed_group_queries == normal_query_baseline, "%d: 40 seconds of normal budget ticks perform no global group query" % population_size)
	check(region.reconcile_calls == 200, "%d: incremental region catalog still drives reconciliation" % population_size)
	check(stream.activity_updates == 200, "%d: PopulationActivity receives every budget update" % population_size)

	var moved := actors[0] as Node2D
	var moved_key := String(moved.get_meta("population_key", ""))
	var car_count_before_move := stream._population_cars.size()
	moved.reparent(mountain, true)
	await process_frame
	await process_frame
	check(stream._population_cars.size() == car_count_before_move, "%d: reparent across regions preserves the live car" % population_size)
	check(String(moved.get_meta("population_key", "")) == moved_key and stream.population_zones.records.has(moved_key), "%d: region handoff preserves population identity" % population_size)

	if population_size == 500:
		await _check_churn_and_fallback(stream, harbor, actors, expected_cars, expected_walkers)

	stats = stream.get_population_catalog_stats()
	var invalid_refs := 0
	for actor_value in stream._population_cars + stream._population_walkers:
		if not is_instance_valid(actor_value): invalid_refs += 1
	check(invalid_refs == 0, "%d: live catalogs contain no invalid references" % population_size)
	print("POPULATION_CATALOG_SCALE actors=%d ticks=200 avg_tick_usec=%.2f group_queries=%d cars=%d walkers=%d" % [population_size, float(normal_usec) / 200.0, stream.observed_group_queries, int(stats.get("cars", -1)), int(stats.get("walkers", -1))])
	fixture.queue_free()
	await process_frame
	await process_frame


func _check_churn_and_fallback(stream: CatalogProbe, harbor: Node2D, actors: Array[Node], expected_cars: int, expected_walkers: int) -> void:
	var removed_cars := 0
	var removed_walkers := 0
	for index in 20:
		var actor := actors[10 + index]
		if actor.is_in_group("modern_traffic"): removed_cars += 1
		else: removed_walkers += 1
		actor.queue_free()
	await process_frame
	await process_frame
	check(stream._population_cars.size() == expected_cars - removed_cars, "churn removes despawned cars immediately")
	check(stream._population_walkers.size() == expected_walkers - removed_walkers, "churn removes despawned walkers immediately")

	for index in 20:
		var replacement := ReadyGroupedActor.new()
		replacement.name = "Replacement_%d" % index
		replacement.primary_group = &"modern_traffic" if index % 2 == 0 else &"pedestrian"
		harbor.add_child(replacement)
	await process_frame
	await process_frame
	check(stream._population_cars.size() == expected_cars - removed_cars + 10, "churn incrementally adds replacement cars")
	check(stream._population_walkers.size() == expected_walkers - removed_walkers + 10, "churn incrementally adds replacement walkers")

	var captured := actors[40] as Node2D
	var captured_key := String(captured.get_meta("population_key", ""))
	stream.population_zones.capture_actor(captured, {"route_id": "churn_route"})
	captured.queue_free()
	await process_frame
	await process_frame
	check(stream.population_zones.records.has(captured_key) and not bool(stream.population_zones.records[captured_key].get("materialized", true)), "virtualized despawn retains its route identity")

	var late_grouped := Node2D.new()
	late_grouped.name = "LateGroupedCar"
	harbor.add_child(late_grouped)
	await process_frame
	var cars_before_fallback := stream._population_cars.size()
	late_grouped.add_to_group("modern_traffic")
	await process_frame
	check(stream._population_cars.size() == cars_before_fallback, "late post-ready group mutation waits for rare fallback")
	var queries_before_fallback := stream.observed_group_queries
	stream._refresh_population_catalog()
	check(stream.observed_group_queries == queries_before_fallback + 4, "explicit fallback performs exactly four global queries")
	check(stream._population_cars.has(late_grouped), "fallback recovers a post-ready group mutation")
	var live_count_after_recovery := stream._population_cars.size() + stream._population_walkers.size()
	stream._refresh_population_catalog()
	check(stream._population_cars.size() + stream._population_walkers.size() == live_count_after_recovery, "reconciliation is idempotent and loses no actor")
	late_grouped.remove_from_group("modern_traffic")
	stream._refresh_population_catalog()
	check(not stream._population_cars.has(late_grouped), "fallback removes an actor that left its population group")
