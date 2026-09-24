extends SceneTree
## Regression: an on-screen ordinary car must wake only the short logical
## leader chain it needs, even though sleeping leaders left the physics space.

const RULES := preload("res://cars/traffic/TrafficSimulationBudget.gd")
const ACTIVITY := preload("res://systems/PopulationActivity.gd")
const DISTANT_ACTORS := 500

class TrafficActor:
	extends CharacterBody2D
	var is_driven_by_player := false
	var is_exploding := false
	var is_flying := false

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: return
	failures.append(message)
	push_error(message)

func make_lane(parent: Node, name_value: String, y: float) -> Path2D:
	var path := Path2D.new()
	path.name = name_value
	path.position.y = y
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2.ZERO)
	path.curve.add_point(Vector2(200000.0, 0.0))
	parent.add_child(path)
	return path

func make_vehicle(path: Path2D, progress: float, sleeping: bool, activity) -> TrafficActor:
	var follow := PathFollow2D.new()
	follow.loop = false
	path.add_child(follow)
	follow.progress = progress
	var vehicle := TrafficActor.new()
	vehicle.add_to_group("vehicle")
	vehicle.add_to_group("modern_traffic")
	vehicle.collision_layer = 2
	vehicle.collision_mask = 2
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(24.0, 12.0)
	vehicle.add_child(collision)
	follow.add_child(vehicle)
	if sleeping: activity.set_active(vehicle, false)
	return vehicle

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var activity := ACTIVITY.new()
	var lane := make_lane(world, "ActiveLane", 0.0)
	var root_car := make_vehicle(lane, 100.0, false, activity)
	var chain: Array[TrafficActor] = []
	for index in RULES.MAX_ORDINARY_LEADER_CHAIN + 3:
		chain.append(make_vehicle(lane, 140.0 + index * 40.0, true, activity))
	var parallel_lane := make_lane(world, "ParallelLane", 8.0)
	var parallel_car := make_vehicle(parallel_lane, 140.0, true, activity)
	await physics_frame
	await physics_frame
	check(chain[0].get_meta("proximity_sleeping", false), "Fixture removes the immediate leader from active physics")
	check(chain[0].disable_mode == CollisionObject2D.DISABLE_MODE_REMOVE, "Fixture uses the real population sleep broadphase policy")

	var area := Rect2(root_car.global_position - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
	var before_stats := {}
	var before_started := Time.get_ticks_usec()
	var before := RULES.active_conflict_actors(self, area, before_stats)
	var before_usec := Time.get_ticks_usec() - before_started
	check(before.has(root_car.get_instance_id()), "Active ordinary traffic is a local dependency root")
	check(before.has(chain[0].get_instance_id()), "Immediate dormant lane leader enters the simulation budget")
	for index in RULES.MAX_ORDINARY_LEADER_CHAIN:
		check(before.has(chain[index].get_instance_id()), "Required dormant leader %d is retained" % index)
	check(not before.has(chain[RULES.MAX_ORDINARY_LEADER_CHAIN].get_instance_id()), "Leader chain stops at its explicit local cap")
	check(not before.has(parallel_car.get_instance_id()), "Spatially close traffic on another lane stays asleep")
	check(before_stats.ordinary_leaders_woken == RULES.MAX_ORDINARY_LEADER_CHAIN, "Diagnostics report exactly the bounded wake chain")
	check(before_stats.ordinary_chains_truncated == 1, "Diagnostics expose a longer queue truncated by policy")

	var distant_lane := make_lane(world, "DistantLane", 10000.0)
	for index in DISTANT_ACTORS:
		make_vehicle(distant_lane, 10000.0 + index * 300.0, true, activity)
	var after_stats := {}
	var after_started := Time.get_ticks_usec()
	var after := RULES.active_conflict_actors(self, area, after_stats)
	var after_usec := Time.get_ticks_usec() - after_started
	check(after.size() == before.size(), "Distant city traffic does not expand the local wake set")
	check(after_stats.ordinary_roots == before_stats.ordinary_roots, "Distant sleepers never become ordinary active roots")
	check(after_stats.ordinary_lane_queries == before_stats.ordinary_lane_queries, "Lane query work is bounded by local roots and chain cap")
	check(after_stats.lane_entries == before_stats.lane_entries, "Distant lanes without an active root are not sorted or indexed as leader chains")
	check(after_stats.indexed_actors == before_stats.indexed_actors + DISTANT_ACTORS, "Every distant actor still enters the shared spatial snapshot exactly once")
	print("LOCAL_DORMANT_LEADER_BUDGET before_usec=", before_usec,
		" after_500_usec=", after_usec, " wake_size=", before.size(),
		" chain_cap=", RULES.MAX_ORDINARY_LEADER_CHAIN,
		" before_stats=", before_stats, " after_stats=", after_stats,
		" failures=", failures)
	activity.restore_all()
	world.queue_free()
	for frame in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
