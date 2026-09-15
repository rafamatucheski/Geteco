shader_type canvas_item;
uniform float reveal = 0.0;
uniform vec2 focus = vec2(0.0);
varying vec4 tint;
varying vec2 world_position;
void vertex(){ tint = COLOR; world_position=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy; }
void fragment(){
	float amount = reveal * (1.0-smoothstep(100.0,210.0,distance(world_position,focus)));
	vec2 step_uv = TEXTURE_PIXEL_SIZE * amount * 4.0;
	vec4 c=texture(TEXTURE,UV)*0.4;
	c+=texture(TEXTURE,UV+vec2(step_uv.x,0.0))*0.15;
	c+=texture(TEXTURE,UV-vec2(step_uv.x,0.0))*0.15;
	c+=texture(TEXTURE,UV+vec2(0.0,step_uv.y))*0.15;
	c+=texture(TEXTURE,UV-vec2(0.0,step_uv.y))*0.15;
	COLOR=c*tint;
	COLOR.a *= 1.0-amount*0.76;
}
