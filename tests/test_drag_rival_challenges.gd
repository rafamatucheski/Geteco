extends SceneTree
## Pure drivetrain calibration plus real isolated persistence; physical crossings
## and UI entry are covered separately by the session integration runner.
const PROGRESS := preload("res://activities/desert_drag/DragRivalChallengeProgress.gd")
const CATALOG := preload("res://activities/desert_drag/DragRivalChallengeCatalog.gd")
const TELEMETRY := preload("res://activities/desert_drag/DragRivalChallengeTelemetry.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const CONTRACT := preload("res://runtime/desert/DesertSaveContract.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const GAME := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks+=1
	print("RIVAL_CHALLENGE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func simulate(metres: float, profile := "desert_faisca", parts: Dictionary = {}, ratio := .54, shift := .91) -> Dictionary:
	var drive := DRIVE.new()
	drive.configure(profile,parts)
	drive.race_mode=true
	drive.launch_blend_seconds=.35
	drive.rpm=drive.redline*ratio
	drive.launch()
	var telemetry := TELEMETRY.new()
	telemetry.course=metres
	var elapsed := 0.0
	const DT := 1.0/120.0
	while elapsed<65.0 and drive.distance_m<metres:
		if drive.rpm>=drive.redline*shift: drive.shift_up()
		drive.step(DT,1.0,false)
		telemetry.observe(drive,drive.distance_m,DT)
		elapsed+=DT
	return {"seconds":elapsed,"metrics":telemetry.snapshot()}

func finish(world: Dictionary, rival: String, step: int, profile := "desert_faisca", parts: Dictionary = {}, ratio := .54, shift := .91) -> Dictionary:
	var started := PROGRESS.begin(world,rival,step,"challenge_test_car",profile,profile,parts)
	if not started.get("ok",false): return {}
	var metres := float(CATALOG.goal(rival,step).distance)
	var run := simulate(metres,profile,parts,ratio,shift)
	return PROGRESS.record_finish(world,int(started.entry.id),"challenge_test_car",profile,parts,float(run.seconds),float(run.seconds)-.5,metres,run.metrics)

func _initialize() -> void:
	_fractional_windows()
	var world := {}
	var wallet := ECONOMY.new()
	check(PROGRESS.validate_world(world,wallet.snapshot()) and world.is_empty(),"old saves require no new state")
	check(not PROGRESS.begin(world,"rauhz",0,"v","desert_faisca","desert_faisca",{}).ok,"challenge chain cannot skip to its final rival")
	check(not TUNING.purchase_check({},[],"rival_digo_ecu",99,999999).ok,"money and ranked wins cannot buy an unearned exclusive part")
	var bad_run := finish(world,"digo",0,"desert_faisca",{},.95)
	check(not bad_run.is_empty() and not bad_run.challenge_success and PROGRESS.status(world,"digo").stamps==0,"poor launch can finish without advancing proof")
	check(not world.has("desert_drag") and not world.has("desert_garage"),"failed workshop proof does not create ranked wins or a gift")
	var successful_world := {}
	for profile in ["desert_faisca","metro_hatch","sedan_classic"]:
		var calibration := {}
		for rival in CATALOG.IDS:
			for step in 2:
				var result := finish(calibration,rival,step,profile)
				check(result.get("challenge_success",false),"stock %s can complete %s proof %d without its own prize"%[profile,rival,step+1])
				if result.is_empty(): print("CALIBRATION_INVALID ",profile," ",rival," ",step)
				else: print("CALIBRATION ",profile," ",rival," ",step," ",result.challenge_detail," ",result.challenge_metrics)
				if profile=="desert_faisca" and rival=="jessica" and step==0: _persistence(calibration,wallet)
			check(PROGRESS.validate_world(calibration,wallet.snapshot()),"calibration ledger stays valid after "+profile+" / "+rival)
		if profile=="desert_faisca": successful_world=calibration
	check(CONTRACT.valid(successful_world,wallet.snapshot()) and GARAGE.valid(GARAGE.data(successful_world),wallet.snapshot()),"six real exclusive gifts reconcile with the complete save contract")
	check(not successful_world.has("desert_drag") and not successful_world.has("digo"),"full challenge chain neither advances campaign nor ranked rivals")
	for rival in CATALOG.IDS:
		var part := str(CATALOG.RIVALS[rival].part)
		var record := GARAGE.vehicle(successful_world,"challenge_test_car","desert_faisca")
		check(part in record.owned and GARAGE.buy(successful_world,wallet,"challenge_test_car","desert_faisca",part,0).ok,"earned part is owned and installable with zero cash: "+rival)
		check(PROGRESS.grant_part(successful_world,rival,"second_car","sedan_classic"),"mastery delivers a free copy to another car: "+rival)
		check(not PROGRESS.grant_part(successful_world,rival,"second_car","sedan_classic"),"duplicate gift cannot duplicate ownership: "+rival)
	check(CONTRACT.valid(successful_world,wallet.snapshot()),"reinstalled gifts and second-car copies remain valid")
	_persistence(successful_world,wallet)
	_retries(successful_world,wallet)
	_corruption(successful_world,wallet)
	print("RIVAL_CHALLENGES_DONE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _fractional_windows() -> void:
	var drive := DRIVE.new()
	drive.configure("desert_faisca",{})
	var telemetry := TELEMETRY.new()
	telemetry.observe(drive,790.0,.1)
	drive.limiter=true
	telemetry.observe(drive,810.0,.2)
	check(is_equal_approx(telemetry.limiter_seconds,.1) and is_equal_approx(telemetry.late_limiter_seconds,.1),"finish clipping counts the same actual limiter time in the final window")
	var elapsed := telemetry.observed_seconds
	telemetry.observe(drive,830.0,.2)
	check(is_equal_approx(telemetry.observed_seconds,elapsed),"post-finish braking cannot change challenge observations")
	var launch := TELEMETRY.new()
	drive.wheelspin=1.0
	launch.observe(drive,0.0,.2)
	check(is_equal_approx(launch.first60_seconds,.2) and is_equal_approx(launch.spin60_seconds,.2),"wheelspin while stationary still counts in the opening sixty metres")

func _retries(world: Dictionary, wallet) -> void:
	var reference: Dictionary=PROGRESS.data(world).reference
	check(not PROGRESS.begin(world,"jessica",1,"another_car","desert_faisca","desert_faisca",{}).ok,"Jessica rejects replacing the reference car")
	check(not PROGRESS.begin(world,"jessica",1,"challenge_test_car","desert_faisca","desert_faisca",{"gearbox":"gear_short"}).ok,"Jessica rejects a changed mechanical preparation")
	var begun := PROGRESS.begin(world,"jessica",1,"challenge_test_car","desert_faisca","desert_faisca",{"paint":"paint_pearl"})
	check(begun.ok,"cosmetics do not invalidate a reference")
	check(PROGRESS.cancel(world) and PROGRESS.data(world).reference==reference,"cancel preserves the durable reference and prior proofs")
	var run := simulate(201)
	for iteration in 7:
		begun=PROGRESS.begin(world,"digo",0,"challenge_test_car","desert_faisca","desert_faisca",{})
		var before := world.duplicate(true)
		check(PROGRESS.record_finish(world,int(begun.entry.id),"other_car","desert_faisca",{},float(run.seconds),12,201,run.metrics).is_empty() and world==before,"wrong car cannot settle a registered proof")
		var seconds := float(run.seconds)-.1*(iteration+1)
		var result := PROGRESS.record_finish(world,int(begun.entry.id),"challenge_test_car","desert_faisca",{},seconds,seconds-.5,201,run.metrics)
		check(result.get("challenge_success",false) and not result.get("won",true),"workshop objective can succeed during a lost race")
		check(PROGRESS.record_finish(world,int(begun.entry.id),"challenge_test_car","desert_faisca",{},seconds,20,201,run.metrics).is_empty(),"duplicate completion is ignored")
	check(int(PROGRESS.data(world).bonuses.digo)==5,"record bonuses stop after the authored five even when records improve")
	check(PROGRESS.claim_rewards(world,wallet)==1000 and PROGRESS.claim_rewards(world,wallet)==0,"five bonuses pay once through real Economy receipts")
	check(PROGRESS.pending_reward(world,wallet.snapshot())==0 and CONTRACT.valid(world,wallet.snapshot()),"record bonus ledger and wallet agree after settlement")
	var full := ECONOMY.new()
	full.grant_reward("rival_capacity_fixture",ECONOMY.LIMIT)
	check(PROGRESS.claim_rewards(world,full)==0 and PROGRESS.pending_reward(world,full.snapshot())==1000,"full wallet leaves all bonuses pending")
	full.spend(200,"rival_capacity_space")
	check(PROGRESS.claim_rewards(world,full)==200 and PROGRESS.pending_reward(world,full.snapshot())==800,"partial capacity settles one exact bonus and keeps the rest")

func _persistence(world: Dictionary, wallet) -> void:
	var game := GAME.new()
	check(game.restore_snapshot(FIXTURE.full_snapshot(Vector3.ZERO,true)),"production save fixture restores")
	game.world_state.merge(world,true)
	game.economy.restore_snapshot(wallet.snapshot())
	var store := STORE.new()
	store.path=FIXTURE.output_dir("drag-rival-save").path_join("progress.json")
	check(store.save(game)==OK,"real isolated SaveStore writes reference, gifts and records")
	var restored := GAME.new()
	check(store.load_into(restored).get("ok",false),"real SaveStore reloads rival progression")
	check(restored.world_state[PROGRESS.KEY]==JSON.parse_string(JSON.stringify(world[PROGRESS.KEY])),"JSON round trip preserves all challenge proof provenance")
	print("RIVAL_SAVE ",ProjectSettings.globalize_path(store.path))

func _corruption(world: Dictionary, wallet) -> void:
	check(not PROGRESS.validate_snapshot("bad"),"invalid challenge root is rejected")
	var forged := world.duplicate(true)
	forged.erase(PROGRESS.KEY)
	check(not CONTRACT.valid(forged,wallet.snapshot()),"exclusive parts without workshop proofs invalidate the save")
	forged=world.duplicate(true)
	forged[PROGRESS.KEY].proofs.digo[0].metrics.launch="PATINOU"
	check(not PROGRESS.validate_world(forged,wallet.snapshot()),"a failed launch cannot be stored as an earned proof")
	forged=world.duplicate(true)
	forged[PROGRESS.KEY].proofs.digo="broken"
	check(not PROGRESS.validate_snapshot(forged[PROGRESS.KEY]),"malformed proof arrays are rejected without throwing")
	forged=world.duplicate(true)
	forged[PROGRESS.KEY].bonuses.digo=6
	check(not PROGRESS.validate_world(forged,wallet.snapshot()),"bonus cap is enforced in persistence")
	var broken_wallet: Dictionary=wallet.snapshot()
	broken_wallet.transactions["reward:drag_rival_record:digo:1"].amount=201
	check(not PROGRESS.validate_world(world,broken_wallet),"changed bonus receipt amount is rejected")
