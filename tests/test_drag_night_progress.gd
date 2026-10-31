extends SceneTree
## As rodadas físicas são cobertas pelo runner integrado. Esta suíte protege a
## série durável, a procedência exata da carteira e o limite real do SaveStore isolado.
const NIGHT := preload("res://activities/desert_drag/DragNightProgress.gd")
const DRAG := preload("res://activities/desert_drag/DesertDragProgress.gd")
const WINS := preload("res://systems/campaign/RaceWins.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const CONTRACT := preload("res://runtime/desert/DesertSaveContract.gd")
const GAME := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DRAG_NIGHT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func pass_run(world: Dictionary, seconds: float, other: float, parts: Dictionary = {}) -> Dictionary:
	var step := NIGHT.next_pass(world)
	if step.is_empty(): return {}
	return NIGHT.record_finish(world,int(step.episode_id),int(step.step),"night_test_car","desert_faisca",parts,seconds,other,float(step.distance))

func _initialize() -> void:
	var world := {}
	var wallet := ECONOMY.new()
	check(NIGHT.validate_world(world,wallet.snapshot()) and world.is_empty(),"old save needs no new key and defaults are read-only")
	check(not NIGHT.validate_snapshot("bad"),"invalid root is rejected safely")
	check(not NIGHT.begin(world,"rauhz","night_test_car","desert_faisca","desert_faisca").get("ok",false),"night cannot bypass the authored rival order")
	check(NIGHT.begin(world,"digo","night_test_car","desert_faisca","desert_faisca").get("ok",false),"first night starts with the current rival")
	var first_id := int(NIGHT.next_pass(world).episode_id)
	check(NIGHT.next_pass(world).distance==201.0 and NIGHT.next_pass(world).round==1,"night starts at the 201 m departure")
	var before := world.duplicate(true)
	check(not NIGHT.begin(world,"digo","night_test_car","desert_faisca","desert_faisca").get("ok",false) and world==before,"starting another night cannot overwrite the current episode")
	for seconds in [NAN,INF,-1.0,0.0,66.0]:
		check(NIGHT.record_finish(world,first_id,0,"night_test_car","desert_faisca",{},seconds,12.0,201.0).is_empty(),"invalid timed finish does not advance")
	check(NIGHT.record_finish(world,first_id,1,"night_test_car","desert_faisca",{},11,12,402).is_empty(),"out-of-order callback is rejected")
	check(NIGHT.record_finish(world,first_id,0,"other_car","desert_faisca",{},11,12,201).is_empty(),"another vehicle cannot complete this entry")
	check(NIGHT.record_finish(world,first_id,0,"night_test_car","desert_coyote",{},11,12,201).is_empty(),"another mechanical profile cannot complete this entry")
	check(NIGHT.record_finish(world,first_id,0,"night_test_car","desert_faisca",{},11,12,800).is_empty() and world==before,"wrong physical distance is rejected without mutation")
	var result := pass_run(world,11,12)
	check(result.get("night",false) and result.get("night_points",0)==1 and not result.get("night_done",true),"first physical win earns one point, no completed-night reward")
	check(NIGHT.claim_rewards(world,wallet)==0 and WINS.count(world,{})==0,"partial night cannot pay or grant upgrade merit")
	before=world.duplicate(true)
	check(NIGHT.record_finish(world,first_id,0,"night_test_car","desert_faisca",{},11,12,201).is_empty() and world==before,"duplicate finish callback is idempotent")
	check(NIGHT.next_pass(world).distance==402.0 and NIGHT.next_pass(world).round==2,"second physical pass begins the 402 m pair")
	result=pass_run(world,17,16)
	check(result.night_points==1 and NIGHT.next_pass(world).round==2,"first 402 m pass alone does not award that round")
	_persistence(world,wallet)
	var loaded_world: Dictionary=JSON.parse_string(JSON.stringify(world))
	check(NIGHT.validate_world(loaded_world,wallet.snapshot()) and NIGHT.next_pass(loaded_world).step==2,"JSON restores the second 402 m pass")
	check(pass_run(loaded_world,16,17,{"gearbox":"gear_short"}).is_empty(),"second 402 m pass cannot silently change its preparation")
	result=pass_run(loaded_world,15.8,16.5)
	check(result.night_points==2 and is_equal_approx(float(result.night_consistency),1.2),"best of both 402 m passes decides the round; consistency remains visible")
	check(NIGHT.next_pass(loaded_world).distance==800.0 and NIGHT.next_pass(loaded_world).round==3,"final challenge is 800 m")
	result=pass_run(loaded_world,27,26)
	check(result.night_done and result.night_won and result.night_points==2,"two of three points win the full night despite losing the final pass")
	check(not loaded_world.has("desert_drag") and WINS.count(loaded_world,{})==1,"night merit does not manufacture a ranked rival win")
	check(NIGHT.data(loaded_world).finishes==1 and NIGHT.data(loaded_world).wins==1,"one completed episode increments exact counters once")
	check(NIGHT.claim_rewards(loaded_world,wallet)==900 and wallet.balance==900,"completion and victory pay 600 plus 300 through actual receipts")
	check(NIGHT.claim_rewards(loaded_world,wallet)==0 and wallet.balance==900,"reward retry cannot pay twice")
	before=loaded_world.duplicate(true)
	check(NIGHT.record_finish(loaded_world,first_id,3,"night_test_car","desert_faisca",{},27,26,800).is_empty() and loaded_world==before,"completed episode rejects replayed final callback")
	check(NIGHT.validate_world(loaded_world,wallet.snapshot()) and CONTRACT.valid(loaded_world,wallet.snapshot()),"night ledger and shared desert contract agree")
	check(NIGHT.record_key("desert_faisca",{},201)==NIGHT.record_key("desert_faisca",{"paint":"paint_pearl"},201),"paint does not fragment mechanical records")
	check(NIGHT.record_key("desert_faisca",{},201)!=NIGHT.record_key("desert_faisca",{"gearbox":"gear_short"},201),"different gearing has its own honest record")
	check(NIGHT.begin(loaded_world,"digo","night_test_car","desert_faisca","desert_faisca").ok and int(NIGHT.next_pass(loaded_world).episode_id)>first_id,"new night uses a monotonic episode identity")
	for i in 4: result=pass_run(loaded_world,30+i,20+i)
	check(result.night_done and not result.night_won and NIGHT.data(loaded_world).wins==1,"losing all three proofs grants no new victory")
	check(NIGHT.claim_rewards(loaded_world,wallet)==600 and wallet.balance==1500,"lost completed night still earns the completion amount")
	check(WINS.count(loaded_world,{})==1,"repeating the event never farms more distinct upgrade merits")
	for id in DRAG.RIVALS: DRAG.record_finish(loaded_world,id,true,25)
	DIGO.complete_desert_race(loaded_world,DIGO.DESERT_RACE_ID,true)
	check(WINS.count(loaded_world,{})==7 and TUNING.purchase_check({},[],"nitro_pro",WINS.count(loaded_world,{}),10000).ok,"six real ranked wins plus a won night unlock nitro without a campaign race")
	check(CONTRACT.valid(loaded_world,wallet.snapshot()),"old ranked prizes can remain pending alongside the new paid night")
	_pending_wallet()
	_corruption(loaded_world,wallet)
	print("DRAG_NIGHT_PROGRESS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _persistence(world: Dictionary, wallet) -> void:
	var game := GAME.new()
	check(game.restore_snapshot(FIXTURE.full_snapshot(Vector3.ZERO,true)),"isolated production save fixture is accepted")
	game.world_state.merge(world,true)
	check(game.economy.restore_snapshot(wallet.snapshot()),"test wallet enters real GameState")
	var folder := FIXTURE.output_dir("drag-night-save")
	check(not folder.is_empty(),"isolated persistence folder exists")
	if folder.is_empty(): return
	var store := STORE.new()
	store.path=folder.path_join("progress.json")
	check(store.save(game)==OK,"real SaveStore writes a night between passes")
	var restored := GAME.new()
	check(store.load_into(restored).get("ok",false),"real SaveStore restores the night")
	check(NIGHT.next_pass(restored.world_state).get("step",-1)==2,"disk restoration resumes the second 402 m pass")
	var expected_json: Dictionary=JSON.parse_string(JSON.stringify(world.get(NIGHT.KEY,{})))
	check(typeof(world[NIGHT.KEY].version)==TYPE_INT and typeof(restored.world_state[NIGHT.KEY].version)==TYPE_FLOAT,"JSON represents persisted numeric counters as floats")
	check(restored.world_state.get(NIGHT.KEY,{})==expected_json,"disk roundtrip keeps the entire serialized car, results and record provenance")
	print("DRAG_NIGHT_SAVE ",ProjectSettings.globalize_path(store.path))

func _pending_wallet() -> void:
	var world := {}
	var wallet := ECONOMY.new()
	wallet.grant_reward("night_capacity_fixture",ECONOMY.LIMIT)
	NIGHT.begin(world,"digo","night_test_car","desert_faisca","desert_faisca")
	for i in 4: pass_run(world,12+i,15+i)
	check(NIGHT.claim_rewards(world,wallet)==0 and NIGHT.validate_world(world,wallet.snapshot()),"full wallet leaves earned night rewards durably pending")
	wallet.spend(300,"night_capacity_bonus_space")
	check(NIGHT.claim_rewards(world,wallet)==300 and NIGHT.pending_reward_amount(world,wallet.snapshot())==600,"partial settlement reports the exact remaining completion reward")
	wallet.spend(600,"night_capacity_space")
	check(NIGHT.claim_rewards(world,wallet)==600 and NIGHT.claim_rewards(world,wallet)==0 and NIGHT.pending_reward_amount(world,wallet.snapshot())==0,"pending rewards recover exactly once after space exists")
	check(NIGHT.begin(world,"digo","night_test_car","desert_faisca","desert_faisca").ok,"another episode can begin after settlement")
	var id := int(NIGHT.next_pass(world).episode_id)
	check(NIGHT.abandon(world) and NIGHT.data(world).finishes==1,"abandoning an incomplete episode grants no result or reward")
	NIGHT.begin(world,"digo","night_test_car","desert_faisca","desert_faisca")
	check(int(NIGHT.next_pass(world).episode_id)>id,"abandoned identities are never recycled")

func _corruption(world: Dictionary, wallet) -> void:
	var bad := world.duplicate(true)
	bad[NIGHT.KEY].wins=bad[NIGHT.KEY].finishes+1
	check(not NIGHT.validate_world(bad,wallet.snapshot()),"wins cannot exceed completed episodes")
	bad=world.duplicate(true)
	bad[NIGHT.KEY].last.results[0].distance=800
	check(not NIGHT.validate_world(bad,wallet.snapshot()),"saved episode cannot reorder distances")
	var blocked := {}
	NIGHT.begin(blocked,"digo","night_test_car","desert_faisca","desert_faisca")
	blocked[NIGHT.KEY].current.rival_id="rauhz"
	check(not NIGHT.validate_world(blocked,ECONOMY.new().snapshot()),"saved night cannot manufacture access to a locked rival")
	var forged := ECONOMY.new()
	forged.grant_reward("drag_night_finish:1",599)
	check(not NIGHT.validate_world(world,forged.snapshot()),"wrong reward amount is rejected")
	check(not NIGHT.validate_world({},wallet.snapshot()),"receipt without durable completed-night state is rejected")
