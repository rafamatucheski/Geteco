shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ocean_surface : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 world_center = vec2(0.0);
uniform vec2 viewport_size = vec2(1280.0,720.0);
uniform float pixels_per_metre = 1.0;

void fragment() {
	// Static water material, fixed to survey coordinates when panning/zooming.
	// Land and inland water retain their authoritative geography above it.
	vec2 world = world_center + (UV * viewport_size - viewport_size * 0.5) / max(pixels_per_metre,0.001);
	vec3 sea = texture(ocean_surface, world / 1100.0).rgb;
	COLOR = vec4(mix(vec3(0.045,0.11,0.15), sea, 0.72),1.0);
}
