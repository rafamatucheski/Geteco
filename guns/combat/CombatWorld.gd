extends RefCounted

static func scene_for(actor: Node) -> Node:
	var ancestor := actor
	while ancestor != null:
		if ancestor.has_meta("combat_scene_root"):
			var room: Variant = ancestor.get_meta("combat_scene_root")
			if is_instance_valid(room): return room
		ancestor = ancestor.get_parent()
	return actor.get_tree().current_scene

static func effects_for(actor: Node2D) -> Node2D:
	for effect in actor.get_tree().get_nodes_in_group("weapon_effects"):
		if effect is Node2D and effect.get_world_2d() == actor.get_world_2d(): return effect
	return null

static func shares_world(a: Node2D, b: Node) -> bool:
	return is_instance_valid(b) and b is Node2D and a.get_world_2d() == b.get_world_2d()
