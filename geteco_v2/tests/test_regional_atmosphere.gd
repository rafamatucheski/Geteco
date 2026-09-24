extends SceneTree
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var harbor := Vector3(243.75,0,237.5)
	var forest := Vector3(640,0,-267)
	var summit := Vector3(670,0,-485)
	var resort := Vector3(11490.0/16,0,-7690.0/16)
	var cemetery := Vector3(-650.0/16,0,1740.0/16)
	var port := ATMOSPHERE.sample_at(harbor,.36,0,0)
	check(ATMOSPHERE.clock_color(.79).is_equal_approx(Color(1,.62,.38)),"Original sunset keyframe")
	check(ATMOSPHERE.daylight_at(.0)==0 and ATMOSPHERE.daylight_at(.5)==1,"Original night/day exposure endpoints")
	check(ATMOSPHERE.daylight_at(.84)<.3,"Twilight remains darker than day")
	var woods := ATMOSPHERE.sample_at(forest,.36,0,0)
	var snow := ATMOSPHERE.sample_at(summit,.36,0,0)
	check(is_equal_approx(port.saturation,.92),"Preserve authored Harbor saturation")
	check(woods.saturation<port.saturation,"Forest greens remain restrained")
	check(snow.shadow_tint.b>woods.shadow_tint.b,"Snow shadows retain blue identity")
	check(snow.haze>woods.haze and woods.haze>port.haze,"Haze increases from harbor through forest to summit")
	check(ATMOSPHERE.sample_at(cemetery,.36,0,0).saturation<port.saturation,"Cemetery local desaturation")
	check(ATMOSPHERE.sample_at(resort,.36,0,0).sunlight_tint.r>snow.sunlight_tint.r,"Resort warms highlights")
	check(ATMOSPHERE.sample_at(summit,.0,0,0).fog_color.get_luminance()<snow.fog_color.get_luminance()*.25,"Night fog stays dark")
	check(ATMOSPHERE.sample_at(harbor,.75,0,0).sunlight_tint.r>port.sunlight_tint.r,"Sunset warms daylight highlights")
	check(ATMOSPHERE.sample_at(harbor,.75,1,0).sunlight_tint.r<ATMOSPHERE.sample_at(harbor,.75,0,0).sunlight_tint.r,"Clouds suppress sunset warmth")
	check(ATMOSPHERE.weights_at(Vector3(480,0,100)).mountain==0,"East city must not receive mountain profile")
	var before := ATMOSPHERE.sample_at(Vector3(456.24,0,-285),.36,.72,1)
	var after := ATMOSPHERE.sample_at(Vector3(456.26,0,-285),.36,.72,1)
	check(absf(before.haze-after.haze)<.001,"Streaming seam does not switch atmosphere")
	var player := Node3D.new()
	player.position = harbor
	root.add_child(player)
	var sun := DirectionalLight3D.new()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var controller := {"world":{"player":player},"sun":sun,"environment":environment}
	var car := Node3D.new()
	root.add_child(car)
	car.position = summit
	controller.world.driving = {"occupied":true,"car":car}
	check(ATMOSPHERE.focus_position(controller)==summit,"Atmosphere follows occupied vehicle")
	controller.world.driving.occupied = false
	check(ATMOSPHERE.focus_position(controller)==harbor,"On foot atmosphere follows player")
	var atmosphere = ATMOSPHERE.new()
	atmosphere.apply(controller,.84,0,0,false,.2)
	check(sun.rotation_degrees.x<=-42,"Moon cannot create grazing-angle wedges")
	check(environment.environment.fog_enabled,"Exterior depth fog enabled")
	check(environment.environment.adjustment_enabled,"Exterior grade enabled")
	player.set_meta("mountain_shelter",true)
	atmosphere.apply(controller,.36,0,1,false,.2)
	check(not environment.environment.fog_enabled,"Authored shelter metadata suppresses mist")
	player.remove_meta("mountain_shelter")
	player.position = Vector3((4300.0+5200)/16,0,(-4960.0+400)/16)
	atmosphere.apply(controller,.36,0,1,false,.2)
	check(not environment.environment.fog_enabled,"Tunnel suppresses external mist")
	atmosphere.apply(controller,.36,0,1,true,.2)
	check(not environment.environment.fog_enabled and not environment.environment.adjustment_enabled,"Interiors suspend exterior effects")
	check(atmosphere.current.is_empty(),"Indoor restore clears previous biome smoothing")
	player.position = summit
	sun.light_color = Color.WHITE
	environment.environment.ambient_light_color = Color.WHITE
	atmosphere.apply(controller,.36,0,0,false,.2)
	check(is_equal_approx(atmosphere.current.saturation,snow.saturation),"Exit restores actual exterior profile")
	atmosphere.current.clear()
	sun.light_color = Color.WHITE
	atmosphere.apply(controller,.79,0,0,false,.2)
	var clear_warmth := sun.light_color.r/sun.light_color.b
	atmosphere.current.clear()
	sun.light_color = Color.WHITE
	atmosphere.apply(controller,.79,0,1,false,.2)
	check(sun.light_color.r/sun.light_color.b<clear_warmth,"Mountain front suppresses sunset even when Harbor is clear")
	player.queue_free()
	car.queue_free()
	sun.free()
	environment.free()
	print("REGIONAL_ATMOSPHERE ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
