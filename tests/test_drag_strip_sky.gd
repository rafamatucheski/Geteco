extends SceneTree
const SKY = preload("res://runtime/atmosphere/DragStripSky.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("DRAG_SKY ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	var sky := SKY.new()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.background_color=Color("829da6")
	sky.apply(environment,Vector3(-900,0,-1320),.75,0.0,1.0,false)
	check(environment.background_mode==Environment.BG_SKY and sky.installed,"track receives clock-driven sky")
	check(environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR,"sky does not replace ambient lighting")
	check(is_equal_approx(float(sky.material.get_shader_parameter("hour")),.75),"sky follows world time instead of forcing sunset")
	var resource := environment.sky
	sky.apply(environment,Vector3(-400,0,-1320),.9,.8,.2,false)
	check(environment.sky==resource,"travelling race reuses one sky resource")
	sky.update_lightning(.8,1)
	check(is_equal_approx(float(sky.material.get_shader_parameter("lightning_strength")),.8),"distant bolt follows shared storm envelope")
	var offset: float = sky.material.get_shader_parameter("strike_offset")
	sky.update_lightning(.4,1)
	check(is_equal_approx(float(sky.material.get_shader_parameter("strike_offset")),offset),"bolt stays fixed during its flash")
	sky.apply(environment,Vector3(-400,0,-1320),.9,.8,.2,true)
	check(not sky.installed and environment.sky==null and environment.background_mode==Environment.BG_COLOR,"interior restores original background")
	sky.update_lightning(1.0,2)
	check(is_zero_approx(float(sky.material.get_shader_parameter("lightning_strength"))),"shelter suppresses distant discharge")
	check(environment.reflected_light_source==Environment.REFLECTION_SOURCE_BG,"original reflection policy restored")
	sky.apply(environment,Vector3(-900,0,-1320),.25,0.0,1.0,false)
	sky.apply(environment,Vector3(100,0,-500),.25,0.0,1.0,false)
	check(not sky.installed and environment.sky==null,"leaving drag area releases local sky")
	quit(0 if failures==0 else 1)
