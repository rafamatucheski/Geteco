extends "res://tests/test_urban_operations.gd"
func run() -> void:
	check(await _initialize_world(),"world starts")
	if not failures.is_empty(): quit(1); return
	world.player.controlled_automatically=true
	world.player.teleport(PORT_CENTER)
	world.production.region.set_focus(PORT_CENTER)
	await settle(15)
	var port=urban.port
	port.refresh_context()
	port._ensure_worker(1)
	check(is_instance_valid(port.boats[1].worker),"physical loader admitted")
	if is_instance_valid(port.boats[1].worker):
		var worker=port.boats[1].worker
		worker.set_physics_process(false)
		var total: int=worker.crate_total()+int(port.boats[1].load)
		worker.receive_damage(1000)
		check(port.worker_respawn[1]==180,"loader cooldown starts")
		check(not is_instance_valid(port.boats[1].worker),"dead loader removed from work cycle")
		var snapshot: Dictionary=port.snapshot()
		check(port.validate_snapshot(snapshot),"death preserves conserved cargo snapshot")
		var interrupted: Dictionary=port.saved_workers[1]
		check(int(interrupted.crate_stock[0])+int(interrupted.crate_stock[1])+int(port.boats[1].load)==total,"death does not create or delete cargo")
		check(port.restore_snapshot(snapshot),"loader state restores while respawn pending")
		port._ensure_worker(1)
		check(not is_instance_valid(port.boats[1].worker),"load cannot bypass cooldown")
		world.camera.set_process(false)
		world.camera.position+=Vector3(0,0,1000)
		port.worker_respawn[1]=0
		port._ensure_worker(1)
		check(is_instance_valid(port.boats[1].worker),"loader returns to work offscreen")
		check(port.validate_snapshot(port.snapshot()),"returned loader preserves freight ledger")
	world.free()
	await process_frame
	print("PORT_LOADING_DEATH failures=",failures)
	quit(0 if failures.is_empty() else 1)
