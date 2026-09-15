extends Node
## Move the production rig into the car's depth buffer during access. No copy,
## z-index trick or second actor viewport is rendered over the bodywork.
var actor: CharacterBody2D
var car: CharacterBody2D
var rig: Node3D
var previous_parent: Node
var previous_transform: Transform3D
var sprite_visible := true
var previous_update := 0
var foot_offset := Vector2.ZERO
var entry := 0.0
var side := 1.0
var old_scale := Vector3.ONE

func configure(person: CharacterBody2D, vehicle: CharacterBody2D, entry_side: float) -> void:
	actor = person
	car = vehicle
	side = entry_side
	rig = actor.model_root
	previous_parent = rig.get_parent()
	previous_transform = rig.transform
	old_scale = rig.scale
	var original_camera: Camera3D = actor.viewport_3d.get_camera_3d()
	var camera: Camera3D = car.body_viewport.get_camera_3d()
	original_camera.force_update_transform()
	camera.force_update_transform()
	var foot := original_camera.unproject_position(Vector3.ZERO)
	foot_offset = actor.sprite_3d_display.to_global(foot-Vector2(actor.viewport_3d.size)*.5)-actor.global_position
	var original_height: float = original_camera.unproject_position(Vector3.UP).distance_to(foot)*actor.sprite_3d_display.scale.x
	var target_height: float = camera.unproject_position(Vector3.UP).distance_to(camera.unproject_position(Vector3.ZERO))*car.sprite.scale.x
	sprite_visible = actor.sprite_3d_display.visible
	previous_update = actor.viewport_3d.render_target_update_mode
	rig.reparent(car.body_viewport,false)
	rig.scale = old_scale*original_height/maxf(target_height,.01)
	actor.sprite_3d_display.hide()
	actor.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	actor.tree_exiting.connect(restore,CONNECT_ONE_SHOT)
	camera.tree_exiting.connect(restore,CONNECT_ONE_SHOT)
	process_priority = 100
	sync()

func _process(_delta: float) -> void: sync()

func sync() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(car) or not is_instance_valid(rig): return
	var camera: Camera3D = car.body_viewport.get_camera_3d()
	var pixel: Vector2 = car.sprite.to_local(actor.global_position+foot_offset)+Vector2(car.body_viewport.size)*.5
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var floor_point := origin-direction*(origin.y/direction.y)
	var seat_point: Vector3 = car.model.to_global(Vector3(side*.36,-.08,.15))
	rig.position = floor_point.lerp(seat_point,smoothstep(.25,.9,entry))

func restore() -> void:
	if not is_instance_valid(rig): return
	if not is_instance_valid(previous_parent):
		rig.queue_free()
		rig = null
		return
	rig.reparent(previous_parent,false)
	rig.transform = previous_transform
	if is_instance_valid(actor):
		actor.sprite_3d_display.visible = sprite_visible
		actor.viewport_3d.render_target_update_mode = previous_update
	rig = null

func _exit_tree() -> void: restore()
