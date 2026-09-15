shader_type canvas_item;
// Foreground portion of an existing actor texture, limited to the actual pole
// silhouette. The ordinary sprite still supplies all other world occlusion.
uniform sampler2D post_texture : filter_linear;
uniform vec3 post_u;
uniform vec3 post_v;
uniform float post_y;
uniform vec2 support_a;
uniform vec2 support_b;
varying vec2 world_pixel;
void vertex() {
	world_pixel = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec2 uv = vec2(dot(post_u, vec3(world_pixel,1.0)), dot(post_v, vec3(world_pixel,1.0)));
	float span = support_b.x-support_a.x;
	float t = abs(span) > 0.01 ? clamp((world_pixel.x-support_a.x)/span,0.0,1.0) : 0.5;
	float floor_y = mix(support_a.y,support_b.y,t);
	if (floor_y <= post_y || any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) discard;
	COLOR.a *= texture(post_texture, uv).a;
}
