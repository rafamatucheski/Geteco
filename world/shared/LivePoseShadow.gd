extends Sprite2D
var source_display: Sprite2D
var source_viewport: SubViewport
var last_foot := Vector2.INF
func _process(_delta: float) -> void:
	if not is_instance_valid(source_display) or not is_instance_valid(source_viewport): return
	if not source_display.is_visible_in_tree(): return
	var camera := source_viewport.get_camera_3d()
	if camera == null: return
	var foot := camera.unproject_position(Vector3.ZERO)
	if centered: foot -= Vector2(source_viewport.size)*.5
	foot += source_display.offset
	if not foot.is_equal_approx(last_foot):
		material.set_shader_parameter("foot",foot)
		last_foot=foot
