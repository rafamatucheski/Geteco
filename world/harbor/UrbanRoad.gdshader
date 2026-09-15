shader_type canvas_item;
uniform sampler2D grain : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D paving : source_color, repeat_enable, filter_linear_mipmap;
varying vec2 ground_position;
void vertex() {
    ground_position=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;
}
void fragment() {
    float high=max(COLOR.r,max(COLOR.g,COLOR.b));
    float low=min(COLOR.r,min(COLOR.g,COLOR.b));
    // White/yellow paint stays crisp; only neutral road and footway surfaces wear.
    if (high<0.79 && high-low<0.16) {
        float stone=texture(paving,ground_position/256.0).r;
        float asphalt=texture(grain,ground_position/256.0).r;
        COLOR.rgb*=mix(asphalt,stone,smoothstep(0.3,0.58,high));
    }
}
