extends SceneTree
## Fora das provas o motor completo não pode passar do teto de rua; a arrancada
## usa motor próprio e continua livre. Troca de marcha na rua é automática.
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	for id in CATALOG.ids():
		var car := VEHICLE.new()
		car.archetype = str(id)
		car.vehicle_id = "cap_"+str(id)
		root.add_child(car)
		car.set_physics_process(false)
		ADAPTER.attach(car,{"engine":"race_cam","turbo":"turbo_large","nitro":"nitro_race"})
		var drive = car.handling.drive
		var cap := float(drive.spec.street_cap_mps)
		var top := 0.0
		var gears := {}
		for i in 60*60:
			car.handling.step(car,1.0/60.0,1.0,0.0,false,0.0)
			top = maxf(top,float(car.speed))
			gears[drive.gear] = true
		_check(top <= cap+.001,"Teto de rua violado em %s: %.1f m/s > %.1f" % [id,top,cap])
		_check(top >= cap*.9,"Teto de rua não foi alcançado por %s (%.1f de %.1f m/s); teste não prova nada" % [id,top,cap])
		_check(car.max_forward_speed <= cap+.001,"max_forward_speed acima do teto em "+str(id))
		_check(gears.size() >= 3,"Troca automática não passou por marchas suficientes em "+str(id))
		print("STREET_CAP ",id," top_kmh=%.0f cap_kmh=%.0f gears=%d" % [top*3.6,cap*3.6,gears.size()])
		car.free()
	# A arrancada instancia o próprio motor: deve passar do teto de rua.
	var race = DRIVE.new()
	race.configure("desert_mirage",{})
	race.stage(5.0,.5)
	race.launch()
	for i in 60*60:
		race.step(1.0/60.0,1.0,false)
		if race.rpm >= race.ideal_shift_rpm and race.gear < race.spec.gears.size(): race.shift_up()
	_check(race.speed_mps > float(race.spec.street_cap_mps)+5.0,"A arrancada não pode herdar o teto de rua (%.1f m/s)" % race.speed_mps)
	await process_frame
	print("STREET_SPEED_CAP ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
