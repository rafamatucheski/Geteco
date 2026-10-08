extends CanvasLayer
## Escuridão dos esgotos de rua: a câmera é fixa e o `NativePlace` remove as luzes de ambiente da sala, então o
## escuro vem de uma camada 2D entre o 3D e a interface. Ela escurece e tinge a cena, escurece mais nas bordas e abre
## poças de luz sobre as luzes reais da sala (lâmpadas que piscam, barris de fogo) e um halo curto em volta do Dante.
## Na sessão, só desenha quando Dante já ocupa a sala, nunca durante sua preparação.
const MAX_LIGHTS := 12
var tint := Color(0.012, 0.02, 0.02)
var base_alpha := 0.62
var edge_alpha := 0.9
var halo := 3.2
var halo_strength := 0.55
var model: Node3D
var _material := ShaderMaterial.new()
var _rect := ColorRect.new()

const SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.012, 0.02, 0.02, 1.0);
uniform float base_alpha = 0.62;
uniform float edge_alpha = 0.9;
uniform float aspect = 1.777;
uniform int light_count = 0;
uniform vec4 lights[12];        // xy = posição (uv), z = raio (altura da tela), w = intensidade
uniform vec4 light_colors[12];
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = (uv - 0.5) * vec2(aspect, 1.0);
	float vignette = smoothstep(0.25, 0.95, length(centered) * 1.35);
	float dark = mix(base_alpha, edge_alpha, vignette);
	float lit = 0.0;
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		if (i >= light_count) break;
		float d = length((uv - lights[i].xy) * vec2(aspect, 1.0)) / max(lights[i].z, 0.001);
		float f = clamp(1.0 - d, 0.0, 1.0);
		f = f * f * lights[i].w;
		lit += f;
		glow += light_colors[i].rgb * f;
	}
	lit = clamp(lit, 0.0, 1.0);
	vec3 warm = glow / max(lit, 0.001);
	vec3 color = mix(tint.rgb, warm * 0.32, lit * 0.55);
	COLOR = vec4(color, clamp(dark * (1.0 - lit * 0.94), 0.0, 1.0));
}
"""

func _init() -> void:
	layer = -1
	hide()
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

func configure(room: Node3D, mood: Dictionary) -> void:
	model = room
	tint = mood.get("tint", tint)
	base_alpha = float(mood.get("base", base_alpha))
	edge_alpha = float(mood.get("edge", edge_alpha))
	halo = float(mood.get("halo", halo))
	halo_strength = float(mood.get("halo_strength", halo_strength))
	_material.set_shader_parameter("tint", tint)
	_material.set_shader_parameter("base_alpha", base_alpha)
	_material.set_shader_parameter("edge_alpha", edge_alpha)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	visible = camera != null and _room_is_current()
	if not visible:
		_material.set_shader_parameter("light_count", 0)
		return
	var size := get_viewport().get_visible_rect().size
	_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	var positions: Array[Vector4] = []
	var colors: Array[Vector4] = []
	var one_meter := _pixels_per_meter(camera, model.global_position)
	for light in model.get("lights") as Array:
		if not is_instance_valid(light) or not light.is_inside_tree() or not light.visible: continue
		if positions.size() >= MAX_LIGHTS - 1: break
		var screen := camera.unproject_position(light.global_position) / size
		var radius := minf(light.omni_range, 5.5) * one_meter / size.y
		positions.append(Vector4(screen.x, screen.y, radius, clampf(light.light_energy / 2.0, 0.0, 1.4)))
		colors.append(Vector4(light.light_color.r, light.light_color.g, light.light_color.b, 1.0))
	var player: Variant = model.get_parent().get_parent().get("player") if model.get_parent() != null and model.get_parent().get_parent() != null else null
	if player is Node3D and (player as Node3D).is_inside_tree():
		var at := camera.unproject_position((player as Node3D).global_position + Vector3.UP * 0.9) / size
		positions.append(Vector4(at.x, at.y, halo * one_meter / size.y, halo_strength))
		colors.append(Vector4(0.55, 0.62, 0.6, 1.0))
	var packed_positions := PackedVector4Array()
	var packed_colors := PackedVector4Array()
	for index in MAX_LIGHTS:
		packed_positions.append(positions[index] if index < positions.size() else Vector4.ZERO)
		packed_colors.append(colors[index] if index < colors.size() else Vector4.ZERO)
	_material.set_shader_parameter("lights", packed_positions)
	_material.set_shader_parameter("light_colors", packed_colors)
	_material.set_shader_parameter("light_count", positions.size())

func _room_is_current() -> bool:
	if not is_instance_valid(model) or not model.is_inside_tree() or not model.is_visible_in_tree(): return false
	var room := model.get_parent()
	var world := room.get_parent() if room != null else null
	var session: Variant = world.get("session") if world != null else null
	# Standalone room previews have no gameplay session.
	if session == null: return true
	return session.room == room and session.state.place_id == str(room.definition.id)

func _pixels_per_meter(camera: Camera3D, at: Vector3) -> float:
	var a := camera.unproject_position(at)
	var b := camera.unproject_position(at + camera.global_basis.x)
	return a.distance_to(b)
