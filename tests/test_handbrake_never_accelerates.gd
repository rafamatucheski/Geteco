extends SceneTree
## Playtest 29/10: segurar Espaço (freio de mão) fazia o carro disparar. Mede, por
## carro e pelos dois controles (V1 de rua e motor próprio do deserto/rua), a
## velocidade no plano antes e durante o freio de mão, em reta e em curva, com e
## sem acelerador. A velocidade nunca pode subir num passo com o freio puxado.
## Contrato puro: sem Main.tscn, só o controle num corpo de teste.
const STOCK = preload("res://gameplay/v1_handling/V1Handling.gd")
const POWERTRAIN = preload("res://gameplay/desert_cars/DesertHandling.gd")
const STREET = preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const DESERT = preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING = preload("res://gameplay/desert_cars/DesertTuning.gd")
const DT := 1.0 / 60.0
# Folga numérica: arredondamento de float, não ganho de verdade.
const EPS := 0.002

class Car extends CharacterBody3D:
	var horizontal_velocity := Vector3.ZERO
	var speed := 0.0
	var effects = null
	func can_rotate(_yaw: float) -> bool: return true
	func burnout_strength() -> float: return 0.0

var failures := 0
var worst := {"gain": 0.0, "case": ""}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var cases := []
	for id in ["sport_coupe", "police_cruiser", "porto_rosso", "american_dump_truck", "police_van"]:
		cases.append({"id": id, "kind": "stock", "spec": preload("res://runtime/FleetCatalog.gd").spec(id)})
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
	await _scene_cases()
	print("HANDBRAKE_NEVER_ACCELERATES cases=%d worst_gain_mps=%.4f (%s) failures=%d" % [checked, worst.gain, worst.case, failures])
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
					await _scene_case(stage, id, turn, throttle, start)
	stage.queue_free()

func _scene_case(stage: Node3D, id: String, turn: float, throttle: float, start: float) -> void:
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
		await physics_frame
		var now := _planar(car)
		peak = maxf(peak, now)
		if now > prior + EPS: bad_frames += 1
		if now - prior > worst.gain:
			worst.gain = now - prior
			worst.case = "scene/%s turn=%.0f throttle=%.0f inicio=%.0f" % [id, turn, throttle, start]
		prior = now
	Input.action_release("handbrake")
	input.touch_move = Vector2.ZERO
	var ok := bad_frames == 0 and peak <= before + EPS
	print(("CASE PASS " if ok else "CASE FAIL ") + "scene/%s turn=%.0f throttle=%.0f inicio=%.0f antes=%.2f m/s pico=%.2f depois=%.2f quadros_subindo=%d" % [id, turn, throttle, start, before, peak, prior, bad_frames])
	if not ok: failures += 1
	car.queue_free()
	await physics_frame

static func _planar(car: CharacterBody3D) -> float:
	return Vector2(car.velocity.x, car.velocity.z).length()
