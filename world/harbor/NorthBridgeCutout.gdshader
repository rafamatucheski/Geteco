shader_type canvas_item;
uniform vec4 patch;
uniform bool enabled = false;
varying vec2 world_position;
void vertex(){ world_position = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy; }
void fragment(){
	if(enabled && world_position.x >= patch.x && world_position.y >= patch.y && world_position.x < patch.x+patch.z && world_position.y < patch.y+patch.w) COLOR.a=0.0;
}
