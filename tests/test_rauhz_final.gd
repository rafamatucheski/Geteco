extends SceneTree
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const RACE := preload("res://activities/desert_drag/DesertDrag.gd")
const BOARD := preload("res://activities/desert_drag/DesertDragBoard.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("RAUHZ ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	var state := {}
	check(PROGRESS.RIVALS.back()=="rauhz" and RACE.RIVALS.rauhz.car=="rauhz_focus_mk1","Rauhz and his Focus close the ladder")
	check(not PROGRESS.can_race(state,"rauhz"),"final cannot be entered from a new campaign")
	for rival in ["digo","livia","raul","jessica","nadir"]:
		check(PROGRESS.record_finish(state,"rauhz",true,17).is_empty(),"cannot skip "+rival)
		PROGRESS.record_finish(state,rival,true,20)
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(PROGRESS.data(state)))
	check(PROGRESS.validate_snapshot(legacy) and legacy.version==1,"old five-win save stays valid without resetting history")
	check(PROGRESS.current_rival(state)=="rauhz" and PROGRESS.can_race(state,"nadir"),"old champion unlocks Rauhz and keeps earlier rematches")
	PROGRESS.record_finish(state,"rauhz",false,19)
	check(PROGRESS.current_rival(state)=="rauhz" and PROGRESS.data(state).wins.size()==5,"losing final grants no championship victory")
	var economy := ECONOMY.new()
	check(PROGRESS.claim_rewards(state,economy)==30000,"old first-win rewards retain their values")
	var before: int = economy.balance
	var finish := PROGRESS.record_finish(state,"rauhz",true,16)
	check(finish.first_win and finish.tier==6,"first final victory is tier six")
	check(PROGRESS.claim_rewards(state,economy)==9000 and economy.balance==before+9000,"final pays R$ 9000 once")
	finish = PROGRESS.record_finish(state,"rauhz",true,15.8)
	check(not finish.first_win and PROGRESS.claim_rewards(state,economy)==0,"final rematch never duplicates prize")
	check(PROGRESS.data(state).best.rauhz==15.8 and PROGRESS.data(state).wins.size()==6,"rematch improves time and preserves all six wins")
	var folder := FIXTURE.output_dir("rauhz-contract")
	var snapshot := FIXTURE.full_snapshot(Vector3.ZERO,true)
	snapshot.world.merge(state,true)
	preload("res://systems/campaign/DigoProgress.gd").complete_desert_race(snapshot.world,"digo_desert_race",true)
	# Use a real isolated checkpoint; preserve the fixture's wallet structure.
	snapshot.economy = economy.snapshot()
	var path := FIXTURE.write_fixture(folder,"champion.json",snapshot)
	check(not path.is_empty(),"final victory and wallet pass full save contract and write to disk")
	if not path.is_empty():
		var restored := STORE.read_valid(path)
		check(not restored.is_empty() and restored.world.desert_drag.wins.size()==6,"real disk load retains final victory")
		check(PROGRESS.claim_rewards(restored.world,economy)==0,"loaded final cannot mint another reward")
	var board := BOARD.new()
	root.add_child(board)
	board.show_progress(legacy)
	board.select_rival("rauhz")
	check(board.rows.size()==6 and not board.race_button.disabled,"legacy champion can select final in the real board")
	check(board.rows.back().position.y+board.rows.back().size.y<581,"sixth row clears footer")
	check(board.photos.rauhz!=null and is_equal_approx(board.photos.nadir.region.size.x,float(board.photos.nadir.atlas.get_width())/5.0),"new portrait does not reslice five-person atlas")
	board.show_progress(PROGRESS.data(state),"rauhz")
	check(board.race_button.text.begins_with("REVANCHE"),"final victory exposes rematch")
	var car := VEHICLE.new()
	car.archetype = "rauhz_focus_mk1"
	car.vehicle_id = "rauhz_contract"
	car.paint_color = Color("101817")
	root.add_child(car)
	car.set_physics_process(false)
	check(car.wheels.size()==4 and car._paint.materials.size()>0,"Focus uses real fleet wheels and paint")
	check(RACE.powertrain_profile_for_vehicle(car)=="rauhz_focus_mk1","Focus retains its own drivetrain")
	var driver := preload("res://activities/desert_drag/DesertDragDriver.gd").attach(car,"rauhz")
	check(driver.get_meta("character_identity")=="rauhz" and driver.wardrobe.top==0,"seated Rauhz keeps short-sleeve black t-shirt")
	check(driver.wardrobe.hat==0 and not driver.wardrobe.glasses and driver.wardrobe.beard==1,"reference look has brown hair and light stubble, no hat or glasses")
	check(car.get_node_or_null("DesertCarAudio")!=null,"Focus receives production engine audio")
	car.free()
	board.free()
	print("RAUHZ_DONE checks=",checks," failures=",failures," output=",folder)
	quit(0 if failures.is_empty() else 1)
