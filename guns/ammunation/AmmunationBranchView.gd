extends "res://world/mountain_pass/MountainStaticModelView.gd"
## A streamed branch can be built while the loading screen suspends rendering.
## Refresh its static texture when it actually enters the gameplay camera.
var _was_on_screen := false
var animated_entrance: BuildingEntrance
var inline_room: Node2D
var door_blocker: CollisionPolygon2D
var _door_amount := 0.0

func bind_entrance(door: BuildingEntrance, room: Node2D) -> void:
	animated_entrance = door
	if room.get("inline_mode") == true:
		inline_room = room
		room.call("attach_inline_facade", self, door)
		var leaves := add_solid(Rect2(-1.3,2.13,2.6,.18), "DoorLeaves")
		door_blocker = leaves.get_child(0) as CollisionPolygon2D
		return
	var passage := preload("res://guns/ammunation/AmmunationPassage.gd").new()
	passage.room = room
	passage.entrance = door
	add_child(passage)

func _process(delta: float) -> void:
	if not is_instance_valid(sprite_3d): return
	var screen_point := sprite_3d.get_global_transform_with_canvas().origin
	var on_screen := is_visible_in_tree() and get_viewport_rect().grow(200).has_point(screen_point)
	if is_instance_valid(animated_entrance):
		var actor_inside := false
		var near_threshold := false
		if is_instance_valid(inline_room):
			var actor := get_tree().get_first_node_in_group("player") as Node2D
			if is_instance_valid(actor) and actor.get("is_dead") != true and actor.visible:
				actor_inside = inline_room.call("contains_point", actor.global_position)
				var door_point := animated_entrance.to_local(actor.global_position)
				# Keep the leaves open between the sensor and the interior boundary.
				near_threshold = absf(door_point.x) < 44.0 and absf(door_point.y) < 70.0
		var target := 1.0 if animated_entrance.enabled and (animated_entrance._door_open or animated_entrance.get_nearest_actor()!=null or actor_inside or near_threshold) else 0.0
		var amount := move_toward(_door_amount,target,delta / .45)
		if not is_equal_approx(amount,_door_amount):
			_door_amount = amount
			model.set_open_amount(amount)
			if is_instance_valid(door_blocker):
				door_blocker.disabled = amount >= .75
			if on_screen: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if on_screen and not _was_on_screen:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	_was_on_screen = on_screen
