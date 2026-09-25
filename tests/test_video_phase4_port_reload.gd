extends "res://tests/test_video_phase4_port_freight.gd"
## Resume the already-proven physical trip; never repeat it to investigate load.
var startup_gates_checked := false

func _trace_added(node: Node) -> void:
	if node.get_script() != preload("res://gameplay/VehicleBoardingPresentation.gd"): return
	node.cancelled.connect(func(reason, point):
		print("FREIGHT_RELOAD_CANCEL reason=", reason, " point=", point, " ready=", world.session.ready_for_play, " kind=", world.session.transition_kind, " driving_blocked=", world.session.blocks_driving_change()))
	node.entered.connect(func(): print("FREIGHT_RELOAD_ENTERED ready=", world.session.ready_for_play, " kind=", world.session.transition_kind))
	_verify_startup_gates.call_deferred(node)

func _verify_startup_gates(body: Node) -> void:
	if startup_gates_checked or world.session.ready_for_play: return
	await physics_frame
	if not is_instance_valid(body) or not body.active: return
	var session = world.session
	startup_gates_checked = true
	check(session.allows_saved_driver_animation() and session.blocks_driving_change(), "saved-driver animation has a dedicated exception while normal driving stays gated")
	var event := InputEventAction.new()
	event.action = "vehicle_interact"
	event.pressed = true
	world.driving._unhandled_input(event)
	check(body.active and not body.exiting and world.driving.transition == body, "F during startup cannot reverse or cancel the saved boarding")
	check(world.driving._entry_option().is_empty() and not session.interact(), "normal entry and interaction remain blocked during restoration")
	check(not session.state.can_attack() and not world.gameplay.fire_at(world.player.position + Vector3.FORWARD * 10), "attacks and firing remain blocked during restoration")
	for action in ["inventory", "journal", "pause_game"]:
		event.action = action
		session._input(event)
	check(not session.modal and not paused, "inventory, journal and pause cannot open during restoration")
	# Probe predicates synchronously, without introducing an actual transition
	# into this restoration. No frame runs while a negative gate is asserted.
	for property in ["modal", "rescue_pending", "arrest_pending", "respawn_busy", "vehicle_transition_busy"]:
		session.set(property, true)
		check(not session.allows_saved_driver_animation(), "saved animation cannot bypass " + property)
		session.set(property, false)
	session.transition_kind = "travel"
	check(not session.allows_saved_driver_animation(), "saved animation cannot bypass another transition")
	session.transition_kind = ""
	session.controller.travel_busy = true
	check(not session.allows_saved_driver_animation(), "saved animation cannot bypass region travel")
	session.controller.travel_busy = false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var checkpoint := EVIDENCE + "phase4-port-depot-save.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--checkpoint="): checkpoint = argument.trim_prefix("--checkpoint=")
	var saved_game: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(checkpoint))
	check(not saved_game.is_empty(), "recorded physical-delivery checkpoint available")
	if not failures.is_empty(): await finish(); return
	node_added.connect(_trace_added)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	check(world.production.state.restore_snapshot(saved_game), "saved checkpoint passes GameState schema")
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	check(startup_gates_checked and not session.allows_saved_driver_animation(), "startup exception was exercised and is cleared after ready")
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.set_process(false)
	await frames(35)
	var ops = session.urban_operations
	var freight = ops.freight
	var bay: int = int(saved_game.world.urban_operations.freight.active_bay)
	var entry: Dictionary = ops.cargo_handling.work_trucks[bay]
	var truck = entry.truck
	var saved: Dictionary = saved_game.world.urban_operations.freight.truck
	print("FREIGHT_RELOAD ready=", session.ready_for_play, " occupied=", world.driving.occupied, " selected=", world.driving.car, " truck=", truck, " p=", truck.global_position if is_instance_valid(truck) else Vector3.INF, " player=", world.player.position, " saved=", saved, " visit=", ops.security.authorized_visit)
	check(is_instance_valid(truck) and truck.global_position.distance_to(saved_point(saved)) < 1, "recorded truck restores at depot")
	check(matching_trucks(FREIGHT._vehicle_id(bay)) == 1 and world.driving.occupied and world.driving.car == truck, "one saved truck restores its occupied driver")
	check(ops.security.authorized_visit, "restoring the driver preserves the existing port visit")
	if not failures.is_empty():
		if is_instance_valid(truck):
			for side in [-1,1]:
				var point: Vector3 = truck.driver_door_anchor(side) + truck.global_basis.x * side * .11 + Vector3.UP * .01
				print("FREIGHT_RELOAD_DOOR side=", side, " point=", point, " clear=", session.position_clear(point), " hull=", world.production.vehicle_position_clear(truck,truck.position,truck.rotation.y), " player_locked=", world.player.input_locked, " body=", world.driving.is_body_transition_active())
		await finish()
		return
	check(entry.loaded and ops.cargo_handling.cranes[bay].visual.get_parent() == truck, "restored cargo is attached to the same truck")
	var depot: Vector3 = freight.depot_position(bay)
	check(world.hud.objective_card.visible and world.hud.objective_label.text.contains("desembarque"), "real HUD asks the restored driver to park and disembark")
	check(world.hud.minimap.objective_target.distance_to(Vector2(depot.x,depot.z)) < .01, "restored minimap points to the depot")
	world.camera.focus_on_store(truck.position + Vector3.UP, 16, .2)
	await frames(25)
	await photograph("reloaded")
	check(world.driving.leave(), "normal physical disembark is admitted")
	check(await wait_transition(), "physical disembark completes")
	await frames(20)
	check(session.nearest().get("target") == "south_port_freight_deliver", "normal delivery action available at the parked cargo")
	await photograph("delivery")
	var balance: int = session.state.economy.balance
	var before: Dictionary = ops.snapshot()
	var returned_at: Vector3 = truck.position
	check(session.interact() and session.state.economy.balance == balance + 300, "explicit handback pays R$300")
	check(freight.active_bay == -1 and freight.jobs[bay] == FREIGHT.DELIVERED and not entry.loaded, "completed shipment and empty truck persist")
	check(entry.phase == "approach" and truck.traffic and world.driving.car == null, "truck returns to NPC control and leaves player selection")
	var prior: Dictionary = saved_game.world.urban_operations.freight.previous_vehicle
	check(session.state.world_state.vehicles.size() == 1 and session.state.world_state.vehicles[0].vehicle_id == prior.vehicle_id and saved_point(session.state.world_state.vehicles[0]).distance_to(saved_point(prior)) < .01, "previous personal car survives the loan and reload")
	check(not session.interact() and session.state.economy.balance == balance + 300, "duplicate delivery interaction cannot pay twice")
	check(ops.restore_snapshot(before), "stale active world checkpoint is accepted for reconciliation")
	check(freight.active_bay == -1 and freight.jobs[bay] == FREIGHT.DELIVERED and session.state.economy.balance == balance + 300, "economy receipt prevents restoring or paying stale cargo")
	await frames(50)
	check(not session.freight_active and not world.hud.objective_card.visible, "payment clears the actual HUD objective")
	check(world.hud.minimap.objective_target.distance_to(Vector2(depot.x,depot.z)) > 1, "payment clears the depot minimap target")
	check(truck.position.distance_to(returned_at) > .2 and world.player.visible, "empty NPC truck physically departs with Dante outside")
	await photograph("paid")
	var legacy: Dictionary = ops.snapshot()
	legacy.erase("freight")
	check(ops.restore_snapshot(legacy) and not freight.bay_available(bay), "legacy world markers still respect durable paid receipts")
	# Materialize another existing bay only for the independent removal branch.
	if not is_instance_valid(ops.cargo_handling.work_trucks[0].truck): ops.cargo_handling._spawn_work_truck(0)
	var other = ops.cargo_handling.work_trucks[0].truck
	check(is_instance_valid(other), "second authored truck available for the removal branch")
	if is_instance_valid(other):
		var removed_job: Dictionary = freight.snapshot()
		removed_job.active_bay = 0
		removed_job.truck = preload("res://runtime/FleetState.gd").capture(other, "harbor")
		removed_job.previous_vehicle = prior.duplicate(true)
		check(freight.restore_snapshot(removed_job), "independent shipment restore accepted")
		await frames(20)
		world.driving.car = other
		world.driving._watch_car(other)
		world.production.capture_player_vehicle()
		other.queue_free()
		await frames(20)
		check(freight.active_bay == -1 and freight.jobs[0] == FREIGHT.LOST, "removed truck retires its shipment")
		check(not session.state.world_state.vehicles.any(func(record): return record.get("vehicle_id") == FREIGHT._vehicle_id(0)), "removal autosave cannot resurrect the deleted truck")
		check(session.state.world_state.vehicles[0].vehicle_id == prior.vehicle_id, "removal also restores the previous personal-car record")
		var loss: Dictionary = freight.snapshot()
		check(FREIGHT.validate_snapshot(loss) and loss.truck.is_empty() and freight.restore_snapshot(loss), "lost shipment remains valid and absent across reload")
		await frames(20)
		check(not session.freight_active and not world.hud.objective_card.visible and session.state.economy.balance == balance + 300, "loss clears HUD without any extra payment")
	await finish()
