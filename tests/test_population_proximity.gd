extends "res://tests/test_reserved_traffic_budget.gd"
const ACTIVITY := preload("res://systems/PopulationActivity.gd")
class Counter:
	extends Node
	var ticks := 0
	func _physics_process(_delta: float) -> void: ticks += 1

func run() -> void:
	root.size = Vector2i(1280, 720)
	var compact_visual := preload("res://characters/AnimatedPedestrian3D.gd").new()
	compact_visual.defer_presentation = true
	var compact_view := SubViewport.new()
	root.add_child(compact_visual)
	compact_view.size = Vector2i(96, 96)
	compact_visual.viewport = compact_view
	compact_visual.add_child(compact_view)
	compact_visual.compact_presentation_for_sleep()
	check(compact_view.size == Vector2i(48, 48), "Sleeping pedestrian presentation compacts to 48x48")
	compact_visual.restore_presentation_after_sleep()
	check(compact_view.size == Vector2i(48, 48), "Waking pedestrian defers its 3D target restore")
	compact_visual.call("_update_viewport_render_state", 0.0)
	check(compact_view.size == Vector2i(96, 96), "Visible pedestrian restores its 3D render target")
	compact_visual.queue_free()
	var world := Node2D.new()
	root.add_child(world)
	var burst_activity := ACTIVITY.new()
	var burst_walkers: Array[Node2D] = []
	for index in 80:
		var burst_actor := actor(world, Vector2(9000 + index * 12, 9000), true)
		burst_walkers.append(burst_actor)
	burst_activity.update(world, Vector2.ZERO, [], burst_walkers)
	check(int(burst_activity.stats.get("pending_transitions", 0)) > 0, "Distant population transitions are bounded per update")
	burst_activity.restore_all()
	for burst_actor in burst_walkers:
		burst_actor.queue_free()
	var activity := ACTIVITY.new()
	var citizen := actor(world, Vector2(5000, 5000), true)
	citizen.remove_from_group("authored_sidewalk_pedestrian")
	citizen.add_to_group("pedestrian")
	var child := Counter.new()
	citizen.add_child(child)
	var view := SubViewport.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	citizen.add_child(view)
	var car := actor(world, Vector2(5100, 5000))
	car.set_process(true)
	car.set_physics_process(false)
	citizen.set_physics_process(true)
	var identity := citizen.get_instance_id()
	activity.update(world, Vector2.ZERO, [car], [citizen])
	var ticks := child.ticks
	for i in 4: await physics_frame
	check(child.ticks == ticks and not citizen.can_process(), "Distant citizen and child simulation are suspended")
	check(view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Sleeping presentation stops render submissions")
	check(not car.can_process(), "Distant traffic stops")
	activity.update(world, Vector2(5000, 5000), [car], [citizen])
	for i in 4: await physics_frame
	check(child.ticks > ticks and citizen.can_process(), "Approaching wakes non-authored pedestrians and children")
	check(car.is_processing() and not car.is_physics_processing(), "Wake restores each callback's original state")
	check(citizen.get_instance_id() == identity and citizen.position == Vector2(5000,5000), "Identity and position survive return")
	check(view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Viewport update policy restored")
	# The interior fallback activation box ends at 850; retention adds 240.
	citizen.position = Vector2(5990,5000)
	activity.update(world, Vector2(5000,5000), [car], [citizen])
	check(citizen.can_process(), "Retention band prevents boundary oscillation")
	citizen.position.x = 6200
	activity.update(world, Vector2(5000,5000), [car], [citizen])
	check(not citizen.can_process(), "Leaving retention band suspends actor")
	citizen.position.x = 5990
	activity.update(world, Vector2(5000,5000), [car], [citizen])
	check(not citizen.can_process(), "Sleeping actor waits for inner activation boundary")
	# An external lifecycle transition can disable movement while asleep.
	citizen.set_physics_process(false)
	citizen.set_meta("simulation_keep_alive", true)
	activity.update(world, Vector2.ZERO, [car], [citizen])
	check(citizen.can_process(), "Explicit mission pin remains active at distance")
	check(not citizen.is_physics_processing(), "Wake preserves lifecycle changes made while asleep")
	citizen.remove_meta("simulation_keep_alive")
	car.is_driven_by_player = true
	activity.update(world, Vector2.ZERO, [car], [citizen])
	check(car.can_process(), "Player controlled vehicle remains active")
	var player := actor(world, Vector2(27400, 20000), true)
	player.add_to_group("player")
	player.add_to_group("pedestrian")
	var player_ticks := Counter.new()
	player.add_child(player_ticks)
	activity.update(world, Vector2.ZERO, [car], [citizen, player])
	for i in 4: await physics_frame
	check(player.can_process() and player_ticks.ticks > 0, "Interior player keeps processing while exterior population is budgeted")
	check(not player.has_meta("proximity_sleeping"), "Player is never marked as sleeping ambient population")
	check(not citizen.can_process(), "Pinning player preserves suspension of distant ambient citizens")
	citizen.free()
	activity.update(world, Vector2.ZERO, [car], [])
	activity.restore_all()
	world.queue_free()
	await process_frame
	print("POPULATION_PROXIMITY failures=", failures)
	quit(0 if failures.is_empty() else 1)
