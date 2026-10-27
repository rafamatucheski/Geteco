extends SceneTree
## Acha o torque que faz o motor completo reproduzir a aceleração antiga de cada carro
## (Vehicle.gd: aceleração constante até o teto) e imprime o resultado para comparar
## com o valor gravado em StreetPowertrainCatalog. Matemática pura; --headless é válido.
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const STEP := 1.0/60.0
const AXLE := preload("res://gameplay/desert_cars/AxleTraction.gd")
## Tração por eixo: quanto a largada pode piorar em relação à aderência inteira antiga.
## Acima disso o pneu ganha `axle_grip`; a diferença entre trações continua, só não aleija.
const AXLE_BANDS := {"awd":1.02, "4x4":1.05, "rwd":1.10, "fwd":1.15}

func _initialize() -> void: run.call_deferred()

func _sim(id: String, torque: float, target_speed: float, full := true) -> Dictionary:
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
		if not full and reach != INF: break
	return {"reach":reach,"quarter":quarter,"top":d.speed_mps}

func _reach_with_axle(id: String, mode: int, grip: float, v_ref: float) -> float:
	AXLE.mode = mode
	var d = DRIVE.new()
	d.configure(id,{})
	d.spec["axle_grip"] = grip
	d.stage(5.0,.5)
	d.launch()
	var cap := float(d.spec.street_cap_mps)
	var t := 0.0
	while t < 60.0:
		d.step(STEP,clampf((cap-d.speed_mps)/(cap*.08),0.0,1.0),false)
		d.speed_mps = minf(d.speed_mps,cap)
		if d.rpm >= d.ideal_shift_rpm and d.gear < d.spec.gears.size(): d.shift_up()
		t += STEP
		if d.speed_mps >= v_ref: return t
	return INF

## Menor `axle_grip` que deixa a largada dentro da faixa da tração (passo de 0,01).
func _calibrate_axle(id: String, spec: Dictionary, v_ref: float) -> void:
	var drive := str(spec.get("drivetrain","rwd"))
	var base := _reach_with_axle(id,0,1.0,v_ref)
	var now := _reach_with_axle(id,1,1.0,v_ref)
	var band := float(AXLE_BANDS.get(drive,1.10))
	var grip := 1.0
	while now > base*band and grip < 2.0:
		grip += .01
		now = _reach_with_axle(id,1,grip,v_ref)
	AXLE.mode = 1
	print("AXLE_CAL %s %s %.2f (largada %.2fs → %.2fs, faixa ×%.2f)" % [id,drive,grip,base,now,band])

func run() -> void:
	if "--axle" in OS.get_cmdline_user_args():
		for id in STREET.ids():
			var spec := STREET.spec(id)
			spec.erase("axle_grip")
			_calibrate_axle(id,spec,minf(100.0/3.6,float(spec.street_cap_mps)*.85))
		quit(0)
		return
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
			if float(_sim(id,mid,v_ref,false).reach) > target: lo = mid
			else: hi = mid
		var best := (lo+hi)*.5
		var cal := _sim(id,best,v_ref)
		var stored := _sim(id,float(spec.torque_nm),v_ref)
		var quarter_legacy := sqrt(2.0*400.0/a) if cap*cap/(2.0*a) >= 400.0 else cap/a+(400.0-cap*cap/(2.0*a))/cap
		print("CAL %s %.0f" % [id,best])
		if best <= 21.0 or best >= 3990.0: print("AVISO ",id," torque no limite da busca; ficha inviável")
		print("%-15s v_ref=%.1f m/s alvo=%.2fs | torque calibrado=%.0f Nm (gravado %.0f -> %.2fs) | 400m: motor %.2fs vs antigo %.2fs | final %.0f vs %.0f km/h" % [
			id,v_ref,target,best,float(spec.torque_nm),float(stored.reach),float(cal.quarter),quarter_legacy,float(cal.top)*3.6,cap*3.6])
	quit(0)
