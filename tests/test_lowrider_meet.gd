extends SceneTree
## Encontro de lowriders (gameplay/lowrider/LowriderMeet.gd): horário da noite, vagas no acostamento
## norte sem invadir a pista, a calçada nem o pátio da Torque (encontro de clássicos), convidados na
## calçada e a pose de balanço sem acumular rotação entre quadros.
const MEET = preload("res://gameplay/lowrider/LowriderMeet.gd")
const FLEET = preload("res://runtime/MuscleFleet.gd")
const TORQUE = preload("res://world/places/classic_meet/ClassicMeetSite.gd")
const DANCER = preload("res://gameplay/lowrider/LowriderDancerModel.gd")
## Acostamento norte da rua de acesso: entre a calçada (z 99,9) e a borda da pista (z 103,6).
const SHOULDER := Vector2(99.9, 103.62)
const POST := Vector3(430.6, 0, 102.2)
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	for hour in [18.0, 21.5, 0.0, 2.9]: check(MEET.is_event_time(hour / 24.0), "noite: %.1f h" % hour)
	for hour in [3.0, 9.0, 12.0, 17.9]: check(not MEET.is_event_time(hour / 24.0), "dia: %.1f h" % hour)
	check(MEET.night_of(5, 1.0 / 24.0) == 4 and MEET.night_of(5, 20.0 / 24.0) == 5, "madrugada conta como a noite anterior")
	var torque := Rect2(TORQUE.LOT.position - Vector2(.5, .5), TORQUE.LOT.size + Vector2(1, 1))
	var boxes: Array[Rect2] = []
	var music := 0
	for spot: Dictionary in MEET.CAR_SPOTS:
		var model := str(spot.model)
		check(FLEET.is_lowrider(model), model + ": vaga do encontro é de lowrider")
		var size: Array = FLEET.spec(model).bounds_size
		var p: Vector3 = spot.position
		# Virado para +X: comprimento em X, largura em Z.
		var box := Rect2(p.x - float(size[2]) * .5, p.z - float(size[0]) * .5, float(size[2]), float(size[0]))
		check(box.position.y >= SHOULDER.x and box.end.y <= SHOULDER.y, model + ": cabe no acostamento (z %.2f–%.2f)" % [box.position.y, box.end.y])
		check(not box.intersects(torque), model + ": fora do pátio da Torque")
		check(not box.grow(.4).has_point(Vector2(POST.x, POST.z)), model + ": longe do poste")
		for other in boxes: check(not box.grow(.3).intersects(other), model + ": não encosta no vizinho")
		boxes.append(box)
		if bool(spot.get("music", false)): music += 1
	check(music == 1, "um carro com o som")
	check(MEET.CAR_SPOTS.any(func(s): return str(s.show) == "hop"), "um carro de pulo")
	check(MEET.CAR_SPOTS.any(func(s): return bool(s.get("day", false))), "algum carro fica de dia")
	var dancers := 0
	for spot: Dictionary in MEET.GUEST_SPOTS:
		var p: Vector3 = spot.position
		check(p.z < SHOULDER.x and p.z > 96.0, "convidado na calçada (z %.2f)" % p.z)
		for box in boxes: check(not box.grow(.5).has_point(Vector2(p.x, p.z)), "convidado fora dos carros")
		if bool(spot.get("dancer", false)): dancers += 1
	check(dancers >= 2, "gente dançando perto do som")
	for path: String in MEET.TRACKS: check(ResourceLoader.exists(path), "faixa existe: " + path)

	# A pose de balanço reescreve o tronco a partir da pose do quadro: mesma hora, mesma pose.
	var model := DANCER.new()
	root.add_child(model)
	model.process_mode = Node.PROCESS_MODE_DISABLED
	model.activity = "groove"
	for i in 30:
		model.clock = 1.0 + i * .016
		model._pose(.016)
	model.clock = 2.5
	model._pose(.016)
	var first: Basis = model.spine.transform.basis
	model.clock = 2.5
	model._pose(.016)
	# A cabeça fica de fora: o CivilianModel suaviza o olhar ao redor entre chamadas.
	check(model.spine.transform.basis.is_equal_approx(first), "tronco não acumula rotação")
	model.clock = 2.5 + 60.0 / DANCER.BPM * .25
	model._pose(.016)
	check(not model.spine.transform.basis.is_equal_approx(first), "tronco marca o tempo")
	model.free()
	print("LOWRIDER_MEET ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
