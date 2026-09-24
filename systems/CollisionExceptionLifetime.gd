extends Node
## Collision exceptions outlive the other body's RID in Godot Physics 2D.
## Remove the reciprocal reference before a participating node is destroyed.
## PREDELETE, rather than tree_exiting, preserves exceptions across lane reparenting.
const META := &"collision_exception_lifetime"
var _body_rid := RID()
var _peers: Dictionary = {}

static func add(body: PhysicsBody2D, other: PhysicsBody2D) -> void:
	body.add_collision_exception_with(other)
	var owner_guard := _guard(body)
	var other_guard := _guard(other)
	owner_guard._peers[other.get_rid()] = weakref(other)
	other_guard._peers[body.get_rid()] = weakref(body)

static func _guard(body: PhysicsBody2D) -> Node:
	if body.has_meta(META):
		return body.get_meta(META)
	var guard := new()
	guard.name = "CollisionExceptionLifetime"
	guard._body_rid = body.get_rid()
	body.add_child(guard)
	body.set_meta(META, guard)
	return guard

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for peer_rid: RID in _peers:
		var peer = _peers[peer_rid].get_ref()
		if not is_instance_valid(peer):
			continue
		PhysicsServer2D.body_remove_collision_exception(peer_rid, _body_rid)
		var guard = peer.get_meta(META, null)
		if is_instance_valid(guard):
			guard._peers.erase(_body_rid)
