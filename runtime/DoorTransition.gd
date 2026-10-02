extends CanvasLayer

const FADE_COLOR := Color(0.025, 0.035, 0.045, 1.0)

var veil: ColorRect
var _tween: Tween

func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	veil = ColorRect.new()
	veil.name = "DoorVeil"
	veil.color = FADE_COLOR
	veil.modulate.a = 0.0
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.hide()

func fade_to(alpha: float, duration: float) -> void:
	if is_instance_valid(_tween): _tween.kill()
	veil.visible = true
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(veil, "modulate:a", clampf(alpha, 0.0, 1.0), maxf(0.01, duration))
	await _tween.finished
	if veil.modulate.a <= 0.001: veil.hide()

func clear() -> void:
	if is_instance_valid(_tween): _tween.kill()
	veil.modulate.a = 0.0
	veil.hide()
