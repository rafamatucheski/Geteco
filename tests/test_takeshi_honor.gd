extends SceneTree
const HONOR := preload("res://runtime/TakeshiHonor.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var state = STATE.new()
	check(STATE.new().restore_snapshot(state.snapshot()),"Legacy fresh state remains valid")
	check(not state.economy.is_weapon_unlocked("katana"),"Katana not sold before Takeshi victory")
	check(not HONOR.claim_state(state,"katana").ok,"No reward before victory")
	check(not HONOR.record_finish(state.world_state,true,NAN).ok,"Invalid finish cannot create reward")
	HONOR.record_finish(state.world_state,false,19.0)
	check(not HONOR.pending_reward(state.world_state),"Losing does not unlock reward")
	HONOR.record_finish(state.world_state,true,13.9)
	check(HONOR.pending_reward(state.world_state),"Winning creates a pending choice")
	check(STATE.new().restore_snapshot(state.snapshot()),"Pending choice survives save/load")
	check(HONOR.claim_state(state,"katana").ok,"Katana can be selected")
	check(state.owns_weapon("katana") and state.equip_weapon("katana"),"Reward is usable")
	check(not HONOR.claim_state(state,"car").ok,"Cannot claim both prizes")
	check(STATE.new().restore_snapshot(state.snapshot()),"Katana reward save is valid")
	check(not HONOR.buy_saber(state,Color.RED).ok,"Insufficient funds do not install saber")
	state.economy.grant_reward("takeshi_test_money",500000)
	check(HONOR.buy_saber(state,Color.RED).ok and state.economy.balance==350000,"Saber costs exactly 150000")
	check(HONOR.buy_saber(state,Color("b833e9")).ok and state.economy.balance==350000,"Subsequent arbitrary colors are free")
	check(HONOR.data(state.world_state).saber_color=="b833e9ff","Selected color persists with opaque blade")
	var output := "res://evidence/takeshi-honor-%d"%OS.get_process_id()
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))==OK,"Isolated save directory writable")
	var store = STORE.new()
	store.path = output.path_join("katana.json")
	check(store.save(state)==OK,"Katana/saber written through real SaveStore")
	var restored = STATE.new()
	var loaded: Dictionary = store.load_into(restored)
	var restored_honor: Dictionary = HONOR.data(restored.world_state)
	# JSON numbers are decoded as floats: compare the persisted meaning, not
	# Dictionary's strict recursive int/float identity.
	check(loaded.ok and restored_honor.reward=="katana" and restored_honor.won and restored_honor.saber_unlocked and restored_honor.saber_color=="b833e9ff" and is_equal_approx(float(restored_honor.best_seconds),13.9),"Actual disk roundtrip preserves reward, best time and color")
	state.set_location("harbor","maciota")
	check(state.equipped_weapon=="fists" and not state.equip_weapon("katana") and not state.can_attack(),"Garage holsters and blocks katana")
	state.set_location("harbor")
	check(state.equip_weapon("katana"),"Katana usable again outside garage")
	var car_state = STATE.new()
	HONOR.record_finish(car_state.world_state,true,13.8)
	var record := {"vehicle_id":HONOR.CAR_ID,"archetype":"supra_a80","region":"desert","position":[-1000.0,.1,-1240.0],"yaw":PI,"health":200.0,"paint":"efeee8ff","equipment":{},"was_driven":false}
	check(HONOR.claim_state(car_state,"car",record).ok,"Car reward creates fleet record")
	check(not car_state.owns_weapon("katana") and car_state.economy.is_weapon_unlocked("katana"),"Choosing Supra unlocks katana shop without gifting it")
	check(STATE.new().restore_snapshot(car_state.snapshot()),"Supra and gifted tuning save valid without fabricated payment")
	car_state.economy.grant_reward("takeshi_car_test_money",450000)
	check(car_state.economy.purchase("weapon","katana","takeshi_purchase_test").ok and car_state.economy.balance==150000,"Shop charges 300000 after Supra choice")
	check(HONOR.buy_saber(car_state,Color.BLUE).ok and car_state.economy.balance==0,"Supra branch also buys saber for 150000")
	store.path = output.path_join("supra.json")
	check(store.save(car_state)==OK,"Supra branch writes actual save")
	check(store.load_into(STATE.new()).ok,"Supra branch actual restore")
	var tampered: Dictionary = car_state.snapshot()
	tampered.world.takeshi.won = false
	check(not STATE.new().restore_snapshot(tampered),"Save cannot claim reward without victory")
	tampered = car_state.snapshot()
	tampered.world.takeshi.saber_color="invalid"
	check(not STATE.new().restore_snapshot(tampered),"Invalid saber color rejected atomically")
	tampered = car_state.snapshot()
	tampered.economy.transactions.erase("spend:takeshi_saber")
	check(not STATE.new().restore_snapshot(tampered),"Saber requires matching paid receipt")
	tampered = car_state.snapshot()
	tampered.world.desert_fleet = "malformed"
	check(not STATE.new().restore_snapshot(tampered),"Malformed fleet rejected without mutation")
	tampered = car_state.snapshot()
	tampered.world.erase("desert_garage")
	check(not STATE.new().restore_snapshot(tampered),"Save cannot silently lose the Supra's gifted tuning")
	var collector = STATE.new()
	collector.economy.grant_reward("takeshi_collection_fixture",10000000)
	collector.world_state.desert_fleet = {}
	collector.world_state.desert_garage = preload("res://runtime/desert/DesertGarageState.gd").defaults()
	for id in preload("res://gameplay/desert_cars/DesertCarCatalog.gd").IDS:
		var spec: Dictionary = preload("res://gameplay/desert_cars/DesertCarCatalog.gd").spec(id)
		if spec.get("race_only",false): continue
		collector.economy.spend(int(spec.price),"desert_car:"+id)
		var fleet_id: String = "desert_owned_"+id
		collector.world_state.desert_garage.purchased[id] = fleet_id
		var saved_car := record.duplicate(true)
		saved_car.archetype = id
		saved_car.vehicle_id = fleet_id
		saved_car.health = 100.0
		collector.world_state.desert_fleet[fleet_id] = saved_car
	HONOR.record_finish(collector.world_state,true,13.8)
	check(HONOR.claim_state(collector,"car",record).ok,"Full purchased collection can also claim Supra")
	check(STATE.new().restore_snapshot(collector.snapshot()),"Catalogue-sized fleet plus prize remains saveable")
	var packed = STATE.new()
	packed.grant_weapon("knife")
	packed.economy.enable_grid_inventory()
	HONOR.record_finish(packed.world_state,true,14.0)
	check(not HONOR.claim_state(packed,"katana").ok and HONOR.pending_reward(packed.world_state) and not packed.owns_weapon("katana"),"No carrying space leaves reward pending and inventory unchanged")
	check(packed.economy.grid_store_weapon("knife","trunk") and HONOR.claim_state(packed,"katana").ok,"Freeing melee slot permits later katana delivery")
	check(STATE.new().restore_snapshot(packed.snapshot()),"Katana and stowed previous weapon both persist")
	print("TAKESHI_HONOR ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures," evidence=",output)
	quit(0 if failures==0 else 1)
