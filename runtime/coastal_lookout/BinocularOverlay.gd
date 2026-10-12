extends CanvasLayer
## Only functional controls: the landscape carries the atmosphere and story.
var controller: Node
var readout: Label

func _ready() -> void:
	layer = 16
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://runtime/coastal_lookout/binocular_mask.gdshader")
	vignette.material = material
	screen.add_child(vignette)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-235, -68)
	bar.add_theme_constant_override("separation", 16)
	screen.add_child(bar)
	readout = Label.new()
	readout.custom_minimum_size = Vector2(72, 44)
	readout.add_theme_font_size_override("font_size", 20)
	bar.add_child(readout)
	for entry in [["−", 4.0], ["+", -4.0]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(52, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(controller.adjust_zoom.bind(entry[1]))
		bar.add_child(button)
	var exit_button := Button.new()
	var controls = get_node_or_null("/root/GameInput")
	exit_button.text = String(TranslationServer.translate("%s · Sair")) % controls.prompt("interact") if controls != null else "Sair"
	exit_button.custom_minimum_size = Vector2(140, 44)
	exit_button.focus_mode = Control.FOCUS_NONE
	exit_button.pressed.connect(controller.leave)
	bar.add_child(exit_button)
	var hint := Label.new()
	var touch: bool = OS.has_feature("android") or (controls != null and controls.get_meta("touch_controls_active",false))
	hint.text = "Olhar: arraste    Zoom: − / +" if touch else "Olhar: mouse / analógico    Zoom: roda / LT · RT"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-228, -99)
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.8, 0.86, 0.82, 0.8)
	screen.add_child(hint)
	update_readout(1.0)

func update_readout(magnification: float) -> void:
	readout.text = "%.1f×" % magnification
