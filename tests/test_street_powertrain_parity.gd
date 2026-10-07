extends SceneTree
## Os carros migrados para o motor completo têm que rodar como antes fora das provas:
## mesma velocidade final e mesmo tempo de arrancada (Vehicle.gd: aceleração constante
## até o teto), trocando marcha sozinhos, com o som original e sem afetar os demais.
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DT := 1.0/60.0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	for id in STREET.ids():
		var legacy: Dictionary = FLEET.all()[id]
		var a := clampf(float(legacy.acceleration)/160.0,2.0,10.0)
		var cap := clampf(float(legacy.max_speed)/16.0,5.0,45.0)
		var v_ref := minf(100.0/3.6,cap*.85)
		var car := VEHICLE.new()
		car.archetype = id
		car.vehicle_id = "parity_"+id
		root.add_child(car)
		car.set_physics_process(false)
		_check(car.handling.get("drive") != null,"Motor completo não foi ligado em "+id)
		_check(car.get_node_or_null("DesertCarAudio") == null,"O som original foi trocado em "+id)
		_check(is_equal_approx(car.max_forward_speed,cap),"Velocidade final mudou em %s: %.2f vs %.2f" % [id,car.max_forward_speed,cap])
		var drive = car.handling.drive
		var t := 0.0
		var reach := INF
		var top := 0.0
		var gears := {}
		while t < 60.0:
			car.handling.step(car,DT,1.0,0.0,false,0.0)
			t += DT
			top = maxf(top,float(car.speed))
			gears[drive.gear] = true
			if reach == INF and float(car.speed) >= v_ref: reach = t
		var target := v_ref/a
		_check(reach != INF and absf(reach-target) <= target*.08,"Arrancada fora de 8%% em %s: %.2fs vs %.2fs" % [id,reach,target])
		_check(top <= cap+.001 and top >= cap*.97,"Final de rua fora do esperado em %s: %.1f vs %.1f m/s" % [id,top,cap])
		_check(gears.size() >= 3,"Troca automática insuficiente em "+id)
		print("PARITY ",id," arrancada=%.2fs (antigo %.2fs) final=%.0f km/h (antigo %.0f) marchas=%d" % [reach,target,top*3.6,cap*3.6,gears.size()])
		car.free()
	for other in ["police_cruiser","route_city","bike_urban","medic_box"]:
		var car := VEHICLE.new()
		car.archetype = other
		car.vehicle_id = "other_"+other
		root.add_child(car)
		car.set_physics_process(false)
		_check(car.handling.get("drive") == null,"Veículo de serviço foi migrado sem querer: "+other)
		car.free()
	await process_frame
	print("STREET_POWERTRAIN_PARITY ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
