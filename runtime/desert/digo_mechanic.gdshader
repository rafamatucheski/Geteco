shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_texture : filter_linear_mipmap;
uniform int outfit = 2;
uniform vec4 shirt_color : source_color = vec4(0.20,0.28,0.33,1.0);
varying float trouser_mask;
void vertex() {
 // The local copy keeps the supplied face and shoes. Work trousers cover
 // the original shorts/bare calves only; the motocross material is intact.
 trouser_mask=smoothstep(0.15,0.20,VERTEX.y)*(1.0-smoothstep(0.78,0.84,VERTEX.y));
}
void fragment() {
 vec3 original=texture(albedo_texture,UV).rgb;
 float garment=smoothstep(0.35,0.65,COLOR.a);
 vec3 top=mix(original,shirt_color.rgb,garment);
 float weave=0.92+dot(original,vec3(0.02,0.05,0.03));
 ALBEDO=mix(top,vec3(0.13,0.18,0.21)*weave,trouser_mask);
 ROUGHNESS=mix(texture(roughness_texture,UV).g,0.94,max(garment,trouser_mask));
 NORMAL_MAP=mix(texture(normal_texture,UV).rgb,vec3(0.5,0.5,1.0),max(garment,trouser_mask));
}
