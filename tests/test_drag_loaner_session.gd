extends SceneTree
const PROFILE:=preload("res://runtime/desert/DragStandaloneProfile.gd")
const FIXTURE:=preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STORE:=preload("res://runtime/SaveStore.gd")
var world
var output:=""
var failures:Array[String]=[]
var checks:=0
class InputShield extends Node:
	func _input(_event: InputEvent) -> void: get_viewport().set_input_as_handled()
	func _physics_process(_delta: float) -> void:
		for action in InputMap.get_actions(): Input.action_release(action)
func _initialize()->void:
	create_timer(360).timeout.connect(func(): push_error("LOANER timeout"); quit(3))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-saved="):
			recheck_saved.call_deferred(argument.trim_prefix("--check-saved="))
			return
	run.call_deferred()

func recheck_saved(directory:String)->void:
	# Reconfere a asserção de save que falhou sem repetir as provas físicas já
	# validadas e a recarga. O Main concede legitimamente first_grand (+50).
	var saved:=STORE.read_valid(directory.path_join("borrowed-save.json"))
	var pending:=STORE.read_valid(directory.path_join("pending-night.json"))
	if not check(not saved.is_empty() and not pending.is_empty(),"both real checkpoints pass complete save validation"): await finish(); return
	check(saved.economy.transactions.get("reward:achievement:first_grand",{}).get("amount",0)==50 and saved.economy.balance==2087,"saved balance includes starting allowance, real achievement and37test reward")
	check(saved.world.vehicles.size()==1 and saved.world.vehicles[0].vehicle_id=="drag_profile_starter" and not saved.world.vehicles[0].was_driven,"saved physical car remains original and unoccupied")
	check("rival_digo_ecu" in preload("res://runtime/desert/DesertGarageState.gd").vehicle(saved.world,"drag_loaner_desert_faisca","desert_faisca").owned,"real proof reward persists in the validated checkpoint")
	check(pending.economy.balance==saved.economy.balance and preload("res://activities/desert_drag/DragNightProgress.gd").current(pending.world).vehicle_id=="drag_loaner_desert_faisca","pending night checkpoint preserves same cash and workshop identity")
	await finish()
func check(ok:bool,label:String)->bool:
	checks+=1
	print("DRAG_LOANER ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok
func frames(count:int)->void:
	for i in count: await physics_frame
func run()->void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	var shield:=InputShield.new()
	shield.process_physics_priority=-100
	output=FIXTURE.output_dir("drag-loaner")
	var data:=PROFILE.initial_snapshot()
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not check(not path.is_empty(),"standalone checkpoint validates before Main"): await finish(); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	root.add_child(shield)
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if not check(world.session!=null and world.session.ready_for_play,"real Main ready"): await finish(); return
	var session=world.session
	var race=session.desert.drag
	var loan=race.loaner_controller
	var driving=world.driving
	world.gameplay.god_mode=true
	world.dispatch.router.nearest_edge(race.staging_point)
	check(world.dispatch.router._native!=null,"native C# route backend")
	check(session.state.campaign.snapshot().completed.is_empty(),"direct racing profile does not complete campaign")
	check(driving.occupied and driving.car.vehicle_id=="drag_profile_starter","direct profile restores seated starter at meet")
	var original=driving.car
	var original_id:String=original.vehicle_id
	var original_health:float=original.health
	var had_pin:bool=original.has_meta("race_owned")
	var old_pin:Variant=original.get_meta("race_owned",false)
	# O carro selecionado no início pode contornar o array de revisão do ambiente. Inscreve-o no
	# ciclo de vida comum de carro estacionado para exercitar a regra de streaming de 145 m.
	if original not in world.production.vehicles: world.production.vehicles.append(original)
	if driving.occupied:
		check(driving.leave(),"normal door exit before borrowing")
		for i in 300:
			await physics_frame
			if not driving.occupied and not driving.is_body_transition_active(): break
	race.open_meet.enabled=false
	await frames(3)
	check(await loan.request("desert_faisca"),"workshop admits one physical loaner in a clear bay")
	if not is_instance_valid(loan.car): await finish(); return
	check(not await loan.request("desert_mirage"),"second loan cannot duplicate the fleet")
	check(original.vehicle_id==original_id and original.health==original_health,"original vehicle remains intact")
	var borrowed=loan.car
	world.player.teleport(borrowed.driver_door_anchor(1)+borrowed.global_basis.x*.25+Vector3.UP*.08)
	await frames(4)
	check(driving.interact(),"borrowed car uses ordinary boarding")
	for i in 300:
		await physics_frame
		if driving.occupied and not driving.is_body_transition_active() and not borrowed.input_locked: break
	check(driving.car==borrowed and driving.occupied,"player controls the actual loaner")
	check(not loan.return_car(),"cannot remove borrowed car beneath its driver")
	# Política de save num limite de região: só o limite de estado é injetado,
	# não uma afirmação de que esta fixture dirigiu pela ponte da campanha.
	session.state.region_id="harbor"
	check(not loan.save_block_reason().is_empty(),"occupied loan blocks an out-of-region checkpoint")
	loan.prepare_save()
	check(session.state.world_state.vehicles[0].region=="desert","original car retains its own region at a save boundary")
	session.state.region_id="desert"
	for step in 2:
		if not await workshop_proof(step): await finish(); return
	check(is_instance_valid(original) and original.health==original_health,"original physical car survives beyond the 145 m streaming radius")
	var garage=preload("res://runtime/desert/DesertGarageState.gd")
	check("rival_digo_ecu" in garage.vehicle(session.state.world_state,borrowed.vehicle_id,borrowed.archetype).owned,"standalone loaner earns actual rival part through two physical proofs")
	session.state.economy.grant_reward("drag_loan_test",37)
	var expected_balance:int=session.state.economy.balance
	check(session.save_game(),"progress can be checkpointed while borrowing")
	check(session.state.world_state.vehicles[0].vehicle_id==original_id and not session.state.world_state.vehicles[0].was_driven,"saved vehicle stays the original car")
	check(session.state.world_state.has("pedestrian") and session.state.world_state.pedestrian.region=="desert","reload returns on foot to lending point")
	var store:=STORE.new()
	store.path=output.path_join("borrowed-save.json")
	check(store.save(session.state)==OK,"actual SaveStore writes isolated progress during loan")
	var restored:=STORE.read_valid(store.path)
	check(not restored.is_empty() and restored.economy.balance==expected_balance and restored.world.vehicles[0].vehicle_id==original_id,"cash and original car survive productive validation")
	check("rival_digo_ecu" in garage.vehicle(restored.world,borrowed.vehicle_id,borrowed.archetype).owned,"earned part survives the same real save roundtrip")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("borrowed.png"))
	check(driving.leave(),"normal exit after borrowing")
	for i in 300:
		await physics_frame
		if not driving.occupied and not driving.is_body_transition_active(): break
	check(loan.return_car(),"return releases only the unoccupied workshop car")
	await frames(3)
	check(not is_instance_valid(borrowed) and driving.car==original and is_instance_valid(original),"original selection restored, no loaner remains")
	check(original.has_meta("race_owned")==had_pin and original.get_meta("race_owned",false)==old_pin,"return restores the original streaming ownership")
	var night=preload("res://activities/desert_drag/DragNightProgress.gd")
	var resumed: Dictionary=night.begin(session.state.world_state,"digo","drag_loaner_desert_faisca","desert_faisca","desert_faisca")
	check(resumed.ok,"saved night can retain the workshop model identity")
	check(not await loan.request("desert_siroco"),"saved workshop night rejects another model")
	check(await loan.request("desert_faisca"),"same workshop model can resume its saved night")
	check(session.save_game(),"pending workshop night checkpoints normally")
	store.path=output.path_join("pending-night.json")
	check(store.save(session.state)==OK,"pending night is written through actual SaveStore")
	world.free()
	await frames(3)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",store.path)
	root.add_child(world)
	current_scene=world
	root.move_child(shield,-1)
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if not check(world.session!=null and world.session.ready_for_play,"fresh Main reloads pending workshop night"): await finish(); return
	session=world.session
	race=session.desert.drag
	loan=race.loaner_controller
	race.open_meet.enabled=false
	check(not world.driving.occupied and session.state.campaign.snapshot().completed.is_empty(),"fresh load returns on foot without unlocking campaign")
	check(night.current(session.state.world_state).get("vehicle_id","")=="drag_loaner_desert_faisca","fresh load retains the exact workshop series identity")
	check(not await loan.request("desert_siroco"),"fresh load rejects replacement with another workshop model")
	check(await loan.request("desert_faisca"),"fresh load physically restores the matching workshop model")
	check("rival_digo_ecu" in garage.vehicle(session.state.world_state,"drag_loaner_desert_faisca","desert_faisca").owned,"fresh load retains earned workshop part ownership")
	night.abandon(session.state.world_state)
	check(loan.return_car(),"abandoned workshop series releases its loan normally")
	check(session.state.campaign.snapshot().completed.is_empty(),"borrow and rewards never unlock campaign bridge")
	await finish()

func workshop_proof(step:int)->bool:
	var session=world.session
	var race=session.desert.drag
	var controller=race.challenge_controller
	if not check(controller.open("digo"),"loaner challenge panel opens %d"%step): return false
	controller.panel.buttons["step:"+str(step)].pressed.emit()
	if not check(not controller.panel.buttons.start.disabled,"loaner objective is available %d"%step): return false
	controller.panel.buttons.start.pressed.emit()
	for i in 180:
		await physics_frame
		if race.active: break
	if not check(race.active and race._challenge_attempt,"loaner starts physical proof %d"%step): return false
	while race.active:
		race._throttle_override=.54 if race.phase=="staging" else 1.0
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		await physics_frame
	if not check(race.last_result.get("challenge_success",false),"loaner completes measured proof %d"%step): return false
	var returned:bool=await race.return_to_entry()
	session.close_menu()
	return check(returned,"loaner returns to the meet after proof %d"%step)

func finish()->void:
	print("DRAG_LOANER_DONE checks=",checks," failures=",failures," output=",output)
	if is_instance_valid(world): world.free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
