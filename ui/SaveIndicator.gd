extends Control
## Brief acknowledgement of a successfully published save. No idle processing.
const DURATION := 1.4
var remaining := 0.0
var angle := 0.0
var failed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -58.0
	offset_top = -58.0
	offset_right = -22.0
	offset_bottom = -22.0
	hide()
	set_process(false)

func acknowledge() -> void:
	failed = false
	tooltip_text = ""
	remaining = DURATION
	show()
	set_process(true)
	queue_redraw()

func reject(reason: String) -> void:
	failed = true
	tooltip_text = reason
	remaining = 3.0
	show()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		hide()
		set_process(false)
		return
	if not failed:
		angle = fposmod(angle + delta * TAU, TAU)
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, 17.0, Color(0.02, 0.03, 0.04, 0.65))
	if failed:
		draw_arc(center, 10.0, 0.0, TAU, 32, Color("ee8c72"), 2.5, true)
		draw_line(center + Vector2(0, -5), center + Vector2(0, 1), Color("ee8c72"), 2.5, true)
		draw_circle(center + Vector2(0, 5), 1.3, Color("ee8c72"))
		return
	draw_arc(center, 10.0, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 2.5, true)
	draw_arc(center, 10.0, angle, angle + TAU * 0.7, 24, Color(0.95, 0.97, 1.0), 2.5, true)
