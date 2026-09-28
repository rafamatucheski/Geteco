extends SceneTree
const STATE := preload("res://gameplay/urban_v1/PortContainerState.gd")
const WALLET := preload("res://systems/economy/Economy.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var wallet := WALLET.new()
	check(not wallet.purchase("supply","lockpick","no_cash").ok,"No purchase without funds")
	wallet.grant_reward("fixture",300)
	check(wallet.purchase("supply","lockpick","first").ok,"Purchase lockpick")
	check(wallet.balance == 225 and wallet.inventory.lockpick == 1,"One charge, one tool")
	check(wallet.purchase("supply","lockpick","first").ok and wallet.inventory.lockpick == 1 and wallet.balance == 225,"Receipt retry never duplicates tools")
	check(wallet.purchase("supply","lockpick","second").ok and wallet.inventory.lockpick == 2,"Tools stack")
	check(wallet.consume_item("lockpick") and wallet.inventory.lockpick == 1,"Failure consumes exactly one")
	var restored := WALLET.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(wallet.snapshot()))),"Supply receipts restore from JSON")
	check(restored.inventory.lockpick == 1 and restored.balance == 150,"Restored count and money")
	check(restored.consume_item("lockpick") and not restored.consume_item("lockpick"),"No negative count")
	check(WALLET.new().restore_snapshot(restored.snapshot()),"Consumed supplies do not invalidate receipts")
	wallet.grant_item("lockpick",998)
	check(not wallet.purchase("supply","lockpick","full").ok and wallet.balance == 150,"Capacity rejection is atomic")
	var ids := STATE.known_ids()
	check(ids.size() == 18,"Eighteen authored ground containers, no upper levels")
	var rows := {ids[0]:{"opened":true,"looted":true},ids[1]:{"opened":true,"looted":false}}
	check(STATE.validate_snapshot(JSON.parse_string(JSON.stringify(rows))),"Cargo state JSON roundtrip")
	check(not STATE.validate_snapshot({ids[0]:{"opened":false,"looted":true}}),"Locked cargo cannot be looted")
	check(not STATE.validate_snapshot({"upper_container":{"opened":true,"looted":false}}),"Unknown and upper cargo IDs rejected")
	check(not STATE.validate_snapshot({ids[0]:{"opened":1,"looted":false}}),"Malformed cargo rejected")
	var kinds := {}
	for id in ids:
		check(STATE.loot(id) == STATE.loot(id),"Loot stable for "+id)
		kinds[STATE.loot(id).kind] = true
	check(kinds.size() == 5,"Cash, ammunition, weapons, armor and empty containers")
	for cycle in 6:
		check(STATE.loot(ids[0],cycle) != STATE.loot(ids[0],cycle+1),"Restocking changes the reward")
	check(STATE.receipt(ids[0],0) == "container_loot:"+ids[0],"Legacy receipt remains valid")
	check(STATE.receipt(ids[0],1) != STATE.receipt(ids[0],0),"New delivery has a separate receipt")
	var modern := {ids[0]:{"opened":false,"looted":false,"cycle":2,"elapsed":0.0}}
	check(STATE.validate_snapshot(JSON.parse_string(JSON.stringify(modern))),"Restocked state survives JSON")
	for bad in [-1,1.5,STATE.MAX_CYCLE+1,INF]:
		modern[ids[0]].cycle = bad
		check(not STATE.validate_snapshot(modern),"Reject malformed delivery cycle")
	modern[ids[0]].cycle = 1
	modern[ids[0]].elapsed = STATE.RESTOCK_SECONDS+1
	check(not STATE.validate_snapshot(modern),"Reject invalid timer")
	var state := preload("res://runtime/GameState.gd").new()
	var snapshot := state.snapshot()
	snapshot.world.port_containers = rows
	check(state.restore_snapshot(snapshot),"Full GameState accepts cargo state")
	var before := state.snapshot()
	snapshot.world.port_containers = {ids[0]:{"opened":false,"looted":true}}
	check(not state.restore_snapshot(snapshot) and state.snapshot() == before,"Invalid cargo rejects whole save without mutation")
	print("PORT_CONTAINER_STATE: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
