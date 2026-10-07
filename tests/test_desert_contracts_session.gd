extends SceneTree
const FIXTURE=preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE=preload("res://runtime/desert/DesertContractState.gd")
const STORE=preload("res://runtime/SaveStore.gd")
var world
var folder:=""
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("CONTRACT_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func boot(path: String) -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	await create_timer(1).timeout
func stage_at(point: Vector3) -> void:
	# Fixture relocation only: this does not certify the long driving routes.
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	await physics_frame
	world.player.teleport(point+Vector3.UP*.08+Vector3.BACK*.8)
	await create_timer(1).timeout
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		var offset: Vector3=point-world.player.global_position
		offset.y=0
		if offset.length()<.18: break
		world.player.automatic_direction=offset.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	var distance: Vector3=point-world.player.global_position
	distance.y=0
	check(distance.length()<.25,"physical final approach")
func choose(prefix: String) -> bool:
	for button in world.session.column.get_children():
		if button is Button and button.text.begins_with(prefix):
			button.pressed.emit()
			return true
	return false
func finish_dialogue() -> void:
	for i in 6:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
	await physics_frame
func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run() -> void:
	create_timer(300).timeout.connect(func(): push_error("CONTRACT_SESSION timeout"); quit(3))
	folder=FIXTURE.output_dir("desert-contract-session")
	var snapshot:=FIXTURE.full_snapshot(Vector3(-151,.08,-941.8),true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[-151,.08,-941.8]}
	var path:=FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot(path)
	check(world.production.loaded_save and not world.production.save_invalid,"isolated save loaded")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# backend")
	var before: int=world.session.state.economy.balance
	var raul_at: Vector3=preload("res://runtime/desert/DesertCampaign.gd").LOCATIONS.raul+Vector3(0,0,1.2)
	for row in [
		["parts",0,Vector3(-151,0,-941.8),"Aceitar entrega"],
		["parts",1,raul_at,"Entregar peças"],
		["rail",0,raul_at,"Aceitar investigação"],
		["parts",2,Vector3(-151,0,-941.8),"Entregar recibo"],
		["rail",1,Vector3(-1097,0,-583),""],
		["rail",2,Vector3(-872,0,-546.4),""],
		["rail",3,raul_at,"Entregar investigação"],
	]:
		await stage_at(row[2])
		if row[0]=="rail" and row[1]==1:
			check(not world.session.desert.contracts.nearest_action().is_empty(),"live field action positive control")
			world.player.input_locked=true
			check(world.session.desert.contracts.nearest_action().is_empty(),"locked player cannot investigate")
			world.player.input_locked=false
			paused=true
			check(world.session.desert.contracts.nearest_action().is_empty(),"pause blocks investigation")
			paused=false
		check(world.session.position_clear(world.player.global_position),"supported interaction position "+str(row[0])+str(row[1]))
		check(await world.session.interact(),"ordinary interaction "+str(row[0])+str(row[1]))
		if not str(row[3]).is_empty():
			await photo(str(row[0])+str(row[1])+"-menu")
			check(choose(row[3]),"real menu button "+str(row[3]))
		check(STATE.data(world.session.state.world_state)[row[0]]==int(row[1])+1,"step advances once")
		await photo(str(row[0])+str(row[1])+"-dialogue")
		await finish_dialogue()
		check(not world.player.input_locked and not world.session.modal,"controls recovered")
		check(world.session.save_game(),"real disk save")
		check(not STORE.read_valid(path).is_empty(),"disk snapshot validates")
		if failures: break
		if row[0]=="rail" and row[1]==1:
			world.free()
			await process_frame
			await boot(path)
			check(STATE.data(world.session.state.world_state).rail==2,"cold reload resumes investigation")
			check(world.session.desert.objective().contains("vagão"),"HUD resumes target")
	var wallet: Dictionary=world.session.state.economy.snapshot()
	check(wallet.transactions.get("reward:desert_contract_parts",{}).get("amount")==1200,"parts receipt exact")
	check(wallet.transactions.get("reward:desert_contract_rail",{}).get("amount")==2200,"rail receipt exact")
	# Earning the first R$ 1,000 also awards the existing first_grand achievement.
	check(wallet.transactions.get("reward:achievement:first_grand",{}).get("amount")==50,"existing achievement paid independently")
	check(world.session.state.economy.balance==before+3450,"two payments plus existing achievement, no duplicates")
	check(STATE.data(world.session.state.world_state).active=="","main story target restored")
	check(not world.session.desert.contracts._advance("rail",3),"stale turn-in cannot pay again")
	world.session.close_menu()
	world.player.input_locked=true
	check(world.session.desert.contracts.nearest_action().is_empty(),"locked player cannot collect")
	world.player.input_locked=false
	print("DESERT_CONTRACT_SESSION checks=%d failures=%d evidence=%s"%[checks,failures,folder])
	quit(0 if failures==0 else 1)
