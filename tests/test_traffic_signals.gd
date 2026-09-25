extends SceneTree
## Fases do semáforo e regra de entrada no cruzamento (TrafficJunctions), sem mundo.

const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	# Cruz em (0,0): braços leste, oeste, norte, sul.
	var graph := {
		"vertices": [Vector3.ZERO, Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, 30), Vector3(0, 0, -30)],
		"edges": {0: [{"to": 1}, {"to": 2}, {"to": 3}, {"to": 4}]},
	}
	JUNCTIONS.configure(graph)
	var key := JUNCTIONS.key_of(Vector3.ZERO)
	check(JUNCTIONS.junctions.has(key), "cruzamento de 4 braços reconhecido")
	check(JUNCTIONS.signal_state(key, Vector3.RIGHT) == "stop", "sem poste registrado vale PARE")

	# PARE: só entra parado na faixa; carro do eixo cruzado dentro segura a entrada.
	var a := Node.new()
	var b := Node.new()
	check(not JUNCTIONS.request(key, a.get_instance_id(), Vector3.RIGHT, 8.0, 5.0), "PARE: longe e andando não entra")
	check(JUNCTIONS.request(key, a.get_instance_id(), Vector3.RIGHT, 1.0, 0.2), "PARE: parado na faixa entra")
	check(not JUNCTIONS.request(key, b.get_instance_id(), Vector3.BACK, 1.0, 0.2), "PARE: eixo cruzado espera o miolo")
	JUNCTIONS.release(key, a.get_instance_id())
	check(JUNCTIONS.request(key, b.get_instance_id(), Vector3.BACK, 1.0, 0.2), "PARE: miolo livre, eixo cruzado entra")
	JUNCTIONS.release(key, b.get_instance_id())

	# Semáforo: os dois eixos nunca ficam verdes juntos e cada um recebe verde no ciclo.
	JUNCTIONS.register_signal(Vector3(0.4, 0, -0.3), 8.0)
	check(JUNCTIONS.is_signalized(key), "poste perto do vértice sinaliza o cruzamento")
	check(is_equal_approx(JUNCTIONS.stop_line(key), 8.0), "faixa de parada vem do poste")
	var both_green := false
	var a_green := false
	var b_green := false
	var t := 0.0
	while t < JUNCTIONS.CYCLE:
		var sa: String = JUNCTIONS._state_at(Vector3.ZERO, true, t)
		var sb: String = JUNCTIONS._state_at(Vector3.ZERO, false, t)
		if sa != "red" and sb != "red": both_green = true
		a_green = a_green or sa == "green"
		b_green = b_green or sb == "green"
		t += .1
	check(not both_green, "eixos cruzados nunca abertos ao mesmo tempo")
	check(a_green and b_green, "cada eixo recebe verde no ciclo")

	# Pedido de entrada segue o estado atual da aproximação.
	var east: String = JUNCTIONS.signal_state(key, Vector3.RIGHT)
	var north: String = JUNCTIONS.signal_state(key, Vector3.BACK)
	check(east != north or east == "red", "leste e norte em fases diferentes")
	var c := Node.new()
	var heading := Vector3.RIGHT if east == "red" else Vector3.BACK
	if JUNCTIONS.signal_state(key, heading) == "red":
		check(not JUNCTIONS.request(key, c.get_instance_id(), heading, 5.0, 6.0), "vermelho segura antes da faixa")
		check(JUNCTIONS.request(key, c.get_instance_id(), heading, -2.0, 6.0), "quem já passou da faixa não para no meio")
	# Carros no mesmo sentido entram juntos (antes era um por vez).
	var green_heading := Vector3.ZERO
	for candidate in [Vector3.RIGHT, Vector3.BACK]:
		if JUNCTIONS.signal_state(key, candidate) == "green": green_heading = candidate
	if green_heading != Vector3.ZERO:
		JUNCTIONS.owners.clear()
		var d := Node.new()
		var e := Node.new()
		check(JUNCTIONS.request(key, d.get_instance_id(), green_heading, 3.0, 5.0) and JUNCTIONS.request(key, e.get_instance_id(), -green_heading, 3.0, 5.0), "verde admite vários carros do mesmo eixo")
		d.free()
		e.free()
	for node in [a, b, c]: node.free()
	print("TRAFFIC_SIGNALS ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
