extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ",label)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	for id in ["union_sedan","sedan_classic","metro_hatch"]:
		var a := VEHICLE.new(); a.archetype = id; a.paint_color = Color("e6e4df"); world.add_child(a); a.set_physics_process(false)
		check(a._paint.roof_materials.size()==1,id+": roof separated")
		check(a._paint.roof_materials[0].albedo_color.is_equal_approx(Color("171b20")),id+": white with black roof")
		var saved := FLEET_STATE.capture(a,"harbor")
		check(FLEET_STATE.validate(saved),id+": valid fleet save")
		var b := VEHICLE.new(); b.archetype = id; b.paint_color = Color.html(saved.paint); world.add_child(b); b.set_physics_process(false)
		check(b._paint.roof_materials[0].albedo_color==a._paint.roof_materials[0].albedo_color,id+": roof restored from saved body color")
		a.paint_color = Color("171b20")
		check(a._paint.roof_materials[0].albedo_color.is_equal_approx(Color("dedcd5")),id+": black with ivory roof")
		check(b._paint.roof_materials[0].albedo_color.is_equal_approx(Color("171b20")),id+": paint does not leak between cars")
		a.paint_color = Color("92979c")
		check(a._paint.roof_materials[0].albedo_color.is_equal_approx(Color("171b20")),id+": gray with black roof")
		a.paint_color = Color("722e30")
		check(a._paint.roof_materials[0].albedo_color.is_equal_approx(a.paint_color),id+": colored paint does not invent a contrasting roof")
		a.receive_damage(a.max_health*.4)
		check(a._paint.roof_materials[0].detail_enabled,id+": roof receives normal wear")
		a.free(); b.free()
	var cabs: Array = []
	for index in 2:
		var car := VEHICLE.new(); car.archetype = "taxi_yellow"; car.vehicle_id = "taxi_rank_"+str(index)
		world.add_child(car); car.set_physics_process(false); cabs.append(car)
	var a = cabs[0].visual.get_node("TaxiLivery")
	var b = cabs[1].visual.get_node("TaxiLivery")
	check(a.plates[0].text!=b.plates[0].text,"taxi registrations differ")
	a.set_available(false)
	check(a.sign_material.emission_energy_multiplier==0 and b.sign_material.emission_energy_multiplier>0,"sign state isolated between taxis")
	var old: String = a.plates[0].text
	cabs[0].vehicle_id = "restored_cab"
	check(a.plates[0].text!=old and a.plates[0].text==a.plates[1].text,"plate follows persistent identity front and rear")
	check(cabs[0]._paint.roof_materials.is_empty(),"taxi retains its authored yellow livery")
	world.free()
	print("VEHICLE_TWOTONE ",checks," checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
