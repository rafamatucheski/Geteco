extends SceneTree
## Fogo com caminhão chamado não apaga sozinho antes de a equipe chegar; sem chamado,
## continua sumindo em BURN_SECONDS + FADE_SECONDS (fogo solto de arma ou explosão).

const FIRE := preload("res://gameplay/emergency/Fire.gd")

var failures: Array[String] = []

class FakeManager extends Node3D:
	var incidents: Dictionary = {}

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _burn(manager: Node3D, key: int, assigned: bool, seconds: float) -> Node3D:
	var fire: Node3D = FIRE.new()
	fire.manager = manager
	fire.incident_key = key
	manager.add_child(fire)
	manager.incidents[key] = {"actor": fire, "role": "fire", "assigned": assigned}
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < seconds and is_instance_valid(fire) and not fire.is_queued_for_deletion():
		fire._physics_process(step)
		elapsed += step
	return fire

func _initialize() -> void:
	# Dentro de _initialize o primeiro nó adicionado ainda não recebe _ready (sonda de 27/10).
	run.call_deferred()

func run() -> void:
	var manager := FakeManager.new()
	root.add_child(manager)
	var total := FIRE.BURN_SECONDS + FIRE.FADE_SECONDS + 1.0
	var loose := _burn(manager, 1, false, total)
	_check(not is_instance_valid(loose) or loose.is_queued_for_deletion(), "fogo sem chamado apaga em %.0f s" % total)
	var awaited := _burn(manager, 2, true, total)
	_check(is_instance_valid(awaited) and not awaited.is_queued_for_deletion() and awaited.intensity > 0.9, "fogo com caminhão chamado segue aceso aos %.0f s" % total)
	if is_instance_valid(awaited):
		manager.incidents[2].assigned = false
		var step := 1.0 / 60.0
		for i in int((FIRE.FADE_SECONDS + 1.0) / step):
			if awaited.is_queued_for_deletion(): break
			awaited._physics_process(step)
		_check(awaited.is_queued_for_deletion(), "fogo volta a apagar quando o caminhão desiste")
	var capped := _burn(manager, 3, true, FIRE.RESPONSE_HOLD_SECONDS + FIRE.FADE_SECONDS + 1.0)
	_check(not is_instance_valid(capped) or capped.is_queued_for_deletion(), "teto de espera de %.0f s" % FIRE.RESPONSE_HOLD_SECONDS)
	print("FIRE_WAITS_FOR_CREW failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
