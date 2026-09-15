extends "res://world/mountain_pass/MountainStaticModelView.gd"
## Actors near an exterior share its real depth buffer, just as in interiors.
var solid_body: StaticBody2D
var depth_bounds := Rect2()
var _actors: Dictionary = {}
var _scan_clock := 0.0
var _canvas_bounds := Rect2()

func install_projected_solids() -> void:
	_canvas_bounds = Rect2(project_floor(depth_bounds.position),Vector2.ZERO)
	for corner in [Vector2(depth_bounds.end.x,depth_bounds.position.y),depth_bounds.end,Vector2(depth_bounds.position.x,depth_bounds.end.y)]:
		_canvas_bounds = _canvas_bounds.expand(project_floor(corner))
	solid_body = StaticBody2D.new()
	solid_body.name = "ProjectedSolids"
	solid_body.collision_layer = 1
	solid_body.collision_mask = 0
	add_child(solid_body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(model,solid_body,project_floor)
	set_process(true)

func _process(delta: float) -> void:
	_scan_clock += delta
	if _scan_clock < .12: return
	_scan_clock = 0.0
	for actor in _actors.keys():
		if not is_instance_valid(actor) or _actors[actor].actor != actor or not actor.is_visible_in_tree() or not _contains_actor(actor) or actor.has_meta("mountain_interior") or actor.has_meta("mountain_lift_riding") or actor.has_meta("mountain_falling"):
			_actors[actor].restore()
			_actors[actor].queue_free()
			_actors.erase(actor)
	for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("winter_resident"):
		if _actors.has(actor) or not actor.is_visible_in_tree() or actor.has_meta("interior_actor_presentation") or actor.has_meta("mountain_interior") or actor.has_meta("mountain_lift_riding") or actor.has_meta("mountain_falling"): continue
		if not _contains_actor(actor): continue
		var helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		add_child(helper)
		helper.configure(actor,camera_3d,sprite_3d)
		_actors[actor] = helper

func _contains_actor(actor: Node2D) -> bool:
	# Reject distant people before performing camera ray projections.
	return _canvas_bounds.has_point(to_local(actor.global_position)) and depth_bounds.has_point(unproject_floor(actor.global_position))

func _exit_tree() -> void:
	for helper in _actors.values(): helper.restore()
