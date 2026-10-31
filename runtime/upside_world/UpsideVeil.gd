extends CanvasLayer
## Cortina independente, de posse por token. Não pode cancelar o tween de porta da sessão.
var veil: ColorRect
var amount := 0.0
var material: ShaderMaterial
func _ready() -> void:
	layer=116
	veil=ColorRect.new()
	veil.name="UpsideVeil"
	veil.color=Color("110c19")
	# A single inward violet ripple; no screen copy, flashing or persistent pass.
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float progress : hint_range(0.0,1.0) = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y,p.x);
	float curl = sin(angle * 3.0 + radius * 9.0 - progress * 5.0);
	float ring = exp(-pow((radius - (1.35 - progress)) * 5.0, 2.0));
	float energy = ring * (0.55 + curl * 0.20) * sin(progress * 3.14159265);
	COLOR = vec4(vec3(0.045,0.024,0.070) + vec3(0.19,0.065,0.30) * energy,progress);
}"""
	material = ShaderMaterial.new()
	material.shader = shader
	veil.material = material
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_amount(amount)
func set_amount(value: float) -> void:
	amount=clampf(value,0.0,1.0)
	if not is_instance_valid(veil): return
	material.set_shader_parameter("progress",amount)
	veil.visible=amount>0.001
