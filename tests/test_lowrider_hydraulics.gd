extends SceneTree
## Hidráulica do lowrider (gameplay/lowrider/LowriderHydraulics.gd), só matemática de apresentação:
## a carroceria sobe pelo canto pedido, as rodas ficam no chão até o fim do curso, o pulo cheio
## tira as rodas do chão, o motorista acompanha, o "show" termina e tudo volta à pose assada.
## O carro fica com processamento desligado; a hidráulica é avançada à mão em passos de 1/60 s.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func advance(lift: Node, seconds: float) -> void:
	for i in int(seconds / STEP): lift._physics_process(STEP)

func body_y(car: Node3D, local: Vector3) -> float:
	return (car.visual.transform * local).y

func wheel_positions(car: Node3D) -> Array:
	var result := []
	for pivot: Node3D in car.wheels: result.append(car.visual.transform * pivot.position)
	return result

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var plain := VEHICLE.new()
	plain.archetype = "potro_68"
	stage.add_child(plain)
	plain.process_mode = Node.PROCESS_MODE_DISABLED
	check(plain.hydraulics == null, "muscle car não tem hidráulica")
	plain.free()
	var car := VEHICLE.new()
	car.archetype = "imperador_64"
	stage.add_child(car)
	car.process_mode = Node.PROCESS_MODE_DISABLED
	var lift: Node = car.hydraulics
	check(lift != null, "lowrider tem hidráulica")
	if lift == null:
		finish()
		return
	var rest_visual: Transform3D = car.visual.transform
	var rest_wheels := wheel_positions(car)
	var rest_seat: Vector3 = car.driver_seat_anchor()
	var nose := Vector3(0, .5, -2.4)
	var tail := Vector3(0, .5, 2.4)
	var nose_rest := body_y(car, nose)
	var tail_rest := body_y(car, tail)
	check(not lift.captures_input(), "sem motorista não captura a direção")
	lift._physics_process(STEP)
	check(not lift.active(), "parado na altura assada fica em repouso")

	# Frente para cima: o nariz sobe, a traseira quase não, e as rodas não saem do lugar.
	lift.set_corners(1, 1, 0, 0)
	advance(lift, 1.5)
	check(body_y(car, nose) - nose_rest > .25, "frente sobe (%.3f m)" % (body_y(car, nose) - nose_rest))
	check(body_y(car, tail) - tail_rest < .08, "traseira fica embaixo (%.3f m)" % (body_y(car, tail) - tail_rest))
	var wheels := wheel_positions(car)
	var drift := 0.0
	for i in wheels.size(): drift = maxf(drift, (wheels[i] - rest_wheels[i]).length())
	check(drift < .01, "rodas no chão com a frente levantada (desvio %.4f m)" % drift)
	check(car.driver_seat_anchor().y > rest_seat.y + .05, "motorista sobe com a carroceria")
	for pivot: Node3D in car.wheels:
		var up: Vector3 = (car.visual.transform.basis * pivot.basis) * Vector3.UP
		check(up.angle_to(Vector3.UP) < .02 or absf(up.x) < .02, "roda continua de pé (sem rolagem)")
		break

	# Lado esquerdo para cima.
	lift.set_corners(1, 0, 1, 0)
	advance(lift, 1.5)
	check(body_y(car, Vector3(-.9, .5, 0)) > body_y(car, Vector3(.9, .5, 0)) + .2, "esquerda acima da direita")

	# Solta tudo e dá o pulo cheio: no alto, as rodas saem do chão.
	lift.set_corners(0, 0, 0, 0)
	advance(lift, 2.0)
	check(lift.hop(1.0), "pulo aceito no chão")
	check(not lift.hop(1.0), "segundo pulo no ar recusado")
	var peak := 0.0
	var wheel_peak := 0.0
	for i in 90:
		lift._physics_process(STEP)
		peak = maxf(peak, lift.hop_y)
		for j in car.wheels.size(): wheel_peak = maxf(wheel_peak, (car.visual.transform * car.wheels[j].position).y - rest_wheels[j].y)
	check(absf(peak - lift.HOP_HEIGHT) < .06, "altura do pulo cheio (%.3f m)" % peak)
	check(wheel_peak > .3, "rodas saem do chão no alto do pulo (%.3f m)" % wheel_peak)
	check(absf(lift.best_hop - peak) < .001, "melhor pulo registrado")

	# Pulo do jogador encadeado: apertar logo depois de aterrissar sobe mais.
	advance(lift, 3.0)
	lift.reset_best_hop()
	check(lift.player_hop(), "pulo do jogador")
	var first_chain: int = lift.hop_chain
	var landed := false
	for i in 180:
		lift._physics_process(STEP)
		if lift.hop_y <= 0.0 and lift.hop_v <= 0.0 and i > 5:
			landed = true
			break
	var first_best: float = lift.best_hop
	check(landed and lift.player_hop(), "segundo pulo logo depois de cair")
	check(lift.hop_chain == first_chain + 1, "pulo no tempo encadeia (%d → %d)" % [first_chain, lift.hop_chain])
	advance(lift, 1.5)
	check(lift.best_hop > first_best + .05, "pulo encadeado sobe mais (%.2f → %.2f)" % [first_best, lift.best_hop])

	# Show com fim: dois ciclos e para sozinho.
	advance(lift, 3.0)
	lift.play("side", 2)
	check(lift.playing() == "side", "padrão começou")
	advance(lift, 6.0)
	check(lift.playing() == "", "padrão terminou depois dos ciclos")
	advance(lift, 3.0)
	check(not lift.active(), "voltou ao repouso")
	check(car.visual.transform.is_equal_approx(rest_visual), "carroceria na pose assada")
	wheels = wheel_positions(car)
	drift = 0.0
	for i in wheels.size(): drift = maxf(drift, (wheels[i] - rest_wheels[i]).length())
	check(drift < .001, "rodas na pose assada")
	check(car.driver_seat_anchor().is_equal_approx(rest_seat), "banco do motorista no lugar")
	car.free()
	finish()
	stage.free()

func finish() -> void:
	print("LOWRIDER_HYDRAULICS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
