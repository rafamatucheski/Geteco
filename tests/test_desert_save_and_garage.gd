extends SceneTree
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const CONTRACT := preload("res://runtime/desert/DesertSaveContract.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
var checks:=0
var failures:=0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(message)
func _initialize() -> void:
	var world: Dictionary={}
	var wallet:=ECONOMY.new()
	wallet.grant_reward("desert_fixture",30000)
	check(CONTRACT.valid(world,wallet.snapshot()),"Legacy saves need no desert keys")
	check(not STORY.mark(world,"delivered"),"Cannot manufacture final proof")
	check(STORY.mark(world,"arrived") and STORY.mark(world,"met_vicente"),"Arrival then real meeting unlock investigation")
	check(not STORY.mark(world,"bank_proof"),"Bank evidence requires physical cargo clue")
	check(STORY.mark(world,"cargo_found") and STORY.mark(world,"bank_proof"),"Cargo and bank prove ordered investigation")
	check(not STORY.mark(world,"delivered"),"Jessica encounter remains required")
	check(STORY.mark(world,"jessica_met") and STORY.mark(world,"delivered"),"Act two reaches final confrontation")
	var before:=wallet.balance
	check(not GARAGE.buy(world,wallet,"test_car","desert_faisca","turbo_large",0).ok,"Locked part cannot be bought")
	check(wallet.balance==before,"Rejected purchase leaves balance untouched")
	check(GARAGE.buy(world,wallet,"test_car","desert_faisca","gear_short",1).ok,"Earned part bought")
	check(wallet.balance==before-2100,"Correct amount charged")
	check(GARAGE.buy(world,wallet,"test_car","desert_faisca","gear_short",1).ok and wallet.balance==before-2100,"Owned reinstall does not charge twice")
	check(GARAGE.valid(GARAGE.data(world),wallet.snapshot()),"Parts and wallet receipts agree")
	check(GARAGE.vehicle(world,"second_car","desert_faisca").parts.is_empty(),"Tuning belongs to vehicle identity")
	var bad:=GARAGE.data(world)
	bad.vehicles.test_car.parts.turbo="turbo_large"
	check(not GARAGE.valid(bad,wallet.snapshot()),"Unpurchased installation rejected")
	bad=GARAGE.data(world)
	bad.vehicles.test_car.presets.drag={"tires":"turbo_large"}
	check(not GARAGE.valid(bad,wallet.snapshot()),"Invalid slot in saved preset rejected")
	var race_result:=RACE.record_finish(world,"digo",false,21)
	check(race_result.finished and not race_result.won,"Digo completion can lose")
	DIGO.complete_desert_race(world,DIGO.DESERT_RACE_ID,true)
	check(DIGO.workshop_unlocked(world),"Digo friendship unlocked on a completed loss")
	check(CONTRACT.valid(world,wallet.snapshot()),"Completed loss has no fake prize receipt")
	race_result=RACE.record_finish(world,"digo",true,20)
	check(CONTRACT.valid(world,wallet.snapshot()) and "digo" in RACE.pending_rewards(world,wallet.snapshot()),"Unpaid victory remains a valid pending prize")
	wallet.grant_reward("desert_drag:digo",4000)
	check(CONTRACT.valid(world,wallet.snapshot()),"Victory reconciles exactly with wallet")
	var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(world))
	check(CONTRACT.valid(roundtrip,wallet.snapshot()),"JSON round trip preserves new contracts")
	var collection:=GARAGE.defaults()
	var collection_wallet:=ECONOMY.new()
	collection_wallet.grant_reward("style_collection_fixture",1000000)
	for id in preload("res://gameplay/desert_cars/DesertCarCatalog.gd").IDS:
		var spec: Dictionary=preload("res://gameplay/desert_cars/DesertCarCatalog.gd").spec(id)
		check(collection_wallet.spend(int(spec.price),"desert_car:"+id),"Collection purchase records an actual receipt: "+id)
		collection.purchased[id]="desert_owned_"+id
	var restored_collection: Dictionary=JSON.parse_string(JSON.stringify(collection))
	check(GARAGE.valid(restored_collection,collection_wallet.snapshot()),"Full roster including race variants survives JSON and receipt validation")
	restored_collection.purchased["desert_counterfeit"]="desert_owned_desert_counterfeit"
	check(not GARAGE.valid(restored_collection,collection_wallet.snapshot()),"Expanded collection still rejects unknown cars")
	print("DESERT_SAVE_GARAGE checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
