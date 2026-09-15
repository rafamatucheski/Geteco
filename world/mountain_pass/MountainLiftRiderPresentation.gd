extends RefCounted
## The actual Dante rig rides inside the chair's depth buffer.
var player: Node2D
var chair: Node2D
var rig: Node3D
var old_parent: Node
var states: Array[Dictionary] = []
var display: Sprite2D
var old_visible := true
var old_physics := true
var active := false

func begin(actor: Node2D, area: Node2D, points: PackedVector2Array) -> void:
	if actor.has_meta("interior_actor_presentation"): actor.get_meta("interior_actor_presentation").restore()
	player = actor
	rig = actor.get("model_root") as Node3D
	if rig == null: return # Logic-only test riders have no render adapter.
	display = actor.get("sprite_3d_display") as Sprite2D
	if display == null: return
	active = true
	old_physics = actor.is_physics_processing()
	actor.set_physics_process(false)
	old_parent = rig.get_parent()
	old_visible = display.visible
	display.hide()
	chair = preload("res://world/mountain_pass/MountainChairliftChair.gd").new()
	area.add_child(chair)
	chair.setup(points,0.0,true,false)
	chair.set_process(false)
	for node in [rig] + rig.find_children("*","Node3D",true,false):
		if node == rig or String(node.name).contains("Upper") or String(node.name).contains("Lower"):
			states.append({"node":node,"transform":node.transform})
	rig.reparent(chair.model.chair_root,false)
	rig.position = Vector3(.22,-.57,-.12)
	rig.rotation = Vector3(0,PI,0)
	for side in ["left","right"]:
		player.get(side+"_upper_leg").rotation.x = 1.35
		player.get(side+"_lower_leg").rotation.x = -1.35
		player.get(side+"_upper_arm").rotation.x = .35
		player.get(side+"_lower_arm").rotation.x = .8
	update()

func update() -> void:
	if not is_instance_valid(chair) or not is_instance_valid(player): return
	chair.global_position = player.global_position
	chair.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func restore() -> void:
	if not active: return
	active = false
	if is_instance_valid(rig) and is_instance_valid(old_parent):
		rig.reparent(old_parent,false)
		for state in states:
			if is_instance_valid(state.node): state.node.transform = state.transform
	if is_instance_valid(display): display.visible = old_visible
	if is_instance_valid(player) and player.get("is_dead") != true and player.get("is_recovering") != true:
		player.set_physics_process(old_physics)
	if is_instance_valid(chair): chair.queue_free()
	states.clear()
	chair = null
