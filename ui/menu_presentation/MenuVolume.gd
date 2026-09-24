extends VBoxContainer
## Caller owns applying and saving. Range matches FullSession.

var slider := HSlider.new()

func _init() -> void:
	var label := Label.new()
	label.text = "Volume geral"
	add_child(label)
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.custom_minimum_size.y = 44
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = label.text
	add_child(slider)

func configure(value: float, on_changed: Callable) -> void:
	slider.set_value_no_signal(clampf(value, 0, 1))
	if on_changed.is_valid(): slider.value_changed.connect(on_changed)
