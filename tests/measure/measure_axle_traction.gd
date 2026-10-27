extends SceneTree
## A/B da tração por eixo (gameplay/desert_cars/AxleTraction.gd) no mesmo processo: o
## interruptor é trocado em tempo de execução, sem mexer em arquivo. Para cada carro com
## motor completo mede a arrancada até 85% do teto de rua no asfalto e na terra, e uma
## curva com acelerador cheio a partir de 12 m/s (quanto o carro gira e escorrega de lado).
## Matemática da dirigibilidade; --headless é válido (não mede FPS).
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const DESERT := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const SPORT := preload("res://runtime/SportFleet.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const AXLE := preload("res://gameplay/desert_cars/AxleTraction.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DT := 1.0/60.0
const OUT := "res://evidence/axle-traction-20261027/axle-ab.json"

func _initialize() -> void: _run.call_deferred()

func _car(id: String, surface: String) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "axle_"+id
	root.add_child(car)
	car.set_physics_process(false)
	car.set_meta("surface_kind",surface)
	return car

func _launch(id: String, surface: String) -> float:
	var car := _car(id,surface)
	var target := float(car.max_forward_speed)*.85
	var t := 0.0
	var reach := INF
	while t < 30.0 and reach == INF:
		car.handling.step(car,DT,1.0,0.0,false,0.0)
		t += DT
		if float(car.speed) >= target: reach = t
	car.free()
	return reach

func _corner(id: String) -> Dictionary:
	var car := _car(id,"asphalt")
	var t := 0.0
	while float(car.speed) < 12.0 and t < 20.0:
		car.handling.step(car,DT,1.0,0.0,false,0.0)
		t += DT
	var yaw0 := car.rotation.y
	var slip := 0.0
	var steps := int(1.2/DT)
	for i in steps:
		car.handling.step(car,DT,1.0,1.0,false,0.0)
		slip += float(car.handling.lateral_speed)/16.0
	var result := {"yaw_deg":rad_to_deg(absf(wrapf(car.rotation.y-yaw0,-PI,PI))), "slip_mps":slip/steps, "exit_mps":float(car.speed)}
	car.free()
	return result

func _run() -> void:
	var ids: Array = []
	for id in STREET.ids() + DESERT.IDS:
		if id not in ids: ids.append(id)
	var rows := {}
	var by_drive := {}
	for id: String in ids:
		var drive := str(FLEET.spec(id).get("drivetrain","rwd"))
		var row := {"drivetrain":drive}
		for m in [0,1]:
			AXLE.mode = m
			row["launch_%d" % m] = _launch(id,"asphalt")
			row["dirt_%d" % m] = _launch(id,"dirt")
			row["corner_%d" % m] = _corner(id)
		AXLE.mode = 1
		row["launch_ratio"] = float(row.launch_1)/maxf(float(row.launch_0),.001)
		row["dirt_ratio"] = float(row.dirt_1)/maxf(float(row.dirt_0),.001)
		row["yaw_delta_deg"] = float(row.corner_1.yaw_deg)-float(row.corner_0.yaw_deg)
		row["slip_delta_mps"] = float(row.corner_1.slip_mps)-float(row.corner_0.slip_mps)
		rows[id] = row
		if not by_drive.has(drive): by_drive[drive] = []
		by_drive[drive].append(id)
		print("AXLE %-20s %-4s largada %.2fs→%.2fs (×%.2f) terra %.2fs→%.2fs (×%.2f) curva giro %+.1f° escorrega %+.2f m/s%s" % [id,drive,row.launch_0,row.launch_1,row.launch_ratio,row.dirt_0,row.dirt_1,row.dirt_ratio,row.yaw_delta_deg,row.slip_delta_mps," (esportivo 2.0)" if id in SPORT.IDS else ""])
	var summary := {}
	for drive: String in by_drive:
		var n := float(by_drive[drive].size())
		var acc := {"cars":int(n),"launch_ratio":0.0,"dirt_ratio":0.0,"yaw_delta_deg":0.0,"slip_delta_mps":0.0}
		for id: String in by_drive[drive]:
			for key in ["launch_ratio","dirt_ratio","yaw_delta_deg","slip_delta_mps"]: acc[key] += float(rows[id][key])/n
		summary[drive] = acc
		print("AXLE_SUMMARY %-4s carros=%d largada ×%.2f terra ×%.2f giro %+.1f° escorrega %+.2f m/s" % [drive,acc.cars,acc.launch_ratio,acc.dirt_ratio,acc.yaw_delta_deg,acc.slip_delta_mps])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"summary":summary},"\t"))
	quit(0)
