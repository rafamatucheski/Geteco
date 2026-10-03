extends SceneTree
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var state := STATE.new()
	state.set_location("harbor","harbor_supermarket")
	state.checkpoint_id = "harbor_supermarket"
	state.economy.enable_grid_inventory()
	state.economy.grant_reward("save_fixture",2000)
	check(state.economy.purchase("supply","juice","saved_juice").ok,"buy juice")
	var store := STORE.new()
	store.path = "res://evidence/supermarket-20261002/isolated-save-%d.json"%Time.get_ticks_usec()
	check(store.save(state)==OK,"save new market location and food to isolated disk file")
	var loaded := STATE.new()
	check(store.load_into(loaded).ok,"load isolated file")
	check(loaded.place_id=="harbor_supermarket" and loaded.checkpoint_id=="harbor_supermarket","market location survives disk restore")
	check(loaded.economy.inventory.get("juice",0)==1 and loaded.economy.balance==1986,"food and exact wallet survive disk restore")
	check(loaded.economy.purchase("supply","juice","saved_juice").ok and loaded.economy.inventory.get("juice",0)==1 and loaded.economy.balance==1986,"durable purchase receipt never duplicates")
	print("MARKET_SAVE checks=6 failures=",failures)
	quit(0 if failures.is_empty() else 1)
