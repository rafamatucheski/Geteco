extends "res://tests/dispatch/test_dispatch_integrated_pursuit.gd"
## P9 (otimização 13/10): o mesmo cenário de tests/dispatch/test_dispatch_integrated_pursuit.gd
## (perseguição a pé no mapa real, desembarque, encerramento), contando o preparo de porta:
## chamadas e ms de span de `dispatch.doors.prewarm` (preparo antecipado) e de
## `vehicle.doors.prepare` (preparo na hora, quando a equipe desce antes de a porta ficar
## pronta), e quantos desembarques policiais encontraram a porta já pronta.
## Rodar com e sem GETECO_DISPATCH_FAST=0. Só contagens e spans; NÃO mede fps nem quadro.
## godot --headless --path . --script res://tests/measure/probe_dispatch_door_warm_pursuit.gd -- --no-save --skip-arrival --population=24 --seed=20260921
const STALL := preload("res://runtime/StallWorkTrace.gd")
const DISPATCH := preload("res://gameplay/dispatch/DispatchController.gd")
var deploys := {"door_ready": 0, "door_not_ready": 0}
var _hooked: Node = null

func _initialize() -> void:
	STALL.start_aggregate()
	super._initialize()

func _process(_delta: float) -> bool:
	var world_node := root.get_node_or_null("World3D")
	if world_node == null or _hooked == world_node: return false
	var controller: Variant = world_node.get("dispatch")
	if controller == null: return false
	controller.dispatch_event.connect(_on_dispatch_event)
	_hooked = world_node
	return false

func _on_dispatch_event(event_name: String, data: Dictionary) -> void:
	if event_name != "unit_state" or data.get("state") != "working": return
	var unit: Variant = data.get("unit")
	if unit == null or not unit.is_police() or not is_instance_valid(unit.vehicle): return
	deploys["door_ready" if unit.vehicle.get_meta("dispatch_doors_warmed", false) else "door_not_ready"] += 1

func _finalize() -> void:
	var labels: Dictionary = STALL.stop_aggregate().labels
	var rows := {}
	for label in ["dispatch.doors.prewarm", "vehicle.doors.prepare"]:
		var row: Dictionary = labels.get(label, {"calls": 0, "total_usec": 0, "max_usec": 0})
		rows[label] = {"calls": row.calls, "total_ms": snappedf(row.total_usec / 1000.0, .001), "max_ms": snappedf(row.max_usec / 1000.0, .001)}
	print("DISPATCH_DOOR_WARM_PURSUIT ", JSON.stringify({"fast": DISPATCH.fast, "spans": rows, "police_deploys": deploys,
		"headless": DisplayServer.get_name() == "headless",
		"scope": "Counts and span ms of door preparation in one on-foot pursuit; ms indicative in headless; no fps/frame time."}))
