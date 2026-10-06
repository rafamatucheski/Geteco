extends SceneTree
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	for id in CATALOG.ids():
		var car := VEHICLE.new()
		car.archetype = str(id)
		car.vehicle_id = "test_"+str(id)
		root.add_child(car)
		car.set_physics_process(false)
		_check(car.wheels.size()==4,"Every new model needs four animated wheel pivots: "+str(id))
		_check(car._paint.materials.size()>0,"Every model needs ordinary fleet painting: "+str(id))
		var before := car.max_health
		_check(ADAPTER.attach(car,{"weight":"lightweight","engine":"street_cam"}),"New car must accept Digo preparation")
		_check(car.max_health < before and car.health <= car.max_health,"Weight saving must preserve valid damage state")
		_check(car.get_meta("desert_parts").get("engine")=="street_cam","Installed part metadata must remain available to save/drag")
		var drive: Variant = car.get_meta("desert_powertrain")
		_check(drive == car.handling.drive,"Free driving and audio must share actual gearbox")
		_check(car.get_node("DesertCarAudio").drivetrain==drive,"Mixer must consume the driving gearbox")
		_check(car.get_node("DesertCarAudio")._bank.size()==7,"Distinct engine family must load its seven real source bands")
		var tuned_health := car.max_health
		ADAPTER.attach(car,{"weight":"lightweight","engine":"street_cam"})
		_check(is_equal_approx(car.max_health,tuned_health),"Restoring a tune must not compound durability reduction")
		_check(car.find_children("DesertCarAudio","",false,false).size()==1,"Repeated restore must not stack engine mixers")
		if str(id)=="desert_faisca": _check_native_audio_sync(car)
		car.free()
	var legacy := VEHICLE.new()
	legacy.archetype = "sport_coupe"
	legacy.vehicle_id = "persistent_legacy_car"
	root.add_child(legacy)
	legacy.set_physics_process(false)
	legacy.health = legacy.max_health*.5
	var old_id := legacy.vehicle_id
	var old_model := legacy.visual
	var old_max := legacy.max_health
	ADAPTER.attach(legacy,{"weight":"lightweight"})
	_check(legacy.vehicle_id==old_id and legacy.visual==old_model and legacy.archetype=="sport_coupe","Legacy preparation must preserve identity, geometry and archetype")
	_check(legacy.max_health<=old_max and is_equal_approx(legacy.health/legacy.max_health,.5),"Legacy tuning preserves condition and fleet durability limits")
	_check(CATALOG.parts_for_vehicle(legacy)=={"weight":"lightweight"},"Legacy car exposes same race/save parts contract")
	legacy.free()
	var panel := PANEL.new()
	root.add_child(panel)
	panel.show_vehicle("desert_faisca",{},[],0,10000)
	_check(panel.visible,"Digo workshop panel opens with authoritative state")
	panel.close_panel()
	_check(not panel.visible,"Digo workshop closes cleanly")
	panel.free()
	await process_frame
	print("DESERT_CARS_FLEET_", "PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_native_audio_sync(car: CharacterBody3D) -> void:
	var sound: Node = car.get_node("DesertCarAudio")
	var drive: RefCounted = car.handling.drive
	car.traffic=true
	car.controlled=false
	car.speed=9.0
	var distance_before: float=drive.distance_m
	drive.nitro=.37
	sound._synchronize_external(.1)
	_check(drive.rpm>1500.0 and is_equal_approx(drive.speed_mps,9.0),"Native traffic motion raises engine RPM above idle")
	_check(is_equal_approx(car.speed,9.0) and is_equal_approx(drive.distance_m,distance_before) and is_equal_approx(drive.nitro,.37),"Traffic audio observation cannot propel car, advance race or refill nitro")
	car.traffic=false
	car.controlled=true
	drive.rpm=1234.0
	drive.gear=3
	sound._synchronize_external(.1)
	_check(is_equal_approx(drive.rpm,1234.0) and drive.gear==3,"Audio observer preserves player simulation")
	car.traffic=true
	car.set_meta("desert_drag_physics",true)
	sound._synchronize_external(.1)
	_check(is_equal_approx(drive.rpm,1234.0) and drive.gear==3,"Audio observer preserves manual drag gearbox even on a reused traffic body")
	car.remove_meta("desert_drag_physics")
	car.traffic=false
	car.external_input=true
	car.throttle_input=.6
	car.speed=25.0
	sound._synchronize_external(.1)
	_check(drive.rpm>1500.0 and drive.gear>1 and is_equal_approx(car.speed,25.0),"External driver audio follows actual speed and gearbox ratios")
