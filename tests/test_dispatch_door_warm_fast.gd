extends SceneTree
## P9 (otimização 13/10): quem recebe o preparo antecipado da porta com
## GETECO_DISPATCH_FAST ligado (padrão) e desligado (=0). Usa DispatchUnit de verdade e carros
## dublês (sem custo de malha): mede só QUEM é preparado e quantas chamadas, nunca tempo.
## Ligado: só a polícia, e em rota só quando pode parar logo. Desligado: todos, como antes.
## Rodar: godot --headless --path . --script res://tests/test_dispatch_door_warm_fast.gd -- --no-save
##        GETECO_DISPATCH_FAST=0 godot ... (mesmo script; as expectativas seguem o modo)
const CONTROLLER := preload("res://gameplay/dispatch/DispatchController.gd")
const UNIT := preload("res://gameplay/dispatch/DispatchUnit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
var checks := 0
var failures: Array[String] = []

class SpyWarmCar extends CharacterBody3D:
	var health := 100.0
	var warm_calls := 0
	func _ready() -> void: set_physics_process(false)
	func warm_doors(_budget_usec: int) -> bool:
		warm_calls += 1
		# Nunca fica pronta: o rodízio continua passando por todos os elegíveis.
		return false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func next_render_frame() -> void:
	var previous := Engine.get_process_frames()
	while Engine.get_process_frames() == previous:
		await process_frame

func make_unit(stage: Node3D, service: String, state: String, near := false) -> RefCounted:
	var unit := UNIT.new()
	unit.service = service
	unit.state = state
	unit._door_warm_near = near
	var car := SpyWarmCar.new()
	stage.add_child(car)
	unit.vehicle = car
	return unit

func rules_table() -> void:
	var stop := RULES.stop_radius(0)
	check(RULES.door_warm_near(stop + 60.0, stop, true, 0.0, true), "stop already planned always warms")
	check(not RULES.door_warm_near(stop + RULES.DOOR_WARM_LEAD + 1.0, stop, false, 0.0, false), "far from the anchor does not warm, even with the target on foot")
	check(RULES.door_warm_near(stop + RULES.DOOR_WARM_LEAD - 1.0, stop, false, 0.0, false), "target on foot within the lead warms")
	check(not RULES.door_warm_near(stop + 5.0, stop, true, 12.0, false), "target fleeing by car does not warm: police only pursues")
	check(RULES.door_warm_near(stop + 5.0, stop, true, RULES.DOOR_WARM_TARGET_SPEED - 0.5, false), "slow target car within the lead warms before it stops")

func run() -> void:
	var fast_env := OS.get_environment("GETECO_DISPATCH_FAST") != "0"
	check(CONTROLLER.fast == fast_env, "switch follows GETECO_DISPATCH_FAST")
	rules_table()
	var stage := Node3D.new()
	root.add_child(stage)
	var controller := CONTROLLER.new()
	controller.set_physics_process(false)
	stage.add_child(controller)
	var medic := make_unit(stage, "medic", "enroute")
	var fire := make_unit(stage, "fire", "parked")
	var mortician := make_unit(stage, "mortician", "enroute")
	var police_far := make_unit(stage, "police", "enroute", false)
	var police_near := make_unit(stage, "police", "enroute", true)
	var police_parked := make_unit(stage, "police", "parked")
	var all := [medic, fire, mortician, police_far, police_near, police_parked]
	controller.units.assign(all)
	var states_before: Array = all.map(func(u): return [u.state, u.crew_remaining])
	var frames := 12
	for index in frames:
		await next_render_frame()
		controller._warm_approaching_doors()
	var calls: Dictionary = {}
	for unit in all: calls["%s:%s:%s" % [unit.service, unit.state, unit._door_warm_near]] = unit.vehicle.warm_calls
	var total := 0
	for unit in all: total += unit.vehicle.warm_calls
	check(total == frames, "still exactly one door job per rendered frame")
	check(all.map(func(u): return [u.state, u.crew_remaining]) == states_before, "warming never changes unit state or crew")
	if fast_env:
		check(medic.vehicle.warm_calls == 0 and fire.vehicle.warm_calls == 0 and mortician.vehicle.warm_calls == 0, "services never prepare doors they do not use")
		check(police_far.vehicle.warm_calls == 0, "police en route that cannot stop soon waits")
		check(police_near.vehicle.warm_calls == int(frames / 2.0) and police_parked.vehicle.warm_calls == int(frames / 2.0), "eligible police alternate round robin")
		# Quando a viatura passa a poder parar, entra no rodízio no quadro seguinte.
		police_far._door_warm_near = true
		await next_render_frame()
		controller._warm_approaching_doors()
		await next_render_frame()
		controller._warm_approaching_doors()
		await next_render_frame()
		controller._warm_approaching_doors()
		check(police_far.vehicle.warm_calls >= 1, "police that may stop soon becomes eligible")
	else:
		for unit in all: check(unit.vehicle.warm_calls == int(float(frames) / all.size()), "legacy mode warms every unit round robin (%s)" % unit.service)
	print("DISPATCH_DOOR_WARM_FAST ", JSON.stringify({"fast": fast_env, "checks": checks, "failures": failures, "calls": calls,
		"scope": "Eligibility and call counts only; no mesh cost, frame time or police behavior certification."}))
	controller.units.clear()
	for unit in all: unit.vehicle = null
	stage.free()
	quit(0 if failures.is_empty() else 1)
