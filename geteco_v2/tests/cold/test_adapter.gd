extends SceneTree
const COLD = preload("res://runtime/ColdSurvival.gd")
const HEAT = preload("res://runtime/cold/OriginalHeatSources.gd")
var errors: Array[String] = []
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: errors.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_cold",true)
	root.add_child(world)
	for i in 900:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.session.weather!=null: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if not errors.is_empty(): quit(1); return
	var cold = COLD.new()
	cold.configure(world.session)
	world.add_child(cold)
	cold.set_process(false)
	cold.model.temperature = 40
	cold._process(1)
	check(cold.model.temperature==40,"Harbor controller paused")
	check(world.production.travel("mountain"),"travel mountain")
	var camp := HEAT.to_world(Vector2(5655,-990))
	world.production.region.set_focus(camp)
	for i in 10: await physics_frame
	world.player.teleport(camp+Vector3(1,.08,0))
	cold._process(1)
	check(cold.context.heat and cold.context.heat_id=="smuggler_camp","physical original camp context")
	check(cold.model.temperature==75,"camp warms35/s")
	world.session.state.place_id = "mountain_cabin"
	cold._process(1)
	check(cold.context.sheltered and cold.model.temperature==90,"interior warms15/s, not camp35")
	world.session.state.place_id = ""
	world.player.teleport(HEAT.to_world(Vector2(8000,-2000))+Vector3.UP*.08)
	cold.model.temperature = 0
	cold.model.exposure = 60
	world.gameplay.armor = 100
	var before_health: float = world.gameplay.health
	var before_crime: int = world.gameplay.crime_points
	cold._process(1)
	check(world.gameplay.health==before_health-5,"environment health loses5")
	check(world.gameplay.armor==100 and world.gameplay.crime_points==before_crime,"cold ignores armor and crime")
	check(cold.status().key=="hypothermia" and cold.status().visible,"functional status")
	var snapshot: Dictionary = cold.snapshot()
	check(cold.restore(JSON.parse_string(JSON.stringify(snapshot))),"adapter JSON save restores")
	check(cold.snapshot()==snapshot,"adapter snapshot exact")
	world.gameplay.health = 0
	cold._process(1)
	check(cold.snapshot()==snapshot,"dead player does not tick")
	world.gameplay.health = 100
	world.session.state.region_id = "harbor"
	cold._process(1)
	check(cold.snapshot()==snapshot and not cold.status().visible,"region exit pauses and hides status")
	world.session.state.region_id = "mountain"
	world.session.state.place_id = "maciota"
	cold.model.temperature = 0
	cold._process(1)
	check(world.gameplay.health==100 and cold.model.temperature==15,"safe interior heats, no damage")
	cold.model.temperature = 0
	cold.model.exposure = 100
	cold.model.damage_fraction = .5
	var weather_clock: float = cold.model.weather_clock
	cold.recover_after_rescue()
	check(cold.model.temperature==100 and cold.model.exposure==0 and cold.model.damage_fraction==0,"rescue avoids repeated cold death")
	check(cold.model.weather_clock==weather_clock,"rescue preserves weather clock")
	check(cold.presentation.find_children("*","Light3D",true,false).is_empty(),"heat presentation has no added lights")
	world.queue_free()
	await create_timer(.15).timeout
	print("COLD_ADAPTER checks=",checks," failures=",errors)
	quit(0 if errors.is_empty() else 1)
