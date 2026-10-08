extends SceneTree
const GAME_STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const STATE := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
const REWARDS := preload("res://activities/amusement_park/AmusementParkRewards.gd")
const COSMETICS := preload("res://activities/amusement_park/AmusementParkCosmetics.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures := 0

class TestWorld extends Node3D:
	var player
	var gameplay := {"health":100}
	var driving := {"occupied":false}

class TestSession extends Node:
	var state = GAME_STATE.new()
	var world
	var modal := false
	var transition := false
	var messages: Array[String] = []
	var store = STORE.new()
	var saves := 0
	func is_transition_blocked() -> bool: return transition
	func show_message(value: String) -> void: messages.append(value)
	func save_game(_manual := false) -> bool:
		saves += 1
		return store.save(state) == OK
	func apply_outfit() -> void:
		world.player.set_outfit(state.economy.outfit)
		COSMETICS.apply(world.player, state.world_state)
	func _menu(_title: String) -> void:
		modal = true
		world.player.input_locked = true
	func _button(_text: String, _action: Callable) -> void: pass
	func close_menu() -> void:
		modal = false
		world.player.input_locked = false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PARK_REWARDS ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var session := TestSession.new()
	session.store.path = "user://tests/park_rewards_%d/progress.json" % Time.get_ticks_usec()
	root.add_child(session)
	var world := TestWorld.new()
	root.add_child(world)
	session.world = world
	world.player = ACTOR.new()
	world.player.is_player = true
	world.add_child(world.player)
	world.player.set_physics_process(false)
	var park := Node3D.new()
	park.position = Vector3(50, 0, 40)
	world.add_child(park)
	var rewards := REWARDS.new()
	session.add_child(rewards)
	rewards.configure(session)
	rewards.set_location(park, null)
	check(rewards.pickups.size() == 4, "four outdoor secrets are available before collection")
	check(GAME_STATE.new().restore_snapshot(session.state.snapshot()), "old saves without cosmetic extension remain loadable")
	check(not STATE.equip(session.state.world_state, session.state.economy, "ghost_mask"), "unfound accessories cannot be equipped")
	var wallet_before: Dictionary = session.state.economy.snapshot()
	check(not STATE.collect(session.state.world_state, session.state.economy, "unknown"), "unknown secret cannot modify ownership")
	var target: Vector3 = park.to_global(REWARDS.POINTS.lume_jacket)
	world.player.position = target + Vector3(0, -.12, .7)
	await physics_frame
	world.gameplay.health = 0
	check(rewards.collect_nearby() == 0, "dead player cannot collect")
	world.gameplay.health = 100
	world.driving.occupied = true
	check(rewards.collect_nearby() == 0, "vehicle occupants cannot collect")
	world.driving.occupied = false
	world.player.input_locked = true
	check(rewards.collect_nearby() == 0, "ride and modal input lock blocks collection")
	world.player.input_locked = false
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = target + Vector3(0, .55, .35)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 1.5, .1)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	await physics_frame
	check(rewards.collect_nearby() == 0, "solid wall blocks secret pickup from adjacent corridor")
	wall.free()
	await physics_frame
	check(rewards.collect_nearby() == 1, "walking close to an unobstructed secret grants the garment")
	check(session.saves == 1 and session.state.economy.owns_outfit("dante_lume"), "pickup saves real outfit ownership")
	check(rewards.collect_nearby() == 0, "same pickup cannot be granted twice")
	check(session.state.economy.snapshot().balance == wallet_before.balance and session.state.economy.snapshot().inventory == wallet_before.inventory and session.state.economy.snapshot().weapons == wallet_before.weapons, "cosmetic finds preserve cash inventory and weapons")
	for id in ["midnight_coat", "star_glasses", "amber_glasses", "ghost_mask", "fox_mask"]:
		check(STATE.collect(session.state.world_state, session.state.economy, id), "secret grants once: " + id)
		check(not STATE.collect(session.state.world_state, session.state.economy, id), "duplicate rejected: " + id)
	check(STATE.equip(session.state.world_state, session.state.economy, "lume_jacket"), "found garment can be worn")
	check(STATE.equip(session.state.world_state, session.state.economy, "star_glasses"), "glasses equip independently")
	check(STATE.equip(session.state.world_state, session.state.economy, "fox_mask"), "mask equips alongside glasses")
	session.apply_outfit()
	check(world.player.outfit_id == "dante_lume" and accessory_count(world.player.skeleton) == 2, "real Dante model wears outfit glasses and mask together")
	var first_mount: Node = world.player.skeleton.get_node("ParkCosmetics")
	var live_mount: WeakRef = weakref(first_mount)
	session.apply_outfit()
	check(live_mount.get_ref() == null and accessory_count(world.player.skeleton) == 2, "reapplying outfit replaces accessories without duplicate mounts")
	check(session.state.economy.grant_outfit("dante_hawaii") and session.state.economy.equip_outfit("dante_hawaii"), "ordinary wardrobe outfit remains usable")
	session.apply_outfit()
	check(accessory_count(world.player.skeleton) == 2 and not baked_glasses_visible(world.player.skeleton), "selected glasses suppress baked eyewear and retain both cosmetic slots")
	check(session.save_game(), "writes valid complete state through real SaveStore")
	var loaded = GAME_STATE.new()
	check(session.store.load_into(loaded).get("ok", false), "loads actual isolated save from disk")
	var restored_cosmetics: Dictionary = loaded.world_state[STATE.KEY]
	check(restored_cosmetics.found == session.state.world_state[STATE.KEY].found and restored_cosmetics.glasses == "star_glasses" and restored_cosmetics.mask == "fox_mask" and restored_cosmetics.version == 1 and loaded.economy.outfit == "dante_hawaii", "save restores found secrets selected glasses mask and current outfit")
	session.state = loaded
	park.free()
	park = Node3D.new()
	world.add_child(park)
	rewards.set_location(park, null)
	check(rewards.pickups.is_empty(), "reentering park after load does not respawn collected secrets")
	var haunted := Node3D.new()
	world.add_child(haunted)
	rewards.set_location(park, haunted)
	check(rewards.pickups.is_empty(), "collected haunted-house secrets remain absent on first post-load visit")
	session.apply_outfit()
	check(accessory_count(world.player.skeleton) == 2, "reloaded cosmetics are attached to live Dante")
	check(STATE.remove(session.state.world_state, "glasses"), "glasses can be removed independently")
	COSMETICS.apply(world.player, session.state.world_state)
	check(accessory_count(world.player.skeleton) == 1 and baked_glasses_visible(world.player.skeleton), "removing glasses retains mask and restores ordinary outfit eyewear")
	check(STATE.remove(session.state.world_state, "mask"), "mask can be removed independently")
	COSMETICS.apply(world.player, session.state.world_state)
	check(not world.player.skeleton.has_node("ParkCosmetics"), "no accessories leaves no empty attachment")
	var corrupt: Dictionary = session.state.snapshot()
	corrupt.world[STATE.KEY].found.append("ghost_mask")
	check(not GAME_STATE.new().restore_snapshot(corrupt), "corrupt duplicate secret markers reject the snapshot")
	corrupt = session.state.snapshot()
	corrupt.world[STATE.KEY].glasses = "fox_mask"
	check(not GAME_STATE.new().restore_snapshot(corrupt), "wrong accessory slot rejects snapshot")
	corrupt = session.state.snapshot()
	corrupt.economy.outfits.erase("dante_lume")
	check(not GAME_STATE.new().restore_snapshot(corrupt), "claimed garment without wallet ownership rejects snapshot")
	corrupt = session.state.snapshot()
	corrupt.world[STATE.KEY].found.erase("ghost_mask")
	corrupt.world[STATE.KEY].mask = "ghost_mask"
	check(not GAME_STATE.new().restore_snapshot(corrupt), "unfound equipped accessory rejects snapshot")
	print("PARK_REWARDS SAVE ", ProjectSettings.globalize_path(session.store.path))
	world.free()
	session.free()
	print("%s amusement park rewards: %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func accessory_count(skeleton: Skeleton3D) -> int:
	var mount := skeleton.get_node_or_null("ParkCosmetics")
	return 0 if mount == null else mount.get_child(0).get_child_count()

func baked_glasses_visible(skeleton: Skeleton3D) -> bool:
	var mount := skeleton.get_node_or_null("MeshyOutfitHead")
	if mount == null: return false
	for space in mount.get_children():
		for child in space.get_children():
			if child.get_meta("outfit_accessory_kind", "") in ["shades", "goggles"] and child.visible: return true
	return false
