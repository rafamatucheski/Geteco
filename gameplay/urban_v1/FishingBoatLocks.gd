extends Control
## Two fixed-size, non-interactive hints; no text, light or viewport per boat.
var terminal: Node3D
var anchors: Array[Vector3] = []
var screen_points: Array[Vector2] = []
var nearby: Array[Vector3] = []
var scan_left := 0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	scan_left-=delta
	if scan_left<=0:
		scan_left=.15
		nearby.clear()
		if is_instance_valid(terminal) and terminal.active:
			var player: Vector3=terminal.session.world.player.global_position
			if terminal.session.state.place_id.is_empty():
				for anchor in anchors:
					if player.distance_squared_to(anchor-Vector3.UP*1.6)<20.25: nearby.append(anchor)
	var camera:=get_viewport().get_camera_3d()
	var projected: Array[Vector2]=[]
	if camera!=null:
		for anchor in nearby:
			if camera.is_position_behind(anchor): continue
			var point:=camera.unproject_position(anchor)
			if get_viewport_rect().has_point(point): projected.append(point.round())
	if projected!=screen_points:
		screen_points=projected
		queue_redraw()

func _draw() -> void:
	for point in screen_points:
		var shade:=Color(0.06,.10,.12,.85)
		var ink:=Color(.9,.88,.78,.85)
		# 14 × 18 pixels with a fine dark outline: only the familiar padlock shape.
		draw_arc(point+Vector2(0,-5),4,PI,TAU,12,shade,5,true)
		draw_arc(point+Vector2(0,-5),4,PI,TAU,12,ink,2,true)
		draw_rect(Rect2(point+Vector2(-7,-5),Vector2(14,11)),shade)
		draw_rect(Rect2(point+Vector2(-5.5,-3.5),Vector2(11,8)),ink)
		draw_circle(point+Vector2(0,-.5),1.3,shade,true,-1,true)
		draw_line(point+Vector2(0,0),point+Vector2(0,2),shade,1.5,true)
