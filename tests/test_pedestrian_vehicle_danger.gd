extends SceneTree
const DIRECTOR := preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd")
const DANGER := preload("res://gameplay/civilian_reactions/PedestrianVehicleDanger.gd")
class Population extends Node3D:
	var people: Array = []
class Witness extends CharacterBody3D:
	var health := 100.0
	var dead := false
	var is_player := false
	var controlled_automatically := false
	var automatic_direction := Vector3.ZERO
	var speed := 1.6
class Vehicle extends CharacterBody3D:
	var half_width := 1.0
	var half_length := 2.3
class Presentation extends Node:
	func scream(_actor) -> bool: return true
	func hide_prop(_actor) -> void: pass
	func clear_actor(_id) -> void: pass
	func clear_all() -> void: pass
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PEDESTRIAN_DANGER ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var world := Population.new()
	root.add_child(world)
	var car := Vehicle.new()
	world.add_child(car)
	car.velocity = Vector3.FORWARD * 10
	check(not DANGER.assess(car, Vector3(0, 0, -15)).is_empty(), "carro se aproxima")
	check(DANGER.assess(car, Vector3(5, 0, -15)).is_empty(), "pista vizinha")
	check(DANGER.assess(car, Vector3(0, 0, 10)).is_empty(), "carro já passou")
	car.velocity = Vector3.BACK * 8
	check(not DANGER.assess(car, Vector3(0, 0, 10)).is_empty(), "ré segue velocidade, não frente do modelo")
	car.velocity = Vector3.RIGHT * 10
	check(not DANGER.assess(car, Vector3(15, 0, 0)).is_empty(), "derrapagem lateral considera casco projetado")
	car.velocity = Vector3.ZERO
	check(DANGER.assess(car, Vector3(0, 0, -2)).is_empty(), "estacionado não provoca fuga")
	car.velocity = Vector3.FORWARD * 0.5
	check(not DANGER.assess(car, Vector3(0, 0, -7), Vector3.BACK * 3.5).is_empty(), "retomada de encontro à manobra lenta reage antecipadamente")
	car.velocity = Vector3.FORWARD * 8
	check(not DANGER.assess(car, Vector3(4, 0, -12), Vector3.LEFT * 2).is_empty(), "pedestre que entra na trajetória é previsto")
	var director := DIRECTOR.new()
	world.add_child(director)
	director.set_physics_process(false)
	director.world = world
	var presenter := Presentation.new()
	director.add_child(presenter)
	director.presenter = presenter
	for i in 40:
		var witness := Witness.new()
		witness.set_meta("gameplay_role", "civilian")
		world.add_child(witness)
		witness.position = Vector3(i % 8, 0, i / 8)
		world.people.append(witness)
	director.report_gunfire(Vector3(-2, 0, 0), Vector3(-2, 0, -30))
	check(director.reactors.size() == 40, "40 pedestres reagem, sem corte em 24")
	var witness: Witness = world.people[0]
	var state: Dictionary = director.reactors[witness.get_instance_id()]
	for phase in ["call", "armed", "melee", "horn", "recover"]:
		state.phase = phase
		state.replan = 1.5
		state.target = Vector3(2, 0, 0)
		director.report_gunfire(Vector3(-2, 0, 0), Vector3(-2, 0, -30))
		check(state.phase == "panic" and state.replan == 0.0 and state.target == Vector3.ZERO, "tiro interrompe " + phase)
	witness.set_meta("street_down", true)
	check(not director._reactive(witness, true), "caído não recebe ordem de correr")
	witness.remove_meta("street_down")
	witness.set_meta("invulnerable", true)
	check(not director._reactive(witness, true), "proteção explícita respeitada")
	director.reset_population()
	check(not witness.controlled_automatically and is_equal_approx(witness.speed, 1.6), "limpeza devolve controle e velocidade")
	world.free()
	print("PEDESTRIAN_DANGER checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
