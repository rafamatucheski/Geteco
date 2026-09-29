extends SceneTree

## Observe an unforced loading cycle in Main, with three physical road vehicles.
var world
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 500:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false,"Main V2 starts")
		quit(1)
		return
	var session = world.session
	check(world.production.no_save,"Loading observation does not touch personal save")
	session.weather.time_of_day = .4
	# A portaria precisa continuar rodando: sem ela a cancela fica fechada e os caminhões
	# de carga travam nela para sempre. A visita autorizada evita o alarme de invasão.
	session.urban_operations.security.authorized_visit = true
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	var view := Vector3(298.0,.08,220.0)
	world.player.teleport(view)
	world.production.region.set_focus(view)
	var logistics = session.urban_operations.cargo_handling
	var saw_carried_crate := false
	var saw_loaded_truck := false
	var saw_gate_crossed := false
	for _frame in 9000:
		await physics_frame
		if _frame % 20 == 0:
			for actor in get_nodes_in_group("v1_routine_actor"):
				if is_instance_valid(actor) and str(actor.name).begins_with("south_port_worker_") and is_instance_valid(actor.carried_crate) and actor.carried_crate.visible:
					saw_carried_crate = true
			for state in logistics.work_trucks:
				if state.loaded and is_instance_valid(state.truck) and state.truck.get_meta("port_container_loaded",false):
					saw_loaded_truck = true
				# Carregado, o caminhão atravessa a cancela (z 211) rumo ao armazém. O ciclo
				# completo (entrega e volta) leva ~30 000 quadros; a rota é coberta por test_port_haul_route.
				if state.loaded and state.phase == "departed" and is_instance_valid(state.truck) and state.truck.global_position.z < 195.0: saw_gate_crossed = true
		if saw_loaded_truck and saw_carried_crate and saw_gate_crossed: break
	check(saw_carried_crate,"Quay worker physically carries a 3D crate")
	check(saw_loaded_truck,"An unforced crane cycle loads a truck in the real scene")
	check(saw_gate_crossed,"Loaded truck passes the open freight gate on its way to the warehouse")
	for index in logistics.work_trucks.size():
		var state: Dictionary = logistics.work_trucks[index]
		print("REAL_PORT_TRUCK ",index," phase=",state.phase," loaded=",state.loaded," position=",state.truck.global_position if is_instance_valid(state.truck) else "missing")
	print("PORT_REAL_LOADING failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
