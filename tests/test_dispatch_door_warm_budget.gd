extends SceneTree
## Só orçamento de admissão e ciclo de vida do dispatch. Veículos espiões mantêm o teste
## independente do custo de malha: o orçamento de peça inteira do montador não é um prazo.
const CONTROLLER := preload("res://gameplay/dispatch/DispatchController.gd")
var checks := 0
var failures: Array[String] = []

class SpyWarmCar extends CharacterBody3D:
	var health := 100.0
	var warm_calls := 0
	var calls_until_ready := 2
	var requested_budgets: Array[int] = []
	func _ready() -> void: set_physics_process(false)
	func warm_doors(budget_usec: int) -> bool:
		warm_calls += 1
		requested_budgets.append(budget_usec)
		return warm_calls >= calls_until_ready

class FakeUnit extends RefCounted:
	var vehicle: CharacterBody3D
	var finished := false
	var wrecked := false
	var suspended := false
	var crew_remaining := 2
	var state := "enroute"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func next_render_frame() -> void:
	# process_frame é emitido antes de o contador avançar. O callback adiado
	# inicial pode compartilhar o valor com o primeiro sinal que esperamos.
	var previous := Engine.get_process_frames()
	while Engine.get_process_frames() == previous:
		await process_frame

func make_car(stage: Node3D, attached := true) -> SpyWarmCar:
	var car := SpyWarmCar.new()
	if attached: stage.add_child(car)
	return car

func make_unit(car: CharacterBody3D) -> FakeUnit:
	var unit := FakeUnit.new()
	unit.vehicle = car
	return unit

func catchup_calls(controller: Node3D) -> void:
	var process_frame_before := Engine.get_process_frames()
	var before: Array = controller.units.duplicate()
	var crew_counts: Array[int] = []
	for unit in before: crew_counts.append(unit.crew_remaining)
	for physics_step in 3: controller._warm_approaching_doors()
	check(Engine.get_process_frames() == process_frame_before, "catch-up calls really share one rendered-frame counter")
	check(controller.units == before, "warming preserves the unit list and its order")
	var crew_preserved := true
	for i in before.size(): crew_preserved = crew_preserved and before[i].crew_remaining == crew_counts[i]
	check(crew_preserved, "warming does not consume or replenish crew")

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var controller := CONTROLLER.new()
	controller.set_physics_process(false)
	stage.add_child(controller)
	var first := make_car(stage)
	var second := make_car(stage)
	controller.units.assign([make_unit(first),make_unit(second)])
	catchup_calls(controller)
	check(first.warm_calls == 1 and second.warm_calls == 0, "three physics catch-up calls admit only one vehicle in this rendered frame")
	await next_render_frame()
	catchup_calls(controller)
	check(first.warm_calls == 1 and second.warm_calls == 1, "next rendered frame gives the other vehicle its turn")
	await next_render_frame()
	catchup_calls(controller)
	check(first.warm_calls == 2 and second.warm_calls == 1, "unfinished jobs advance round robin instead of starving the first")
	await next_render_frame()
	catchup_calls(controller)
	check(first.warm_calls == 2 and second.warm_calls == 2, "the second unfinished job also reaches readiness")

	var third := make_car(stage)
	controller.units.append(make_unit(third))
	await next_render_frame()
	catchup_calls(controller)
	check(first.warm_calls == 2 and second.warm_calls == 2 and third.warm_calls == 1, "ready vehicles are skipped and a newly approaching crew advances")
	await next_render_frame()
	catchup_calls(controller)
	check(first.warm_calls == 2 and second.warm_calls == 2 and third.warm_calls == 2, "completed jobs remain skipped on subsequent frames")
	check(first.requested_budgets == [1000,1000] and second.requested_budgets == [1000,1000] and third.requested_budgets == [1000,1000], "each admitted call receives the provisional 1 ms work budget")

	# Todo caso inválido continua pertencendo a esta fixture; só o carro válido final
	# pode aquecer. Inspeciona os carros na fila antes de ceder, enquanto os objetos existem.
	var invalid_cars: Array[SpyWarmCar] = []
	var invalid_units: Array[FakeUnit] = []
	for index in 7:
		var car := make_car(stage, index != 6)
		invalid_cars.append(car)
		invalid_units.append(make_unit(car))
	invalid_units[0].suspended = true
	invalid_units[1].finished = true
	invalid_units[2].wrecked = true
	invalid_units[3].crew_remaining = 0
	invalid_units[4].state = "working"
	invalid_cars[5].health = 0.0
	var queued := make_car(stage)
	var queued_unit := make_unit(queued)
	var eligible := make_car(stage)
	var eligible_unit := make_unit(eligible)
	eligible_unit.state = "parked"
	controller.units.assign(invalid_units)
	controller.units.append(queued_unit)
	controller.units.append(make_unit(null))
	controller.units.append(eligible_unit)
	await next_render_frame()
	queued.queue_free()
	catchup_calls(controller)
	var all_invalid_skipped := queued.warm_calls == 0
	for car in invalid_cars: all_invalid_skipped = all_invalid_skipped and car.warm_calls == 0
	check(all_invalid_skipped and eligible.warm_calls == 1, "suspended, finished, wrecked, empty crew, inactive, dead, detached, queued and missing cars are skipped")
	check(eligible_unit.state == "parked" and eligible_unit.crew_remaining == 2, "warming a parked approaching crew does not alter deployment state")
	# Limpa a referência na fila antes de o motor apagar esse carro de fixture.
	controller.units.clear()
	queued_unit.vehicle = null
	invalid_cars[6].free()
	await next_render_frame()

	# Equipes suspensas não recebem trabalho. Retomar dentro do mesmo quadro não dá
	# uma segunda admissão; elas ficam elegíveis no quadro renderizado seguinte.
	var resumed := make_car(stage)
	var resumed_unit := make_unit(resumed)
	resumed_unit.suspended = true
	controller.units.assign([resumed_unit])
	catchup_calls(controller)
	check(resumed.warm_calls == 0, "an entirely suspended queue performs no door work")
	resumed_unit.suspended = false
	catchup_calls(controller)
	check(resumed.warm_calls == 0, "same-frame resume does not reset the shared budget")
	await next_render_frame()
	catchup_calls(controller)
	check(resumed.warm_calls == 1, "resumed crew advances on the next rendered frame")
	await next_render_frame()
	catchup_calls(controller)
	check(resumed.warm_calls == 2, "resumed preparation reaches readiness without blocking crew state")
	resumed_unit.suspended = true
	await next_render_frame()
	catchup_calls(controller)
	resumed_unit.suspended = false
	await next_render_frame()
	catchup_calls(controller)
	check(resumed.warm_calls == 2, "readiness survives suspension and resume without rebuilding doors")

	# A remoção real pode deixar uma referência obsoleta de veículo até o próximo tick
	# de ciclo de vida da unidade. O aquecimento roda antes desse tick e precisa ignorá-la com segurança.
	var removed := make_car(stage)
	var removed_unit := make_unit(removed)
	controller.units.clear()
	var removal_controller := CONTROLLER.new()
	removal_controller.set_physics_process(false)
	stage.add_child(removal_controller)
	var after_removal := make_car(stage)
	removal_controller.units.assign([removed_unit,make_unit(after_removal)])
	removed.free()
	await next_render_frame()
	catchup_calls(removal_controller)
	check(removal_controller.units.size() == 2 and removal_controller.units[0] == removed_unit and after_removal.warm_calls == 1, "freed vehicle is ignored and does not prevent the next live unit from warming")
	removal_controller.units.clear()
	removed_unit.vehicle = null
	stage.free()
	print("DISPATCH_DOOR_WARM_BUDGET ",JSON.stringify({"checks":checks,"failures":failures,"scope":"One vehicle per rendered frame and lifecycle contract, no mesh cost or FPS certification."}))
	quit(0 if failures.is_empty() else 1)
