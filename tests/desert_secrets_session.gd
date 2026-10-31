extends SceneTree
## Main real, entrada de caminhada e interação, profundidade renderizada e load frio de save.
## Os bandidos são explicitamente derrotados antes; o combate deles tem a própria fixture separada.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const SITE := preload("res://world/desert/DesertAbandonedSite.gd")
const SECRET := preload("res://runtime/desert/DesertSecretState.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const ACHIEVEMENTS := preload("res://data/catalogs/AchievementCatalog.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
var world: Node3D
var failures: Array[String] = []
var checks := 0
var folder := ""
var path := ""
var old_launch_path := ""
var depth: Array[Dictionary] = []
var temporal: Node
var temporal_report: Dictionary = {}

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): failures.append("240s watchdog"); _finish(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	checks += 1
	print("DESERT_SECRETS ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _seed() -> Dictionary:
	var state := STATE.new()
	if not state.restore_snapshot(FIXTURE.full_snapshot(SITE.POSITION+Vector3(0,.08,6),true)): return {}
	state.set_location("desert")
	state.world_state.pedestrian={"region":"desert","position":[-1300,.08,-1714]}
	state.world_state.desert_bandits={"version":1,"defeated_mask":7}
	state.world_state.desert_story=preload("res://runtime/desert/DesertStoryState.gd").defaults()
	state.world_state.desert_story.arrived=true
	return state.snapshot()

func _run() -> void:
	if not _check(DisplayServer.get_name()!="headless" and "--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"rendered .NET and --no-save required; explicit isolated snapshot files only"):
		_finish(2); return
	folder=FIXTURE.output_dir("desert-secrets-session")
	path=FIXTURE.write_fixture(folder,"initial.json",_seed())
	if not _check(not path.is_empty(),"isolated completed-campaign checkpoint validates with pre-defeated bandits"):
		_finish(1); return
	old_launch_path=str(root.get_node("V2Launch").selected_path)
	if not await _load_world(): _finish(1); return
	if not _begin_temporal(): _finish(1); return
	var session=world.session
	_check(not world.gameplay.god_mode,"no invulnerability during physical walking")
	world.player.controlled_automatically=true
	world.player.speed=3.0
	if not await _walk(world.player,SITE.POSITION+Vector3(0,0,.2),8.0): _finish(1); return
	_check(session.state.place_id.is_empty() and not session.modal,"open ruin uses continuous exterior walking and camera")
	var house: Dictionary=SITE.definitions()[0]
	if not await _walk(world.player,house.interaction,4.0): _finish(1); return
	var before: int=session.state.economy.balance
	if not _check(session.nearest().get("target","")=="secret:"+SITE.HOUSE_ID,"FullSession selects the reachable physical house cache"):
		print("SECRET_ACTION_DIAGNOSTIC ",session.nearest()," player=",world.player.global_position)
		_finish(1); return
	await _input("interact")
	await _frames(4)
	_check(SECRET.collected(session.state.world_state,SITE.HOUSE_ID),"real interaction records Vicente clue")
	_check_receipt(session.state.economy,SITE.HOUSE_ID+"_cache",5000)
	_check_receipt(session.state.economy,"achievement:first_grand",int(ACHIEVEMENTS.CASH_REWARDS.first_grand))
	var after_house: int=before+5000+int(ACHIEVEMENTS.CASH_REWARDS.first_grand)
	_check(session.state.economy.balance==after_house,"house gives5000 plus the catalogue first_grand bonus, with both exact receipts")
	_check(session.state.economy.has_reward_receipt(SITE.HOUSE_ID+"_cache"),"native economy has durable unique house receipt")
	if session.dialogue_open: await _input("interact")
	if session.modal: await _input("ui_cancel")
	await _input("interact")
	_check(session.state.economy.balance==after_house,"repeated real input leaves the settled house balance unchanged")
	var missing_marker: Dictionary={}
	var recovered: Dictionary=SECRET.claim(missing_marker,session.state.economy,SITE.HOUSE_ID,true)
	_check(bool(recovered.get("ok",false)) and not bool(recovered.get("reward_changed",true)) and session.state.economy.balance==after_house,"durable receipt repairs a missing world marker without paying twice")
	_check(not bool(SECRET.claim({},session.state.economy,SITE.CABIN_ID,false).ok),"dead player cannot claim an unseen cache")
	# A área inteira da mesa bloqueia tanto uma varredura grande quanto uma caminhada sustentada.
	_check(world.player.test_move(world.player.global_transform,Vector3(5,0,0)),"large player sweep cannot cross the table footprint")
	world.player.automatic_direction=Vector3.RIGHT
	await _frames(75)
	world.player.automatic_direction=Vector3.ZERO
	_check(world.player.global_position.x<SITE.POSITION.x+1.68 and world.player.global_position.y<.2,"walking stops beside the table without climbing its top")
	if not await _walk(world.player,SITE.POSITION+Vector3(0,0,.2),4.0): _finish(1); return
	if not await _walk(world.player,SITE.POSITION+Vector3(0,0,6),5.0): _finish(1); return
	for point in [Vector3(-1314,0,-1710),Vector3(-1325,0,-1712),Vector3(-1331,0,-1714)]:
		if not await _walk(world.player,point,8.0): _finish(1); return
	var cabin: Dictionary=SITE.definitions()[1]
	if not await _walk(world.player,cabin.interaction,5.0): _finish(1); return
	_check(session.nearest().get("target","")=="secret:"+SITE.CABIN_ID,"connected35m walking route reaches the cabin cache")
	await _input("interact")
	await _frames(4)
	_check_receipt(session.state.economy,SITE.CABIN_ID+"_cache",5000)
	_check_receipt(session.state.economy,"achievement:shark",int(ACHIEVEMENTS.CASH_REWARDS.shark))
	var final_balance: int=after_house+5000+int(ACHIEVEMENTS.CASH_REWARDS.shark)
	_check(SECRET.collected(session.state.world_state,SITE.CABIN_ID) and session.state.economy.balance==final_balance,"cabin gives5000 plus the catalogue shark bonus, with both exact receipts")
	if session.dialogue_open: await _input("interact")
	if session.modal: await _input("ui_cancel")
	if not await _walk(world.player,SITE.CABIN_POSITION+Vector3(.4,0,.45),3.0): _finish(1); return
	_check(world.player.test_move(world.player.global_transform,Vector3(-3,0,0)),"cabin cot blocks a large player sweep across its whole footprint")
	world.player.automatic_direction=Vector3.LEFT
	await _frames(45)
	world.player.automatic_direction=Vector3.ZERO
	_check(world.player.global_position.x>SITE.CABIN_POSITION.x-.65 and world.player.global_position.y<.2,"cabin walking stops beside the cot without climbing onto it")
	if not await _walk(world.player,cabin.interaction,3.0): _finish(1); return
	_check(session.save_game(),"actual save flow captures world state in no-save mode")
	var saved: Dictionary=session.state.snapshot()
	path=FIXTURE.write_fixture(folder,"collected.json",saved)
	if not _check(not path.is_empty() and not STORE.read_valid(path).is_empty(),"full native GameState/SaveStore validates isolated persisted secrets"):
		_finish(1); return
	_stop_temporal()
	world.queue_free()
	await _frames(4)
	if not await _load_world(): _finish(1); return
	session=world.session
	_check(SECRET.collected(session.state.world_state,SITE.HOUSE_ID) and SECRET.collected(session.state.world_state,SITE.CABIN_ID),"cold Main reload restores both collected flags")
	_check(session.state.economy.balance==final_balance,"cold reload preserves the settled reward and achievement balance")
	await _input("interact")
	_check(session.state.economy.balance==final_balance,"real interaction after reload does not pay again")
	world.player.controlled_automatically=true
	world.player.speed=3.0
	for point in [Vector3(-1331,0,-1714),Vector3(-1325,0,-1712),Vector3(-1314,0,-1710),SITE.POSITION+Vector3(0,0,6)]:
		if not await _walk(world.player,point,8.0): _finish(1); return
	await _npc_and_depth()
	_finish(0 if failures.is_empty() else 1)

func _load_world() -> bool:
	root.get_node("V2Launch").selected_path=path
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path and world.production.no_save,"Main uses only the isolated fixture"):
		return false
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not _check(world.dispatch.router._native!=null and world.production.requested_population==20,"native C# routing and population20 active"): return false
	return _check(world.session.desert.get("frontier")!=null,"frontier runtime integrated")

func _walk(actor: CharacterBody3D, target: Vector3, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		var offset := target-actor.global_position
		offset.y=0
		if offset.length()<.14:
			actor.automatic_direction=Vector3.ZERO
			return _check(actor.is_on_floor() and absf(actor.global_position.y)<.2,"physical walking reaches "+str(target))
		actor.automatic_direction=offset.normalized()
		await physics_frame
	actor.automatic_direction=Vector3.ZERO
	return _check(false,"walking obstructed toward %s; actual=%s"%[target,actor.global_position])

func _input(action: String) -> void:
	for pressed in [true,false]:
		var event := InputEventAction.new()
		event.action=action
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await _frames(2)

func _npc_and_depth() -> void:
	var npc := ACTOR.new()
	npc.controlled_automatically=true
	npc.speed=2.8
	npc.position=SITE.POSITION+Vector3(.65,.05,5.3)
	world.add_child(npc)
	await _frames(3)
	await _walk(npc,SITE.POSITION+Vector3(.65,0,.2),5.0)
	await _walk(npc,SITE.POSITION+Vector3(1.05,0,-.8),4.0)
	_check(npc.test_move(npc.global_transform,Vector3(5,0,0)),"real NPC full-body sweep blocked by table")
	_check(world.player.global_position.distance_to(npc.global_position)>1,"player and visiting NPC coexist at separate supported positions")
	npc.queue_free()
	await _frames(2)
	var cabin_npc := ACTOR.new()
	cabin_npc.controlled_automatically=true
	cabin_npc.speed=2.8
	cabin_npc.position=SITE.CABIN_POSITION+Vector3(4,.05,0)
	world.add_child(cabin_npc)
	await _frames(3)
	await _walk(cabin_npc,SITE.CABIN_POSITION+Vector3(.4,0,.45),4.0)
	_check(cabin_npc.test_move(cabin_npc.global_transform,Vector3(-3,0,0)),"cabin cot blocks a real NPC full-body sweep")
	await _walk(cabin_npc,SITE.CABIN_POSITION+Vector3(4,0,0),4.0)
	cabin_npc.queue_free()
	await _frames(2)
	var site := world.find_child("DesertAbandonedSite",true,false) as Node3D
	if not _check(is_instance_valid(site),"streamed ruin meshes exist for rendered depth"): return
	var camera := root.get_camera_3d()
	var prior_transform := camera.global_transform
	var prior_processing := camera.is_processing()
	camera.set_process(false)
	camera.global_position=SITE.POSITION+Vector3(0,25.3,25.3)
	camera.look_at(SITE.POSITION+Vector3(0,.7,0))
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var areas := [
		{"id":"house","origin":SITE.POSITION,"natural":Vector3(0,.04,.2),"poses":[{"id":"doorway","point":Vector3(0,.04,3.0),"occluded":false},{"id":"beneath-porch-roof","point":Vector3(-2.0,.04,2.85),"occluded":true,"full_occlusion":true},{"id":"behind-broken-wall","point":Vector3(2.0,.04,2.85),"occluded":true},{"id":"beside-table","point":Vector3(1.05,.04,-.8),"occluded":false}]},
		{"id":"cabin","origin":SITE.CABIN_POSITION,"natural":Vector3(.4,.04,.45),"poses":[{"id":"doorway","point":Vector3(2.2,.04,0),"occluded":false},{"id":"behind-broken-wall","point":Vector3(-.4,.04,1.35),"occluded":true},{"id":"beneath-rafter","point":Vector3(-.4,.04,.45),"occluded":true},{"id":"beside-cot-clear","point":Vector3(1.35,.04,.45),"occluded":false}]},
	]
	for area in areas:
		var origin: Vector3=area.origin
		camera.global_position=origin+Vector3(0,25.3,25.3)
		camera.look_at(origin+Vector3(0,.7,0))
		for player in [true,false]:
			var actor := ACTOR.new()
			actor.is_player=player
			actor.controlled_automatically=true
			actor.position=origin+Vector3(area.natural)
			world.add_child(actor)
			actor.set_physics_process(false)
			actor.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
			await _frames(2)
			var who := "player" if player else "npc"
			(await _capture()).save_png(folder.path_join(str(area.id)+"-"+who+"-natural.png"))
			_mask_meshes(actor,diagnostic)
			for setup in area.poses:
				actor.position=origin+Vector3(setup.point)
				actor.reset_physics_interpolation()
				var actual := await _capture()
				site.hide()
				var control := await _capture()
				site.show()
				var visible := _mask_count(actual)
				var positive := _mask_count(control)
				var ratio := float(visible)/maxi(1,positive)
				var label := "%s-%s-%s"%[area.id,who,setup.id]
				_check(positive>100,label+" positive actor control")
				var expected_depth: bool=ratio<.15 if bool(setup.get("full_occlusion",false)) else (ratio>.05 and ratio<.97 if setup.occluded else ratio>.85)
				_check(expected_depth,label+" native depth ratio="+str(ratio))
				depth.append({"area":area.id,"actor":who,"pose":setup.id,"visible":visible,"control":positive,"ratio":ratio})
				actual.save_png(folder.path_join(label+".png"))
				control.save_png(folder.path_join(label+"-control.png"))
			actor.free()
	camera.global_transform=prior_transform
	camera.set_process(prior_processing)

func _capture() -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _mask_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override=material
		node.material_overlay=null
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _mask_meshes(child,material)

func _mask_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.r>.55 and color.b>.55 and color.g<.2: count+=1
	return count

func _check_receipt(economy: RefCounted, id: String, amount: int) -> void:
	var receipt: Dictionary=RECEIPTS.lookup(economy.snapshot(),"reward",id)
	_check(receipt.get("kind","")=="reward" and receipt.get("item","")==id and int(receipt.get("amount",-1))==amount,"exact native receipt "+id+" amount="+str(amount))
	if id.begins_with("achievement:"):
		_check(id.trim_prefix("achievement:") in economy.snapshot().achievements,"earned achievement accompanies its reward receipt: "+id)

func _begin_temporal() -> bool:
	temporal=load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(temporal)
	if not _check(temporal.begin(world,world.session.desert.drag,folder.path_join("sequence"),3600),"daytime ruin temporal capture starts, cap30 and max3600 frames"): return false
	temporal.segment="ruins_first_visit_day"
	temporal._report["clock_control"]="Initial isolated checkpoint clear daytime0.45, normal production clock"
	temporal._report["coverage"]="Continuous first-visit house/cabin walking, real collectible interactions and solid probes under the normal exterior camera, ending before cold reload"
	temporal._report["not_covered"]=["night","combat","cold reload","diagnostic depth poses","performance"]
	return true

func _stop_temporal() -> void:
	if not is_instance_valid(temporal) or not temporal_report.is_empty(): return
	var report: Dictionary=temporal.stop()
	temporal_report={"path":str(temporal.output).path_join("sequence.json"),"frames":int(report.get("frame_count",0)),"duration_seconds":float(report.get("duration_seconds",0)),"failure":str(report.get("failure","")),"not_a_performance_benchmark":true}
	_check(str(temporal_report.failure).is_empty() and int(temporal_report.frames)>0,"daytime ruin sequence closes before reload without capture errors")

func _finish(code: int) -> void:
	_stop_temporal()
	if not old_launch_path.is_empty(): root.get_node("V2Launch").selected_path=old_launch_path
	if not folder.is_empty():
		var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"depth":depth,"temporal":temporal_report,"combat_scope":"pre-defeated bandits fixture; no combat coverage","persistence_scope":"FullSession captures no-save state; isolated explicit full GameState files cold-loaded by Main","performance":"not measured"},"\t"))
	print("DESERT_SECRETS checks=%d failures=%d evidence=%s"%[checks,failures.size(),folder])
	quit(code)
