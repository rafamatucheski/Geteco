extends Node
## Session boundary for the mine: ordinary vehicles and the standard place transition.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const OPERATION := preload("res://gameplay/mining/MiningOperation.gd")
var session
var operation: Node
var raid: Node3D

func configure(owner_session) -> void:
	session=owner_session
	name="MiningRuntime"
	if not LAYOUT.enabled(): return
	operation=OPERATION.new()
	add_child(operation)
	operation.configure(session)
	raid=preload("res://gameplay/mining/MiningRaid.gd").new()
	add_child(raid)
	raid.configure(session)

func nearest_action() -> Dictionary:
	if not LAYOUT.enabled() or session.state.region_id!="desert" or session.world.driving.occupied or session.is_transition_blocked(): return {}
	if session.state.place_id=="remote_coal_mine" and is_instance_valid(session.room):
		if is_instance_valid(raid):
			var action: Dictionary=raid.nearest_action()
			if not action.is_empty(): return action
		return session.room.nearest_mine_action(session.world.player.global_position)
	return {}

func perform(action: Dictionary) -> bool:
	if session.modal or session.world.gameplay.health<=0 or nearest_action().get("target","")!=action.get("target",""): return false
	if action.get("target","")=="coal_lever": return session.room.perform_mine_action()
	if action.get("target","")=="raid_loot" and is_instance_valid(raid): return raid.perform(action)
	return false

func save_block_reason() -> String:
	if is_instance_valid(raid):
		var reason: String=raid.save_block_reason()
		if not reason.is_empty(): return reason
	if is_instance_valid(operation) and operation.has_method("save_block_reason"): return operation.save_block_reason()
	return ""

func write_snapshot() -> void:
	if is_instance_valid(operation) and operation.has_method("write_snapshot"): operation.write_snapshot(session.state.world_state)

func fall_limit(point: Vector3) -> float:
	if LAYOUT.enabled() and session.state.region_id=="desert" and session.state.place_id.is_empty() and LAYOUT.BOUNDS.has_point(Vector2(point.x,point.z)):
		return preload("res://world/mining/MiningExterior.gd").surface_height(Vector2(point.x,point.z))-12.0
	return -12.0

func cancel_attempt() -> void:
	if is_instance_valid(operation): operation.cancel()
	if is_instance_valid(raid): raid.cancel()
