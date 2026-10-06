extends SceneTree
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)

func _run() -> void:
	var families := {}
	for id in CARS.ids():
		var result := _race(str(id),{},.91,false)
		_check(float(result.time) >= 12.0 and float(result.time) <= 30.0,"500 m duration outside useful drag range: %s %s" % [id,result])
		families[str(CARS.spec(str(id)).engine_family)] = true
		var table := []
		for length in [500.0,650.0,800.0]:
			table.append({"metres":length,"stock":_race(str(id),{},.91,false,length),"prepared":_race(str(id),{"engine":"race_cam","turbo":"turbo_large","nitro":"nitro_race","tires":"drag_tires","weight":"lightweight"},.91,true,length)})
		print("DESERT_CAR_TIMING ",id," ",JSON.stringify(table))
	_check(families.size() == 5,"Roster must have distinct acoustic source families")
	var good := _race("desert_faisca",{},.91,false)
	var early := _race("desert_faisca",{},.57,false)
	_check(float(good.time)+.4 < float(early.time),"Early shifts must lose meaningful time")
	var boosted := _race("desert_faisca",{"nitro":"nitro_street"},.91,true)
	_check(float(boosted.time) < float(good.time)-.25,"Installed nitro must improve elapsed time")
	_check(float(boosted.nitro) <= .001,"Nitro reserve should be consumed, never refilled by shifts")
	var stock := TUNING.tuned_spec("desert_faisca")
	var short_box := TUNING.tuned_spec("desert_faisca",{"gearbox":"gear_short"})
	_check(float(short_box.max_speed) < float(stock.max_speed) and float(short_box.final_drive) > float(stock.final_drive),"Short ratio must sacrifice final speed")
	var light := TUNING.tuned_spec("desert_coyote",{"weight":"lightweight"})
	_check(float(light.mass) < float(CARS.spec("desert_coyote").mass) and float(light.durability) < float(CARS.spec("desert_coyote").durability),"Weight removal must reduce impact resistance")
	var d := DRIVE.new()
	d.configure("desert_faisca")
	d.rpm = d.redline*.52
	d.launch()
	for i in 1500: d.step(1.0/120.0,1.0,false)
	_check(d.gear == 1 and d.speed_mps < 23.0,"No manual shift must stay limited in first gear")
	var before := d.speed_mps
	d.shift_up()
	_check(is_equal_approx(d.speed_mps,before),"Shifting must not award artificial velocity")
	var locked := TUNING.purchase_check({},[],"race_cam",0,100000)
	_check(not bool(locked.ok),"Money cannot bypass race unlock")
	var poor := TUNING.purchase_check({},[],"street_cam",1,10)
	_check(not bool(poor.ok),"Insufficient balance cannot purchase")
	var bought := TUNING.purchase_check({},[],"street_cam",1,1800)
	_check(bool(bought.ok) and int(bought.cost)==1800,"Valid purchase should charge listed price")
	var reinstall := TUNING.purchase_check({},bought.owned,"street_cam",1,0)
	_check(bool(reinstall.ok) and int(reinstall.cost)==0,"Owned part reinstall must not charge again")
	var dirty := TUNING.clean_parts({"nitro":"race_cam","engine":"street_cam","bad":"garbage"})
	_check(dirty == {"engine":"street_cam"},"Invalid or mismatched save slots must be rejected")
	print("DESERT_CARS_RESULTS good=",good," early=",early," nitro=",boosted)
	print("DESERT_CARS_", "PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _race(id: String, parts: Dictionary, shift_ratio: float, use_nitro: bool, length := 500.0) -> Dictionary:
	var d := DRIVE.new()
	d.configure(id,parts)
	d.rpm = d.redline*.52
	d.launch()
	var elapsed := 0.0
	while d.distance_m < length and elapsed < 60.0:
		if d.rpm >= d.redline*shift_ratio: d.shift_up()
		d.step(1.0/120.0,1.0,use_nitro)
		elapsed += 1.0/120.0
	return {"time":elapsed,"speed":d.speed_mps,"nitro":d.nitro,"gear":d.gear}
