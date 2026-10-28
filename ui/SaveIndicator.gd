extends Control
## Brief acknowledgement of a successfully published save. No idle processing.
## `set_blocked` deixa o ícone de falha fixo com o motivo ao lado enquanto o salvamento
## estiver desligado na sessão; antes só o F5 mostrava a recusa e o autosave parava calado.
const DURATION := 1.4
var remaining := 0.0
var angle := 0.0
var failed := false
var blocked_reason := ""
var _blocked_label: Label
var _hud: Node
var _hud_root: Control
var _layout_queued := false

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
	get_viewport().size_changed.connect(_queue_layout)
	_queue_layout()

func acknowledge() -> void:
	failed = false
	tooltip_text = ""
	remaining = DURATION
	show()
	set_process(true)
	_queue_layout()
	queue_redraw()

func reject(reason: String) -> void:
	failed = true
	tooltip_text = reason
	remaining = 3.0
	show()
	set_process(true)
	_queue_layout()
	queue_redraw()

func set_blocked(reason: String) -> void:
	blocked_reason = reason
	if reason.is_empty():
		if is_instance_valid(_blocked_label): _blocked_label.hide()
		if remaining <= 0.0: hide()
		_queue_layout()
		return
	if not is_instance_valid(_blocked_label):
		_blocked_label = Label.new()
		_blocked_label.name = "BlockedReason"
		_blocked_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blocked_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_blocked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_blocked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_blocked_label.add_theme_color_override("font_color", Color("ee8c72"))
		_blocked_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.9))
		_blocked_label.add_theme_constant_override("outline_size", 1)
		_blocked_label.add_theme_font_size_override("font_size", 13)
		# À esquerda do ícone, sem cobrir o centro da tela.
		_blocked_label.position = Vector2(-372, -6)
		_blocked_label.size = Vector2(364, 48)
		add_child(_blocked_label)
		_blocked_label.minimum_size_changed.connect(_queue_layout)
	_blocked_label.text = reason
	_blocked_label.show()
	failed = true
	tooltip_text = reason
	show()
	_queue_layout()
	queue_redraw()

func _queue_layout() -> void:
	if _layout_queued or not is_inside_tree(): return
	_layout_queued = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_queued = false
	if not is_inside_tree(): return
	if not is_instance_valid(_hud):
		var candidate := get_tree().get_first_node_in_group("hud")
		if is_instance_valid(candidate) and candidate.has_method("save_feedback_bottom"):
			_hud = candidate
			_hud_root = _hud.get("root_control")
			if _hud.has_signal("layout_changed"): _hud.connect("layout_changed", _queue_layout)
			if _hud.has_signal("visibility_changed"): _hud.connect("visibility_changed", _queue_layout)
			if is_instance_valid(_hud_root): _hud_root.visibility_changed.connect(_queue_layout)
	var hud_visible := is_instance_valid(_hud_root) and _hud_root.is_visible_in_tree()
	if _hud is CanvasLayer and not _hud.visible: hud_visible = false
	if hud_visible and not get_tree().paused:
		var label_height := 0.0
		if is_instance_valid(_blocked_label) and _blocked_label.visible:
			var label_width := maxf(80,float(_hud.call("save_feedback_width"))-44) if _hud.has_method("save_feedback_width") else 220.0
			_blocked_label.size.x = label_width
			label_height = _blocked_label.get_combined_minimum_size().y
			_blocked_label.size.y = label_height
			_blocked_label.position = Vector2(-label_width-8, (36.0-label_height)*0.5)
		var band_height := maxf(36.0, label_height)
		var bottom := float(_hud.call("save_feedback_bottom"))
		var top := float(_hud.call("save_feedback_top")) if _hud.has_method("save_feedback_top") else -1.0
		if top>=0: bottom=top+band_height
		var icon_top := bottom-band_height+(band_height-36.0)*0.5
		set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -60.0
		offset_right = -24.0
		offset_top = icon_top
		offset_bottom = icon_top+36.0
	else:
		# This independent layer remains readable while gameplay HUD is hidden.
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		offset_left = -58.0
		offset_top = -58.0
		offset_right = -22.0
		offset_bottom = -22.0
		if is_instance_valid(_blocked_label):
			_blocked_label.position = Vector2(-372, -6)
			_blocked_label.size = Vector2(364, 48)

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		set_process(false)
		if not blocked_reason.is_empty():
			# Volta ao ícone fixo de bloqueio depois de um aviso breve.
			failed = true
			queue_redraw()
			return
		hide()
		return
	if not failed:
		angle = fposmod(angle + delta * TAU, TAU)
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, 17.0, Color(0.02, 0.03, 0.04, 0.65), true, -1.0, true)
	if failed:
		draw_arc(center, 10.0, 0.0, TAU, 32, Color("ee8c72"), 2.5, true)
		draw_line(center + Vector2(0, -5), center + Vector2(0, 1), Color("ee8c72"), 2.5, true)
		draw_circle(center + Vector2(0, 5), 1.3, Color("ee8c72"), true, -1.0, true)
		return
	draw_arc(center, 10.0, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 2.5, true)
	draw_arc(center, 10.0, angle, angle + TAU * 0.7, 24, Color(0.95, 0.97, 1.0), 2.5, true)
