extends SceneTree
## P9 (otimização 13/10): quanto custa preparar a porta de UM veículo de despacho, do jeito que
## DispatchController._warm_approaching_doors faz (uma chamada por quadro, orçamento de 1 ms),
## e quanto custaria fazer tudo de uma vez (o fallback `finish_now` do desembarque).
## Mede chamadas e microssegundos de cada chamada (span). NÃO mede fps nem tempo de quadro.
## Em --headless os µs são indicativos (driver de renderização dummy); as contagens valem.
## Uso: godot --headless --path . --script res://tests/measure/probe_dispatch_door_warm.gd -- --no-save
const VEHICLE := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const CONTROLLER := preload("res://gameplay/dispatch/DispatchController.gd")
const ARCHETYPES := ["police_cruiser", "police_transport", "medic_box", "rescue_pumper", "station_wagon"]
## Mesma ordem de grandeza do laço real; acima disto o preparo é dado como travado.
const MAX_CALLS := 2000

var stage: Node3D

func _initialize() -> void: run.call_deferred()

func spawn(id: String) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	stage.add_child(car)
	car.set_physics_process(false)
	car.global_position = Vector3(0, .04, 0)
	return car

func warm_like_dispatch(car: CharacterBody3D) -> Dictionary:
	var spans: Array[int] = []
	var ready := false
	while not ready and spans.size() < MAX_CALLS:
		var began := Time.get_ticks_usec()
		ready = car.warm_doors(CONTROLLER.DOOR_WARM_BUDGET_USEC)
		spans.append(Time.get_ticks_usec() - began)
		await process_frame
	var total := 0
	var largest := 0
	var over_budget := 0
	for span in spans:
		total += span
		largest = maxi(largest, span)
		if span > CONTROLLER.DOOR_WARM_BUDGET_USEC: over_budget += 1
	var sorted := spans.duplicate()
	sorted.sort()
	return {"ready": ready, "calls": spans.size(), "total_ms": snappedf(total / 1000.0, .001),
		"max_ms": snappedf(largest / 1000.0, .001), "median_ms": snappedf(sorted[sorted.size() / 2] / 1000.0, .001),
		"calls_over_budget": over_budget, "last_call_ms": snappedf(spans[-1] / 1000.0, .001)}

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	await process_frame
	var report := {"budget_usec": CONTROLLER.DOOR_WARM_BUDGET_USEC, "headless": DisplayServer.get_name() == "headless", "archetypes": {}}
	for id in ARCHETYPES:
		var row := {}
		# Dois carros iguais seguidos: o segundo mostra se algo do primeiro é reaproveitado.
		for index in 2:
			var car := spawn(id)
			await process_frame
			row["incremental_%d" % index] = await warm_like_dispatch(car)
			car.queue_free()
			await process_frame
		var quick := spawn(id)
		await process_frame
		var began := Time.get_ticks_usec()
		quick.finish_doors()
		row["finish_now_ms"] = snappedf((Time.get_ticks_usec() - began) / 1000.0, .001)
		row["boarding_class"] = quick.boarding_class()
		quick.queue_free()
		await process_frame
		report.archetypes[id] = row
	print("DISPATCH_DOOR_WARM_PROBE ", JSON.stringify(report))
	stage.free()
	quit(0)
