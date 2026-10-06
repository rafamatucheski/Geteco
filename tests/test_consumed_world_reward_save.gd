extends SceneTree
## Collected food/drink remains collected after use, with durable grant evidence.
## Disk writes use an isolated evidence path and never the user's progress.json.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
var failures: Array[String]=[]
var checks: int=0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var definition: Dictionary=HOMES.home_data("santa_lua_home_1")
	var stamp: int=Time.get_ticks_usec()
	for reward in definition.rewards:
		if reward.kind!="item": continue
		var item: String=str(reward.item)
		var receipt_key: String="reward:"+str(reward.id)
		var state: STATE=STATE.new()
		state.economy.enable_grid_inventory()
		check(state.economy.grant_world_reward(reward).ok,item+" world reward is granted")
		state.world_state.rewards.append(reward.id)
		check(state.economy.consume_item(item),item+" can be consumed through the real inventory")
		check(int(state.economy.inventory.get(item,0))==0,item+" leaves carried inventory after consumption")
		var store: STORE=STORE.new()
		store.path="res://evidence/desert-village/consumable-save-%d-%s.json"%[stamp,item]
		check(store.save(state)==OK,item+" consumed reward saves to isolated disk")
		var loaded: STATE=STATE.new()
		check(store.load_into(loaded).ok,item+" consumed reward restores from disk")
		check(loaded.world_state.rewards.has(reward.id) and loaded.economy.has_reward_receipt(reward.id),item+" marker and receipt survive together")
		check(int(loaded.economy.inventory.get(item,0))==0,item+" is not recreated by restore")
		var retry: Dictionary=loaded.economy.grant_world_reward(reward)
		check(retry.ok and not retry.changed and int(loaded.economy.inventory.get(item,0))==0,item+" cannot be recollected after consumption/load")

		var consumed: Dictionary=JSON.parse_string(JSON.stringify(state.snapshot()))
		var forged_marker: Dictionary=consumed.duplicate(true)
		forged_marker.economy.transactions.erase(receipt_key)
		var unchanged: Dictionary=loaded.snapshot()
		check(not loaded.restore_snapshot(forged_marker),item+" marker without receipt or item is rejected")
		check(loaded.snapshot()==unchanged,item+" rejected marker leaves current state unchanged")
		for field in ["amount","kind","item"]:
			var malformed: Dictionary=consumed.duplicate(true)
			malformed.economy.transactions[receipt_key][field] = 7 if field=="amount" else "spend" if field=="kind" else "unrelated_reward"
			check(not STATE.new().restore_snapshot(malformed),item+" rejects mismatched receipt "+field)

		var legacy: STATE=STATE.new()
		legacy.economy.enable_grid_inventory()
		check(legacy.economy.grant_item(item),item+" legacy ownership fixture")
		legacy.world_state.rewards.append(reward.id)
		check(STATE.new().restore_snapshot(legacy.snapshot()),item+" older marker plus owned item without receipt stays loadable")
		var invalid_with_item: Dictionary=legacy.snapshot()
		invalid_with_item.economy.transactions[receipt_key]={"kind":"reward","item":reward.id,"amount":7}
		check(not STATE.new().restore_snapshot(invalid_with_item),item+" possession never excuses an invalid receipt")
		var receipt_only: Dictionary=consumed.duplicate(true)
		receipt_only.world.rewards=[]
		check(STATE.new().restore_snapshot(receipt_only),item+" interrupted marker publication stays repairable after consumption")

		var dropped: STATE=STATE.new()
		dropped.economy.enable_grid_inventory()
		check(dropped.economy.grid_equip_bag("backpack"),item+" drop fixture equips backpack")
		check(dropped.economy.grant_world_reward(reward).ok,item+" drop fixture collects legitimate reward")
		dropped.world_state.rewards.append(reward.id)
		var grid: Dictionary=dropped.economy.grid_snapshot()
		var pocket_index: int=-1
		for index in grid.pockets.size():
			if grid.pockets[index].id==item: pocket_index=index; break
		check(pocket_index>=0 and dropped.economy.grid_move("pockets",pocket_index,"storage"),item+" moves into backpack")
		check(dropped.economy.grid_drop_bag("harbor","",Vector3(12,0,15))>0,item+" backpack is dropped through real inventory API")
		check(int(dropped.economy.inventory.get(item,0))==0,item+" dropped item is no longer carried")
		check(STATE.new().restore_snapshot(JSON.parse_string(JSON.stringify(dropped.snapshot()))),item+" receipt and world drop remain valid together")
	print("CONSUMED_WORLD_REWARD_SAVE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
