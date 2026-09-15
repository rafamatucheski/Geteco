extends "res://world/mountain_pass/MountainStaticModelView.gd"
## A streamed branch can be built while the loading screen suspends rendering.
## Refresh its static texture when it actually enters the gameplay camera.
var _was_on_screen := false
var animated_entrance: BuildingEntrance
var _door_amount := 0.0

func bind_entrance(door: BuildingEntrance, room: Node2D) -> void:
	animated_entrance = door
	var passage := preload("res://guns/ammunation/AmmunationPassage.gd").new()
	passage.room = room
	passage.entrance = door
	add_child(passage)

func _process(delta: float) -> void:
	if not is_instance_valid(sprite_3d): return
	var screen_point := sprite_3d.get_global_transform_with_canvas().origin
	var on_screen := is_visible_in_tree() and get_viewport_rect().grow(200).has_point(screen_point)
	if is_instance_valid(animated_entrance):
		var target := 1.0 if animated_entrance.enabled and (animated_entrance._door_open or animated_entrance.get_nearest_actor()!=null) else 0.0
		var amount := move_toward(_door_amount,target,delta / .45)
		if not is_equal_approx(amount,_door_amount):
			_door_amount = amount
			model.set_open_amount(amount)
			if on_screen: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if on_screen and not _was_on_screen:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	_was_on_screen = on_screen
