extends SceneTree
## Actual Main, C# router, ordinary interactions, physical approaches and cold save reload.
## Fixture relocation between locations does not certify the complete driving route.
const FIXTURE:=preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE:=preload("res://runtime/desert/community/DesertCommunityState.gd")
const SITE:=preload("res://world/desert/community/DesertCommunitySite.gd")
const CONTRACTS:=preload("res://runtime/desert/DesertContractState.gd")
const ECONOMY:=preload("res://systems/economy/Economy.gd")
const STORE:=preload("res://runtime/SaveStore.gd")
var world
var folder:=""
var failures:=0
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("COMMUNITY_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func boot(path: String) -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	# --no-save protects ordinary startup, then persistence is enabled only for
	# the verified isolated fixture path. Never enable writes to a user slot.
	check(world.production.store.path==path and path.begins_with(folder+"/"),"only isolated fixture slot may receive writes")
	if world.production.store.path!=path or not path.begins_with(folder+"/"): quit(1); return
	world.production.no_save=false
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	await create_timer(1).timeout
func stage_at(point: Vector3) -> void:
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	await physics_frame
	world.player.teleport(point+Vector3(0,.08,.7))
	await create_timer(1).timeout
	var deadline:=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline:
		var offset: Vector3=point-world.player.global_position
		offset.y=0
		if offset.length()<.15: break
		world.player.automatic_direction=offset.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	check(Vector2(point.x,point.z).distance_to(Vector2(world.player.global_position.x,world.player.global_position.z))<.22,"real player walks final approach")
	check(world.session.position_clear(world.player.global_position),"player capsule supported and clear")
func close_dialogue() -> void:
	for i in 8:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
	await physics_frame
func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func verify_pump_physics() -> void:
	await stage_at(SITE.PUMP+Vector3(.4,0,0))
	check(world.player.test_move(world.player.global_transform,Vector3(-3,0,0)),"actual player capsule sweep blocked by pump")
	check(not world.player.test_move(world.player.global_transform,Vector3(0,0,1.8)),"pump leaves exterior circulation open")
	for actor in world.people:
		if not is_instance_valid(actor) or not actor is CharacterBody3D: continue
		var transform: Transform3D=actor.global_transform
		transform.origin=world.player.global_position
		check(actor.test_move(transform,Vector3(-3,0,0)),"real resident capsule also blocked by pump")
		break
	# Three controls under the gameplay camera expose drawing/occlusion errors;
	# these photographs need visual review and are not an automatic depth verdict.
	for offset in [Vector3(0,0,1.8),Vector3(0,0,-1.8),Vector3(2.1,0,0)]:
		await stage_at(SITE.ORIGIN+offset)
		await create_timer(.4).timeout
		await photo("pump-depth-"+str(offset.x)+"-"+str(offset.z))
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("COMMUNITY_SESSION timeout"); quit(3))
	folder=FIXTURE.output_dir("desert-community-session")
	var at:=SITE.RADIO+Vector3.UP*.08
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var wallet:=ECONOMY.new()
	check(wallet.restore_snapshot(snapshot.economy),"fixture wallet restored")
	for step in 4: check(CONTRACTS.advance(snapshot.world,wallet,"rail",step).ok,"rail prerequisite in isolated checkpoint")
	check(CONTRACTS.advance(snapshot.world,wallet,"parts",0).ok,"another tracked contract exists before selecting community")
	check(preload("res://gameplay/mining/jobs/MiningYardJobState.gd").begin(snapshot.world),"another yard job exists before selecting community")
	snapshot.economy=wallet.snapshot()
	var path:=FIXTURE.write_fixture(folder,"save.json",snapshot)
	check(not path.is_empty(),"isolated checkpoint valid")
	if path.is_empty(): quit(1); return
	await boot(path)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# router active")
	var community=world.session.desert.extras.community
	check(is_instance_valid(community),"integrated community controller")
	var initial_balance: int=world.session.state.economy.balance
	for step in STATE.LAST:
		community=world.session.desert.extras.community
		await stage_at(community.step_definition(step).point)
		var action: Dictionary=community.nearest_action()
		check(not action.is_empty(),"physical interaction available "+str(step))
		if action.is_empty(): break
		world.player.input_locked=true
		check(community.nearest_action().is_empty(),"input lock blocks action")
		world.player.input_locked=false
		paused=true
		check(community.nearest_action().is_empty(),"pause blocks action")
		paused=false
		await photo("before-"+str(step))
		check(await world.session.interact(),"ordinary session interaction "+str(step))
		check(STATE.data(world.session.state.world_state).step==step+1,"objective advanced once")
		check(CONTRACTS.data(world.session.state.world_state).active=="" and preload("res://gameplay/mining/jobs/MiningYardJobState.gd").data(world.session.state.world_state).status=="paused","selected community objective takes HUD priority without losing other jobs")
		check(not community.perform(action),"stale action blocked while dialogue open")
		await photo("after-"+str(step))
		await close_dialogue()
		check(not world.player.input_locked and not world.session.modal,"control recovered")
		check(world.session.save_game(),"real disk save")
		var saved:=STORE.read_valid(path)
		check(not saved.is_empty() and STATE.data(saved.world).step==step+1,"real persisted snapshot validates and contains new progress")
		if step==0: await verify_pump_physics()
		if step in [2,3,4]:
			var sites:=get_nodes_in_group(SITE.GROUP)
			check(sites.size()==1,"one streamed community site")
			if sites.size()==1:
				check(sites[0].get_node("InstalledCoupling").visible,"installed component visible")
				check(sites[0].get_node("RestoredWater").visible==(step>=3),"water matches opened valve")
		if step==1 or step==3:
			world.free()
			await process_frame
			await boot(path)
			check(STATE.data(world.session.state.world_state).step==step+1,"cold save reload keeps cargo/water")
			check(world.session.desert.extras.community.objective().contains(STATE.TITLE),"objective restored after load")
		if failures: break
	check(STATE.data(world.session.state.world_state).step==STATE.LAST,"community story finished")
	check(world.session.state.economy.balance==initial_balance+1800,"exactly one community reward")
	check(world.session.state.economy.snapshot().transactions.get("reward:"+STATE.REWARD_ID,{}).get("amount")==1800,"durable reward receipt")
	print("DESERT_COMMUNITY_SESSION checks=%d failures=%d evidence=%s"%[checks,failures,folder])
	quit(0 if failures==0 else 1)
