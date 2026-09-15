extends "res://world/harbor/HarborTransitPassenger.gd"
## Preserve civilian physics and animation while sharing the terminal 3D scene.
var uses_terminal_stage := false

func _update_viewport_render_state(delta: float) -> void:
	if not uses_terminal_stage:
		super._update_viewport_render_state(delta)
		return
	# The articulated rig has moved to the shared stage. Its old per-person
	# viewport has no model to render; roof occlusion now comes from real depth.
	_viewport_render_active = true
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func attach_to_terminal(stage: Node3D) -> void:
	model_root.reparent(stage, false)
	model_root.scale *= 0.90
	sprite_3d_display.hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	uses_terminal_stage = true
