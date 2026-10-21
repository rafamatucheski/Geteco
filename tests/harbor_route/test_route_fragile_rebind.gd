extends SceneTree
## Poste preservado continua consultável e derrubado ao trocar o chunk e a mancha.
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const RECOVERY := preload("res://gameplay/street_physics/LampRecovery3D.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("test_route_fragile_rebind exige renderer real: Dummy não conserva transforms de MultiMesh")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var first := Node3D.new()
	var second := Node3D.new()
	root.add_child(first)
	root.add_child(second)
	var lamp := Node3D.new()
	lamp.name = "StreetLight_Reused"
	first.add_child(lamp)
	lamp.position = Vector3(8, 0, 5)
	var old_pool := _pool()
	FRAGILE.register_node("lamp", lamp, first, {"multimesh": old_pool, "index": 0})
	var initial := FRAGILE.query(lamp.global_position, 2.0)
	check(initial.size() == 1, "primeira montagem registra exatamente um poste")
	var item: Dictionary = initial[0]
	first.remove_child(lamp)
	second.add_child(lamp)
	first.free()
	check(FRAGILE.query(lamp.global_position, 2.0).is_empty(), "consulta remove vínculo com chunk descartado")
	var next_pool := _pool()
	FRAGILE.register_node("lamp", lamp, second, {"multimesh": next_pool, "index": 0})
	var rebound := FRAGILE.query(lamp.global_position, 2.0)
	check(rebound.size() == 1, "retorno reinsere o mesmo poste sem duplicar")
	check(rebound[0].chunk.get_ref() == second and rebound[0].pool.multimesh == next_pool, "luz e física apontam ao novo chunk")
	FRAGILE.register_node("lamp", lamp, second, {"multimesh": next_pool, "index": 0})
	check(FRAGILE.query(lamp.global_position, 2.0).size() == 1, "repetir registro não duplica entrada")
	RECOVERY.capture(item)
	item.state = "down"
	FRAGILE._kill_light(item)
	var director := Node.new()
	var third := Node3D.new()
	root.add_child(director)
	root.add_child(third)
	item.recovery_director = weakref(director)
	var deadline := Time.get_ticks_msec() + 20
	item.recovery_due_msec = deadline
	second.remove_child(lamp)
	third.add_child(lamp)
	second.free()
	var third_pool := _pool()
	FRAGILE.register_node("lamp", lamp, third, {"multimesh": third_pool, "index": 0})
	check(item.state == "down" and FRAGILE.query(lamp.global_position, 2.0).is_empty(), "trocar pool não ressuscita poste derrubado")
	check(is_zero_approx(third_pool.get_instance_transform(0).basis.determinant()), "mancha nova do poste derrubado continua apagada")
	check(not get_processed_tweens().is_empty() and item.recovery_due_msec == deadline, "retorno reassocia recuperação ao chunk atual sem reiniciar prazo")
	await create_timer(0.12).timeout
	check(item.state == "standing" and not is_zero_approx(third_pool.get_instance_transform(0).basis.determinant()), "timer de recuperação restaura raiz e mancha atuais")
	check(FRAGILE.query(lamp.global_position, 2.0).size() == 1, "poste recuperado continua consultável")
	third.free()
	director.free()
	FRAGILE.query(Vector3(8, 0, 5), 2.0)
	for failure in failures: print("FALHOU: ", failure)
	print("test_route_fragile_rebind checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _pool() -> MultiMesh:
	var pool := MultiMesh.new()
	pool.transform_format = MultiMesh.TRANSFORM_3D
	pool.mesh = QuadMesh.new()
	pool.instance_count = 1
	pool.set_instance_transform(0, Transform3D.IDENTITY)
	return pool

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
