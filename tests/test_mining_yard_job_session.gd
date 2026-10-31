extends "res://tests/test_mining_session.gd"
## Integração nativa de contato/menu/save da sessão e entrada real da pá. Os posicionamentos
## iniciais de carga/carro são fixtures de diagnóstico, não evidência de rota dirigida.
const JOB := preload("res://gameplay/mining/jobs/MiningYardJob.gd")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): finish(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-yard-job-session")
	var at:=JOB.CONTACT+Vector3.UP*.08
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"isolated quarry fixture"): finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for frame in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and not world.production.save_invalid,"real Main ready"): finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# path active")
	check(world.production.store.path==path,"writes isolated")
	world.production.no_save=false
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	if world.session.modal: world.session.close_menu()
	await frames(60)
	var job=world.session.desert.extras.mining_job
	if not check(job!=null,"integrated job exists"): finish(1); return
	check(world.player.is_on_floor(),"contact has real floor support")
	check(world.session.nearest().get("target","")=="yard_job","contact wins normal interaction routing")
	check(await world.session.interact(),"normal E opens contract menu")
	job._begin()
	check(JOB.STATE.data(world.session.state.world_state).status=="active","menu accepts contract")
	if world.session.modal: world.session.close_menu()
	await frames(20)
	await photo("job-accepted")
	var operation=world.session.mining.operation
	if not check(operation.rocks.size()>=3,"reuses existing physical rocks"): finish(1); return
	var machine: CharacterBody3D
	for car in world.production.vehicles:
		if is_instance_valid(car) and car.vehicle_id=="mineradora_tractor": machine=car; break
	if not check(machine!=null,"existing loader available"): finish(1); return
	# Põe o trator na aproximação norte livre; o embarque comum e B/PgUp
	# operam o adaptador real dele. Nenhum teste chama a mutação do estado de entrega.
	var delivery:=JOB.DESTINATION+Vector3(-1.8,0,0)
	# Dá um metro inteiro de folga de rolagem ao retirar a pá erguida;
	# soltar sobre o limite pintado falha com razão no contrato de entrega.
	machine.place(delivery+Vector3(0,.08,-4.1),PI)
	world.player.teleport(machine.driver_door_anchor(1)+machine.global_basis.x*.5+Vector3.UP*.08)
	await frames(20)
	if not check(world.driving.interact(),"ordinary tractor boarding"): finish(1); return
	for frame in 600:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	if not check(world.driving.occupied and world.driving.car==machine,"driver controls tractor"): finish(1); return
	var controls=machine.get_node("MiningMachine")
	var rock: RigidBody3D=operation.rocks[0]
	rock.global_position=delivery+Vector3.UP*.65
	rock.linear_velocity=Vector3.ZERO
	rock.angular_velocity=Vector3.ZERO
	await frames(120)
	check(JOB.STATE.data(world.session.state.world_state).delivered.is_empty(),"pushing a rock into bay without using scoop gives no credit")
	# Move só a fixture inicial para o alcance real de captura da pá.
	rock.global_position=controls.cargo_anchor()+Vector3(0,.65,.5)
	await frames(2)
	key(KEY_B,true); await frames(2); key(KEY_B,false)
	if not check(controls.cargo==rock,"B captures real job load"): finish(1); return
	await frames(20)
	check(JOB.STATE.data(world.session.state.world_state).delivered.is_empty(),"attached load not credited")
	check(not world.session.save_block_reason().is_empty(),"suspended cargo blocks save")
	key(KEY_PAGEUP,true); await frames(40); key(KEY_PAGEUP,false)
	await photo("job-lifted")
	key(KEY_B,true); await frames(2); key(KEY_B,false)
	check(not is_instance_valid(controls.cargo),"B restores loose rigid physics")
	Input.action_press("brake",.45)
	await frames(120)
	Input.action_release("brake")
	Input.action_press("handbrake")
	await frames(180)
	Input.action_release("handbrake")
	print("MINING_JOB_DROP point=",rock.global_position," carrier=",machine.global_position," anchor=",controls.cargo_anchor()," stable=",JOB.deposit_ready(rock))
	check(JOB.STATE.data(world.session.state.world_state).delivered.size()==1,"released and grounded actual hydraulic load credited exactly once")
	await photo("job-deposited")
	check(world.driving.leave(),"ordinary tractor exit")
	for frame in 600:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	job.cancel_attempt()
	check(JOB.STATE.data(world.session.state.world_state).status=="paused" and JOB.STATE.data(world.session.state.world_state).delivered.size()==1,"rescue/death cancellation retains accepted delivery")
	check(world.session.save_game(),"partial job writes via full session")
	var saved:=preload("res://runtime/SaveStore.gd").read_valid(path)
	check(not saved.is_empty() and JOB.STATE.data(saved.world).delivered.size()==1,"full save validator restores partial job")
	check(not saved.is_empty() and JOB.STATE.validate_wallet(saved.world,saved.economy),"partial state has consistent unpaid wallet")
	if not saved.is_empty() and JOB.STATE.data(saved.world).delivered.has("0"):
		# Recria o controlador e a rocha original dele, exatamente os dois donos
		# restaurados de forma independente no início. Mantém o terreno/colisores reais em streaming.
		var row: Dictionary=JOB.STATE.data(saved.world).delivered["0"]
		var expected:=Vector3(row.position[0],row.position[1],row.position[2])
		rock.global_position=LAYOUT.cargo_spawns()[0]+Vector3.UP*.65
		rock.freeze=false
		rock.remove_meta("mining_job_delivered")
		var replacement:=JOB.new()
		world.session.desert.extras.add_child(replacement)
		replacement.configure(world.session)
		world.session.desert.extras.mining_job=replacement
		# Troca a posse de forma atômica antes de ceder: o HUD consulta o agregador
		# a cada quadro e nunca pode observar um nó de fixture liberado de propósito.
		job.queue_free()
		await frames(90)
		check(rock.freeze and rock.global_position.distance_to(expected)<.03,"fresh controller restores delivered physical rock without duplicating cargo")
		check(JOB.STATE.data(world.session.state.world_state).delivered.size()==1,"restoration does not double-credit accepted cargo")
	finish(0 if failures.is_empty() else 1)
