extends SceneTree
## Caminhos nativos de corpo inteiro e ciclo de vida da recompensa. A profundidade renderizada é um portão à parte.
const MINE := preload("res://world/mining/coal/CoalMinePlace.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("COAL_MINE ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func supported(actor: CharacterBody3D, position_value: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(position_value + Vector3.UP * .3, position_value - Vector3.UP * .2, 1)
	query.exclude = [actor.get_rid()]
	return not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func walk_path(actor: CharacterBody3D, route: Array[Vector3]) -> bool:
	actor.position = route[0] + Vector3.UP * .04
	for index in range(1, route.size()):
		var destination := route[index] + Vector3.UP * .04
		var vector := destination - actor.position
		var steps := maxi(1, int(ceil(vector.length() / .4)))
		var movement := vector / steps
		for step in steps:
			var hit := KinematicCollision3D.new()
			if actor.test_move(actor.global_transform, movement, hit):
				print("COAL_PATH_BLOCKED at=", actor.position, " to=", destination, " collider=", hit.get_collider(), " contact=", hit.get_position())
				return false
			actor.position += movement
			if not supported(actor, actor.position): return false
	return true

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var mine := MINE.new()
	stage.add_child(mine)
	await physics_frame
	await physics_frame
	check(mine.reward_points.is_empty(), "closed secret publishes no collectible, including invisible pickups")
	check(mine.nearest_mine_action(mine.spawn_position).is_empty(), "lever cannot be activated from entrance")
	check(not mine.nearest_mine_action(mine.to_global(MINE.LEVER_POINT)).is_empty(), "lever has a reachable functional interaction")
	var route: Array[Vector3] = [Vector3(9, 0, 8.8), Vector3(9, 0, -4), Vector3(0, 0, -4),
		MINE.LEVER_POINT, Vector3(-4.7, 0, -4.05), Vector3(-5.15, 0, -7.9),
		Vector3(-4.7, 0, -4.05), Vector3(0, 0, -4), Vector3(9, 0, -4), Vector3(9, 0, 10.5)]
	for player in [true, false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		for frame in 3: await physics_frame
		var who := "player" if player else "npc"
		check(walk_path(actor, route), who + " sweeps entrance, full tunnel, lever, cash and return with floor support")
		# Passa da borda de rocha do conector em x=16 antes de virar para o norte com a
		# cápsula inteira; um corte diagonal em x=15.5 raspa esse canto legítimo da parede.
		var raid_route: Array[Vector3] = [Vector3(9, 0, 8.8), Vector3(9, 0, 3), Vector3(16.7, 0, 3),
			Vector3(16.7, 0, -.5), Vector3(22, 0, -.5), MINE.RAID_LOOT]
		check(walk_path(actor, raid_route), who + " crosses criminal gallery and flanks cover to cash table")
		raid_route.reverse()
		check(walk_path(actor, raid_route), who + " returns from criminal gallery with full body and floor support")
		for point in MINE.RAID_GUARDS:
			actor.position = point + Vector3.UP * .04
			check(not actor.test_move(actor.global_transform, Vector3.UP * .001) and supported(actor, actor.position), who + " guard station clear " + str(point))
		for point in [route[0], MINE.LEVER_POINT, Vector3(-5.15, 0, -7.9), route[-1]]:
			actor.position = point + Vector3.UP * .04
			check(not actor.test_move(actor.global_transform, Vector3.UP * .001) and supported(actor, actor.position), who + " authored station fits entire body at " + str(point))
		for probe in [
			["east wall and large sweep", Vector3(9, .04, 6), Vector3(20, 0, 0)],
			["west cutaway remains solid", Vector3(9, .04, 6), Vector3(-5, 0, 0)],
			["north tunnel end", Vector3(9, .04, -4), Vector3(0, 0, -5)],
			["wagon full footprint", Vector3(-7.5, .04, -4.9), Vector3(0, 0, -5)],
			["bench full footprint", Vector3(-11.6, .04, 1.65), Vector3(0, 0, -1.5)],
			["stacked supplies", Vector3(.65, .04, -7.8), Vector3(0, 0, -3)],
			["coal heap", Vector3(.85, .04, -2), Vector3(0, 0, 2)],
			["support post", Vector3(9, .04, 5.8), Vector3(2.5, 0, 0)],
			["lever housing", Vector3(-9.65, .04, -4.05), Vector3(-2, 0, 0)],
			["west criminal cover", Vector3(19, .04, 5), Vector3(0, 0, -3)],
			["center criminal cover", Vector3(24, .04, -.5), Vector3(0, 0, 3)],
			["south criminal cover", Vector3(27, .04, 5.8), Vector3(0, 0, 4)],
			["contraband pallet", Vector3(19.2, .04, -2.8), Vector3(0, 0, -3)],
			["cash table", Vector3(28, .04, -3), Vector3(0, 0, -2)]]:
			actor.position = probe[1]
			check(actor.test_move(actor.global_transform, probe[2]), who + " blocks " + probe[0])
		actor.free()
		await physics_frame
	check(mine.perform_mine_action(), "first lever activation reveals secret")
	check(not mine.raid_contains(mine.spawn_position) and not mine.raid_contains(mine.to_global(MINE.LEVER_POINT)), "criminal encounter stays outside entrance and western easter egg")
	check(mine.raid_contains(mine.raid_loot_position()), "loot belongs to criminal gallery")
	check(mine.nearest_raid_action(mine.raid_loot_position(), false).is_empty(), "runtime can withhold guarded bag")
	check(mine.nearest_raid_action(mine.raid_loot_position()).get("target", "") == "raid_loot", "cash bag has functional interaction from clear floor")
	mine.set_raid_loot_available(false)
	check(mine.nearest_raid_action(mine.raid_loot_position()).is_empty(), "carried or completed bag cannot be grabbed twice")
	check(not mine.perform_mine_action(), "repeat interaction has no duplicate effect")
	check(mine.reward_points.size() == 1 and mine.reward_points[0].id == MINE.CACHE_ID, "revealed secret publishes one persistent reward")
	mine.set_reward_available(false, MINE.CACHE_ID)
	mine.restore_secret(true)
	check(not mine.reward_points[0].visual.visible, "restoring revealed secret does not resurrect claimed cash")
	mine.set_active(false)
	check(mine.nearest_mine_action(mine.to_global(MINE.LEVER_POINT)).is_empty() and not mine.perform_mine_action(), "inactive gallery cannot interact")
	check(not mine.visible and mine.process_mode == Node.PROCESS_MODE_DISABLED, "inactive mine stops presentation and processing")
	mine.free()
	var restored := MINE.new()
	stage.add_child(restored)
	restored.set_reward_available(false, MINE.CACHE_ID)
	restored.restore_secret(true)
	check(restored.secret_revealed and not restored.reward_points[0].visual.visible, "new room instance restores secret and claimed reward independently")
	stage.free()
	print("COAL_MINE checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
