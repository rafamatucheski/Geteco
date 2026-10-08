extends Control
const STYLE := preload("res://ui/GameStyle.gd")
var veil: ColorRect
var status: Label
var meter: ProgressBar
var shader_material: ShaderMaterial
func _ready() -> void:
	name="WineEffect"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil=ColorRect.new()
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shader_material=ShaderMaterial.new()
	shader_material.shader=preload("res://gameplay/wine/wine_vignette.gdshader")
	veil.material=shader_material
	add_child(veil)
	var box:=VBoxContainer.new()
	box.position=Vector2(24,184)
	box.custom_minimum_size=Vector2(194,44)
	box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(box)
	status=STYLE.label("",14,Color("edd4ab"))
	box.add_child(status)
	meter=ProgressBar.new()
	meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	meter.show_percentage=false
	meter.custom_minimum_size=Vector2(194,5)
	var background:=StyleBoxFlat.new(); background.bg_color=Color(0.08,0.04,0.05,0.6)
	var fill:=StyleBoxFlat.new(); fill.bg_color=Color("c39a64")
	meter.add_theme_stylebox_override("background",background)
	meter.add_theme_stylebox_override("fill",fill)
	box.add_child(meter)
	hide()
func update_effect(intensity: float, phase: float, text: String, unobstructed: bool) -> void:
	visible=intensity>0.0001 and unobstructed
	if not visible: return
	shader_material.set_shader_parameter("intensity",intensity)
	shader_material.set_shader_parameter("phase",phase)
	if status.text!=text: status.text=text
	meter.value=intensity*100.0
