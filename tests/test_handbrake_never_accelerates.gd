extends SceneTree
## Playtest 29/10: segurar Espaço (freio de mão) fazia o carro disparar. Mede, por
## carro e pelos dois controles (V1 de rua e motor próprio do deserto/rua), a
## velocidade no plano antes e durante o freio de mão, em reta e em curva, com e
## sem acelerador. A velocidade nunca pode subir num passo com o freio puxado.
## Contrato puro: sem Main.tscn, só o controle num corpo de teste.
##
## Relato seguinte (29/10): "em alguns carros, quando pressiona e faz curva, eles ganham
## velocidade". Segurar o freio os 3 s nunca mostrava ganho: o limite de entrada vale
## enquanto o botão está puxado. O ganho vinha depois de SOLTAR o Espaço ainda virando:
## handbrake_slide segura o lado mole por 0,7 s e o motor completo (DesertHandling)
## reconstruía a frente com a velocidade de antes do giro, somando o lado ao módulo
## (+2,3 m/s sem acelerador no sport_coupe a 20 m/s). Os casos "toque" e "pulso" medem
## isso na frota inteira, em asfalto e terra: sem acelerador nunca sobe; com acelerador
## nunca passa do mesmo carro fazendo a mesma curva sem freio de mão.
const STOCK = preload("res://gameplay/v1_handling/V1Handling.gd")
const POWERTRAIN = preload("res://gameplay/desert_cars/DesertHandling.gd")
const STREET = preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const DESERT = preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING = preload("res://gameplay/desert_cars/DesertTuning.gd")
const DT := 1.0 / 60.0
# Folga numérica: arredondamento de float, não ganho de verdade.
const EPS := 0.002
## Com acelerador, quanto o caso com freio pode ficar acima do mesmo carro sem freio
## (m/s): só ruído de passo; o ganho do relato era de 3 m/s.
const BASE_TOL := 0.05

class Car extends CharacterBody3D:
	var horizontal_velocity := Vector3.ZERO
	var speed := 0.0
	var effects = null
	func can_rotate(_yaw: float) -> bool: return true
	func burnout_strength() -> float: return 0.0

var failures := 0
var worst := {"gain": 0.0, "case": "", "over": 0.0, "over_case": ""}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var cases := []
	# Frota inteira no controle V1: quem tem ficha de motor próprio entra abaixo também.
	var fleet: Array = preload("res://runtime/FleetCatalog.gd").all().keys()
	fleet.sort()
	for id in fleet:
		if STREET.has(str(id)): continue
		cases.append({"id": str(id), "kind": "stock", "spec": preload("res://runtime/FleetCatalog.gd").spec(str(id))})
	for id in STREET.ids():
		cases.append({"id": id, "kind": "street_powertrain", "spec": STREET.spec(id)})
	for id in DESERT.IDS:
		cases.append({"id": id, "kind": "desert_powertrain", "spec": TUNING.tuned_spec(id, {})})
	var checked := 0
	for c in cases:
		if (c.spec as Dictionary).is_empty(): continue
		for turn in [0.0, 1.0, -1.0]:
			for throttle in [0.0, 1.0]:
				for start in [0.7, 0.2]:
					for wet in [0.0, 1.0]:
						_case(c, turn, throttle, start, wet)
						checked += 1
		# Freio tocado/pulsado no meio da curva, em asfalto e terra.
		for mode in ["toque", "pulso"]:
			for throttle in [0.0, 1.0]:
				for start in [0.7, 0.35]:
					for surface in ["asphalt", "dirt"]:
						_release_case(c, mode, throttle, start, surface)
						checked += 1
	await _scene_cases()
	print("HANDBRAKE_NEVER_ACCELERATES cases=%d worst_gain_mps=%.4f (%s) worst_over_unbraked_mps=%.4f (%s) failures=%d" % [checked, worst.gain, worst.case, worst.over, worst.over_case, failures])
	quit(1 if failures else 0)

func _case(c: Dictionary, turn: float, throttle: float, start: float, wet: float) -> void:
	var controller = (STOCK if c.kind == "stock" else POWERTRAIN).new()
	controller.configure(c.spec)
	var car := Car.new()
	root.add_child(car)
	# Embala em reta até a fração pedida do teto de rua (ou 20 s): rápido e devagar, onde o
	# motor tem mais força.
	var top := float(c.spec.get("max_speed", 600.0)) * 0.8 / STOCK.PX * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
	for frame in 60 * 20:
		controller.step(car, DT, 1.0, 0.0, false, 0.0)
		if car.horizontal_velocity.length() >= top * start: break
	var before := car.horizontal_velocity.length()
	var peak := before
	var label := "%s/%s turn=%.0f throttle=%.0f inicio=%.0f%% molhado=%.0f" % [c.kind, c.id, turn, throttle, start * 100.0, wet]
	var bad_frames := 0
	# Segura o freio de mão 3 s.
	for frame in 180:
		var prior := car.horizontal_velocity.length()
		controller.step(car, DT, throttle, turn, true, wet)
		var now := car.horizontal_velocity.length()
		peak = maxf(peak, now)
		if now - prior > worst.gain:
			worst.gain = now - prior
			worst.case = label
		if now > prior + EPS: bad_frames += 1
	var after := car.horizontal_velocity.length()
	var ok := bad_frames == 0 and peak <= before + EPS
	print(("CASE PASS " if ok else "CASE FAIL ") + "%s antes=%.2f m/s pico=%.2f depois=%.2f quadros_subindo=%d" % [label, before, peak, after, bad_frames])
	if not ok: failures += 1
	car.free()

static func _held(mode: String, frame: int) -> bool:
	# Quadros com o botão puxado; o resto dos 180 é a curva com ele solto.
	match mode:
		"segura": return true
		"toque": return frame < 15
		"pulso": return frame % 30 < 12
	return false

## Embala em reta e devolve controle + corpo prontos para a curva.
func _launched(c: Dictionary, start: float, surface: String) -> Array:
	var controller = (STOCK if c.kind == "stock" else POWERTRAIN).new()
	controller.configure(c.spec)
	var car := Car.new()
	root.add_child(car)
	car.set_meta("surface_kind", surface)
	var top := float(c.spec.get("max_speed", 600.0)) * 0.8 / STOCK.PX * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
	for frame in 60 * 20:
		controller.step(car, DT, 1.0, 0.0, false, 0.0)
		if car.horizontal_velocity.length() >= top * start: break
	return [controller, car]

## Curva cheia por 3 s com o freio só tocado (ou pulsado). Sem acelerador a velocidade no
## plano nunca sobe; com acelerador não passa da mesma curva sem freio de mão.
func _release_case(c: Dictionary, mode: String, throttle: float, start: float, surface: String) -> void:
	var base: Array = []
	if throttle > 0.0:
		var b: Array = _launched(c, start, surface)
		for frame in 180:
			b[0].step(b[1], DT, throttle, 1.0, false, 0.0)
			base.append(b[1].horizontal_velocity.length())
		b[1].free()
	var run: Array = _launched(c, start, surface)
	var controller = run[0]
	var car: Car = run[1]
	var before := car.horizontal_velocity.length()
	var prior := before
	var peak := before
	var bad_frames := 0
	var over := 0.0
	var label := "%s/%s %s throttle=%.0f inicio=%.0f%% %s" % [c.kind, c.id, mode, throttle, start * 100.0, surface]
	for frame in 180:
		controller.step(car, DT, throttle, 1.0, _held(mode, frame), 0.0)
		var now := car.horizontal_velocity.length()
		peak = maxf(peak, now)
		if throttle > 0.0:
			over = maxf(over, now - float(base[frame]))
		else:
			if now > prior + EPS: bad_frames += 1
			if now - prior > worst.gain:
				worst.gain = now - prior
				worst.case = label
		prior = now
	var ok := (bad_frames == 0 and peak <= before + EPS) if throttle == 0.0 else over <= BASE_TOL
	if throttle > 0.0 and over > worst.over:
		worst.over = over
		worst.over_case = label
	print(("CASE PASS " if ok else "CASE FAIL ") + "%s antes=%.2f m/s pico=%.2f depois=%.2f quadros_subindo=%d acima_sem_freio=%.2f" % [label, before, peak, prior, bad_frames, over])
	if not ok: failures += 1
	car.free()

## Mesmo contrato com o Vehicle de verdade numa pista plana (move_and_slide, entrada
## pelo GameInput e o freio de mão pela ação "handbrake", como o jogador aperta Espaço).
func _scene_cases() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	stage.add_child(ground)
	var street: Array = STREET.ids()
	for id in ["sport_coupe", "police_cruiser", str(street[0]), str(street[street.size() / 2])]:
		for turn in [0.0, 1.0]:
			for throttle in [0.0, 1.0]:
				for start in [22.0, 6.0]:
					await _scene_case(stage, id, turn, throttle, start, "segura")
		# Espaço tocado no começo da curva e solto ainda virando, sem pedal (o caso do relato).
		for start in [20.0, 10.0]:
			await _scene_case(stage, id, 1.0, 0.0, start, "toque")
	stage.queue_free()

func _scene_case(stage: Node3D, id: String, turn: float, throttle: float, start: float, mode: String) -> void:
	var input = root.get_node("/root/GameInput")
	var car: CharacterBody3D = preload("res://scripts/Vehicle.gd").new()
	car.archetype = id
	car.position = Vector3(0, 0.05, 0)
	stage.add_child(car)
	if STREET.has(id): preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car)
	car.controlled = true
	for i in 10: await physics_frame
	input.touch_move = Vector2(0, -1)
	for i in 60 * 12:
		await physics_frame
		if _planar(car) >= start: break
	var before := _planar(car)
	var peak := before
	var bad_frames := 0
	input.touch_move = Vector2(turn, -throttle)
	Input.action_press("handbrake")
	var prior := before
	for i in 180:
		if not _held(mode, i) and Input.is_action_pressed("handbrake"): Input.action_release("handbrake")
		await physics_frame
		var now := _planar(car)
		peak = maxf(peak, now)
		if now > prior + EPS: bad_frames += 1
		if now - prior > worst.gain:
			worst.gain = now - prior
			worst.case = "scene/%s %s turn=%.0f throttle=%.0f inicio=%.0f" % [id, mode, turn, throttle, start]
		prior = now
	Input.action_release("handbrake")
	input.touch_move = Vector2.ZERO
	var ok := bad_frames == 0 and peak <= before + EPS
	print(("CASE PASS " if ok else "CASE FAIL ") + "scene/%s %s turn=%.0f throttle=%.0f inicio=%.0f antes=%.2f m/s pico=%.2f depois=%.2f quadros_subindo=%d" % [id, mode, turn, throttle, start, before, peak, prior, bad_frames])
	if not ok: failures += 1
	car.queue_free()
	await physics_frame

static func _planar(car: CharacterBody3D) -> float:
	return Vector2(car.velocity.x, car.velocity.z).length()
