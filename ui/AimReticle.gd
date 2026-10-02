extends Control
## Small screen-space sight projected from the actual horizontal firing path.
var gameplay: Node
var blocked := false
var world_point := Vector3.ZERO

func _ready() -> void:
	name = "AimReticle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	hide()

func _process(_delta: float) -> void:
	visible = is_instance_valid(gameplay) and not get_tree().paused and gameplay.aim_feedback_active()
	if not visible: return
	var camera: Camera3D = gameplay.camera
	if not is_instance_valid(camera):
		hide()
		return
	# FullSession resolves mouse input during render processing. Query after
	# it (priority 100), so the marker uses this frame's cursor and muzzle.
	var feedback: Dictionary = gameplay.aim_feedback()
	world_point = feedback.point
	if blocked != bool(feedback.blocked):
		blocked = feedback.blocked
		queue_redraw()
	visible = not camera.is_position_behind(world_point)
	if not visible: return
	position = camera.unproject_position(world_point)

func _draw() -> void:
	var ink := Color("ffb568") if blocked else Color("f7fbef")
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(direction * 5.0, direction * 10.0, Color(0.03, 0.04, 0.06, 0.95), 4.0, true)
		draw_line(direction * 5.0, direction * 10.0, ink, 2.0, true)
	if blocked:
		for slope in [-1.0, 1.0]:
			draw_line(Vector2(-3, -3 * slope), Vector2(3, 3 * slope), Color.BLACK, 4.0, true)
			draw_line(Vector2(-3, -3 * slope), Vector2(3, 3 * slope), ink, 2.0, true)
	else:
		draw_circle(Vector2.ZERO, 2.5, Color.BLACK)
		draw_circle(Vector2.ZERO, 1.3, ink)
