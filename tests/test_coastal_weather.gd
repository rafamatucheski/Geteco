extends SceneTree
const LOOK := preload("res://runtime/atmosphere/CoastalWeatherLook.gd")
var errors: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var dry := LOOK.sample(1.0,0.0,0.0)
	var marine := LOOK.sample(1.0,.52,0.0)
	var rain := LOOK.sample(1.0,.72,1.0)
	check(dry.sun.r>dry.sun.b,"A has warm sunlight")
	check(marine.shadow.g>dry.shadow.g and marine.horizon.b>dry.horizon.b,"B has marine fill and a cooler reflection horizon")
	check(rain.sun.b>rain.sun.r and rain.saturation<dry.saturation,"C has cool light and restrained saturation")
	check(LOOK.sample(0.0,1.0,1.0).horizon.get_luminance()<rain.horizon.get_luminance()*.2,"Rain reflections cannot turn night into day")
	check(LOOK.sample(1.0,0.0,.6).marine_weight>0,"Clearing weather retains a humid appearance during drying")
	var previous := LOOK.sample(1,0,0)
	for i in range(1,101):
		var next := LOOK.sample(1,float(i)/100.0,0)
		check(absf(next.saturation-previous.saturation)<.02,"Continuous weather palette at step "+str(i))
		previous = next
	check(is_equal_approx(LOOK.advance_wetness(0,true,45),1.0),"Rain wets the street over 45 seconds")
	check(is_equal_approx(LOOK.advance_wetness(1,false,60),.5),"Street stays half wet one minute after rain")
	check(LOOK.advance_wetness(.5,false,120)==0,"Street eventually dries")
	check(LOOK.advance_wetness(.5,true,-1)==.5,"Negative deltas do not change moisture")
	var env := Environment.new()
	var original := Sky.new()
	env.sky = original
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var sun := DirectionalLight3D.new()
	sun.shadow_opacity = .8
	sun.shadow_blur = 1.1
	var look := LOOK.new()
	look.apply(env,sun,1,.52,.5,1,false)
	check(env.sky==look.sky and env.reflected_light_source==Environment.REFLECTION_SOURCE_SKY,"Coastal exterior installs its shared reflection sky")
	var resource := look.sky
	look.apply(env,sun,1,.52,.5,1,false)
	check(look.sky==resource,"Repeated updates reuse the sky resource")
	look.apply(env,sun,1,1,1,1,true)
	check(env.sky==original and env.reflected_light_source==Environment.REFLECTION_SOURCE_DISABLED,"Interior restores the previous reflection environment")
	check(is_equal_approx(sun.shadow_opacity,.8),"Interior restores the previous shadow opacity")
	check(is_equal_approx(sun.shadow_blur,1.1),"Interior restores the previous shadow filter")
	look.apply(env,sun,1,0,0,1,false,.72)
	check(is_equal_approx(sun.rotation_degrees.x,-35),"Late afternoon uses a grazing but bounded solar angle")
	sun.rotation_degrees.x = -42
	look.apply(env,sun,0,0,0,1,false,.93)
	check(is_equal_approx(sun.rotation_degrees.x,-42),"Night preserves the elevated lunar angle")
	check(is_equal_approx(sun.shadow_blur,1.1),"Night preserves the original lunar shadow filter")
	look.apply(env,sun,1,0,0,1,false)
	look.apply(env,sun,1,0,0,0,false)
	check(env.sky==original,"Mountain/desert leave the coastal sky behind")
	look.apply(env,sun,1,0,0,1,false)
	var other := Sky.new()
	env.sky = other
	look.release(env)
	check(env.sky==other,"Releasing coastal sky never overwrites another environment owner")
	sun.free()
	var state = preload("res://runtime/GameState.gd").new()
	state.world_state.coastal_wetness = .63
	var store = preload("res://runtime/SaveStore.gd").new()
	store.path = "user://tests/coastal-weather-"+str(Time.get_ticks_usec())+"/progress.json"
	check(store.save(state)==OK,"Isolated save accepts partial moisture")
	var restored = preload("res://runtime/GameState.gd").new()
	check(store.load_into(restored).get("ok",false),"Isolated save reloads successfully")
	check(is_equal_approx(float(restored.world_state.get("coastal_wetness",-1)),.63),"Drying state survives a real disk round trip")
	var snapshot: Dictionary = state.snapshot()
	for bad in [-.1,1.1,NAN,"wet"]:
		snapshot.world.coastal_wetness = bad
		check(not restored.restore_snapshot(snapshot),"Invalid moisture is rejected without replacing the save state")
	snapshot.world.erase("coastal_wetness")
	check(restored.restore_snapshot(snapshot),"Older saves without moisture remain valid")
	var glass: StandardMaterial3D = preload("res://world/city_look/CityLookMaterials.gd").window_glass_dark()
	check(not glass.normal_enabled and glass.roughness<.3,"Exterior dark glass never receives matte plaster finish")
	check(glass==preload("res://world/city_look/CityLookMaterials.gd").window_glass_dark(),"Glazing instances reuse the same material")
	print("COASTAL_WEATHER_CONTRACT ",checks," checks; errors=",errors)
	quit(0 if errors.is_empty() else 1)
