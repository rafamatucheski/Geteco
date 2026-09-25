extends SceneTree

const MANAGER := preload("res://gameplay/emergency/EmergencyManager.gd")
const FIRE := preload("res://gameplay/emergency/Fire.gd")
const RESPONDER := preload("res://gameplay/emergency/Responder.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var manager := MANAGER.new()
	scene.add_child(manager)
	manager.set_physics_process(false)

	var fire := FIRE.new()
	fire.manager = manager
	fire.intensity = 0.001
	manager.add_child(fire)
	fire.set_physics_process(false)
	manager.incidents[1] = {"actor": fire, "role": "fire"}
	var responder := _responder(manager, 1)
	responder._physics_process(1.0 / 60.0)
	check(fire.is_queued_for_deletion(), "extinção do último foco libera o fogo")
	check(not responder.stream.visible, "jato some no quadro da extinção")
	check(responder.mode == "return" and responder.is_queued_for_deletion(), "bombeiro inicia retorno após extinção")

	var removed_fire := FIRE.new()
	removed_fire.manager = manager
	manager.add_child(removed_fire)
	removed_fire.set_physics_process(false)
	manager.incidents[2] = {"actor": removed_fire, "role": "fire"}
	var second_responder := _responder(manager, 2)
	removed_fire.free()
	second_responder._physics_process(1.0 / 60.0)
	check(not second_responder.stream.visible, "jato fica oculto para fogo já liberado")
	check(second_responder.mode == "return" and second_responder.is_queued_for_deletion(), "referência já liberada não interrompe o retorno")

	print("RESPONDER_FIRE_LIFECYCLE checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _responder(manager: Node3D, key: int) -> CharacterBody3D:
	var responder := RESPONDER.new()
	responder.manager = manager
	responder.role = "fire"
	responder.incident_id = key
	responder.mode = "service"
	manager.add_child(responder)
	responder.set_physics_process(false)
	return responder
