extends "res://world/places/NativePlace.gd"
## The mine uses the ordinary place admission, return, rewards and save contract.
const ART := preload("res://world/mining/coal/CoalMineModel.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const PLACE_ID := "remote_coal_mine"
const CACHE_ID := "remote_coal_cache_01"
const LEVER_POINT := Vector3(-9.65, 0, -4.05)
const RAID_GUARDS := [Vector3(18, 0, 6.3), Vector3(20, 0, -2.5), Vector3(27, 0, 6), Vector3(27, 0, -.6)]
const RAID_LOOT := Vector3(28, 0, -3)
const RAID_ZONE := Rect2(15.4, -5.5, 15.6, 15.5)
var secret_revealed := false
var _reward_claimed := false
var _authored_rewards: Array[Dictionary] = []
var _session: Node

static func definition_data() -> Dictionary:
	var cash := {"id": CACHE_ID, "kind": "cash", "amount": 1800,
		"local_position": Vector3(-5.15, 0, -7.9)}
	return {"id": PLACE_ID, "original_name": "Galeria Santa Brasa", "region": "desert",
		"source_id": PLACE_ID, "model": "res://world/mining/coal/CoalMineModel.gd",
		"exterior_position": LAYOUT.SECRET_EXTERIOR,
		"entry_position": LAYOUT.SECRET_ENTRY,
		"return_position": LAYOUT.SECRET_RETURN,
		"spawn": Vector3(9, 0, 8.8), "exit": Vector3(9, 0, 10.5),
		"size": Vector2(48, 26), "camera_target": Vector3(8.5, .7, -.4),
		"camera_size": 30.0, "variant": 0, "service": "secret",
		"reward": cash, "rewards": [cash], "npcs": [], "npc_model": "",
		"npc_point": Vector3.ZERO, "integration_status": "native"}

func _ready() -> void:
	if definition.is_empty(): definition = definition_data()
	name = PLACE_ID
	model = ART.new()
	add_child(model)
	for body: StaticBody3D in model.solid_bodies:
		solid_bodies.append(body)
	for bounds: AABB in model.solid_bounds:
		solid_bounds.append(bounds)
	interaction_points["service"] = to_global(LEVER_POINT)
	interaction_points["coal_lever"] = to_global(LEVER_POINT)
	_install_reward()
	_authored_rewards.assign(reward_points)
	restore_secret(secret_revealed)

func on_session_entered(session: Node) -> void:
	_session = session
	_reward_claimed = session.state.world_state.rewards.has(CACHE_ID)
	restore_secret(bool(session.state.world_state.get("remote_coal_secret_revealed", false)))
	if session.mining != null and session.mining.get("raid") != null:
		session.mining.raid.enter_room(self)

func raid_guard_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point in RAID_GUARDS: points.append(to_global(point))
	return points

func raid_loot_position() -> Vector3:
	return to_global(RAID_LOOT)

func raid_contains(world_point: Vector3) -> bool:
	var point := to_local(world_point)
	return absf(point.y) < 4 and RAID_ZONE.has_point(Vector2(point.x, point.z))

func nearest_raid_action(world_point: Vector3, can_collect := true) -> Dictionary:
	if not active or not can_collect or not model.raid_loot_available: return {}
	if world_point.distance_to(raid_loot_position()) > 1.45: return {}
	return {"id": "mining", "target": "raid_loot", "label": "Pegar bolsa"}

func set_raid_loot_available(value: bool) -> void:
	if is_instance_valid(model): model.set_raid_loot_available(value)

func nearest_mine_action(world_point: Vector3) -> Dictionary:
	if not active or secret_revealed: return {}
	if to_local(world_point).distance_to(LEVER_POINT) > 1.65: return {}
	return {"id": "mining", "target": "coal_lever", "label": "Acionar alavanca"}

func perform_mine_action() -> bool:
	if not active or secret_revealed: return false
	if is_instance_valid(_session):
		if _session.world.gameplay.health <= 0 or _session.world.driving.occupied: return false
		if _session.state.place_id != PLACE_ID: return false
		if nearest_mine_action(_session.world.player.global_position).is_empty(): return false
	secret_revealed = true
	model.reveal_secret(true)
	reward_points.assign(_authored_rewards)
	super.set_reward_available(not _reward_claimed, CACHE_ID)
	if is_instance_valid(_session):
		_session.state.world_state["remote_coal_secret_revealed"] = true
		_session.save_game()
	return true

func restore_secret(revealed: bool) -> void:
	secret_revealed = revealed
	if not is_instance_valid(model): return
	model.reveal_secret(false, revealed)
	# FullSession collects published points even when their visual is hidden.
	# Keep the reward entirely out of that collection list until the lever opens it.
	reward_points.assign(_authored_rewards if revealed else [])
	for point in _authored_rewards:
		point.visual.set_available(revealed and not _reward_claimed, false)
	super.set_reward_available(revealed and not _reward_claimed, CACHE_ID)

func set_reward_available(available: bool, id: String = "", animate := false) -> void:
	if id.is_empty() or id == CACHE_ID: _reward_claimed = not available
	super.set_reward_available(available and secret_revealed, id, animate)

func set_active(value: bool) -> void:
	super.set_active(value)
	if is_instance_valid(model): model.set_active(value)
