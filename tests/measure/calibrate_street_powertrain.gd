extends SceneTree
## Acha o torque que faz o motor completo reproduzir a aceleração antiga de cada carro
## (Vehicle.gd: aceleração constante até o teto) e imprime o resultado para comparar
## com o valor gravado em StreetPowertrainCatalog. Matemática pura; --headless é válido.
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const STEP := 1.0/60.0

func _initialize() -> void: run.call_deferred()

func _sim(id: String, torque: float, target_speed: float) -> Dictionary:
	var d = DRIVE.new()
	d.configure(id,{})
	d.spec.torque_nm = torque
	d.stage(5.0,.5)
	d.launch()
	var cap := float(d.spec.street_cap_mps)
	var t := 0.0
	var reach := INF
	var quarter := INF
	while t < 90.0:
		# Mesmo limitador de rua de DesertHandling.
		d.step(STEP,clampf((cap-d.speed_mps)/(cap*.08),0.0,1.0),false)
		d.speed_mps = minf(d.speed_mps,cap)
		if d.rpm >= d.ideal_shift_rpm and d.gear < d.spec.gears.size(): d.shift_up()
		t += STEP
		if reach == INF and d.speed_mps >= target_speed: reach = t
		if quarter == INF and d.distance_m >= 400.0: quarter = t
	return {"reach":reach,"quarter":quarter,"top":d.speed_mps}

func run() -> void:
	for id in STREET.ids():
		var spec := STREET.spec(id)
		var a := clampf(float(spec.acceleration)/160.0,2.0,10.0)
		var cap := float(spec.street_cap_mps)
		var v_ref := minf(100.0/3.6,cap*.85)
		var target := v_ref/a
		var lo := 20.0
		var hi := 4000.0
		for i in 30:
			var mid := (lo+hi)*.5
			if float(_sim(id,mid,v_ref).reach) > target: lo = mid
			else: hi = mid
		var best := (lo+hi)*.5
		var cal := _sim(id,best,v_ref)
		var stored := _sim(id,float(spec.torque_nm),v_ref)
		var quarter_legacy := sqrt(2.0*400.0/a) if cap*cap/(2.0*a) >= 400.0 else cap/a+(400.0-cap*cap/(2.0*a))/cap
		print("%-15s v_ref=%.1f m/s alvo=%.2fs | torque calibrado=%.0f Nm (gravado %.0f -> %.2fs) | 400m: motor %.2fs vs antigo %.2fs | final %.0f vs %.0f km/h" % [
			id,v_ref,target,best,float(spec.torque_nm),float(stored.reach),float(cal.quarter),quarter_legacy,float(cal.top)*3.6,cap*3.6])
	quit(0)
