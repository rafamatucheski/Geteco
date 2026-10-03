shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_texture : filter_linear_mipmap;
uniform int outfit = 0;
uniform vec4 shirt_color : source_color = vec4(0.45, 0.45, 0.43, 1.0);
void fragment() {
 vec3 original = texture(albedo_texture, UV).rgb;
 float garment = smoothstep(0.35,0.65,COLOR.a);
 ALBEDO = outfit == 0 ? original : mix(original, shirt_color.rgb, garment);
 ROUGHNESS = mix(texture(roughness_texture,UV).g,0.9,outfit == 0 ? 0.0 : garment);
 NORMAL_MAP = mix(texture(normal_texture,UV).rgb,vec3(0.5,0.5,1.0),outfit == 0 ? 0.0 : garment);
}
