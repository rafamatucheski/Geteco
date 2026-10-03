extends SceneTree
const ECONOMY := preload("res://systems/economy/Economy.gd")
const STATE := preload("res://runtime/GameState.gd")
const MOTO := preload("res://activities/motocross/MotocrossProgress.gd")
const SKI := preload("res://activities/V1OptionalRewardPolicy.gd")
const COURSES := preload("res://activities/MountainProgression.gd").COURSES
var checks:=0
var failures: Array[String]=[]

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); print("FAIL ",label)

func _base(count: int):
	var wallet=ECONOMY.new()
	var accepted: bool=wallet.grant_reward("funds",1000000) and wallet.grant_weapon("pistol")
	accepted=wallet.spend(1,"old_spend") and accepted
	accepted=wallet.buy_ammo("pistol",1,"old_ammo") and accepted
	accepted=bool(wallet.purchase("supply","lockpick","old_purchase").ok) and accepted
	accepted=bool(wallet.grant_world_reward({"id":"old_world","kind":"cash","amount":10}).ok) and accepted
	for serial in range(5,count): accepted=wallet.grant_reward("opaque_%d"%serial,0) and accepted
	check(accepted and wallet.snapshot().transactions.size()==count and ECONOMY.validate_snapshot(wallet.snapshot()),"valid public-API base%d"%count)
	return wallet

func _clone(data: Dictionary):
	var wallet=ECONOMY.new()
	check(wallet.restore_snapshot(data),"restore capacity control")
	return wallet

func _cap_contract() -> void:
	var wallet=_base(9999)
	var partial: Dictionary=wallet.snapshot()
	check(wallet.spend(1,"last_opaque") and wallet.snapshot().transactions.size()==10000,"9999 admits the10000th exact opaque receipt")
	var full: Dictionary=wallet.snapshot()
	for grid in [false,true]:
		for operation in ["spend","reward","ammo","purchase","world_weapon","world_item"]:
			wallet=_clone(full)
			if grid:
				wallet.enable_grid_inventory()
				check(wallet.grid_equip_bag("backpack"),"grid control has room for weapon/item before receipt check")
			var before: Dictionary=wallet.snapshot()
			check(ECONOMY.validate_snapshot(before),"control inventory remains valid")
			var accepted:=false
			var reason:=""
			match operation:
				"spend": accepted=wallet.spend(10,"new_spend")
				"reward": accepted=wallet.grant_reward("new_reward",10)
				"ammo": accepted=wallet.buy_ammo("pistol",1,"new_ammo")
				"purchase":
					var result: Dictionary=wallet.purchase("supply","lockpick","new_purchase")
					accepted=bool(result.ok); reason=str(result.reason)
				"world_weapon": accepted=bool(wallet.grant_world_reward({"id":"new_world_weapon","kind":"weapon","item":"shotgun","ammo":20}).ok)
				"world_item": accepted=bool(wallet.grant_world_reward({"id":"new_world_item","kind":"item","item":"lockpick","amount":1}).ok)
			check(not accepted and wallet.snapshot()==before,"full ledger refuses atomically: %s grid=%s"%[operation,str(grid)])
			if operation=="purchase": check(reason=="receipt_limit","purchase reports receipt capacity rather than funds")
			check(ECONOMY.validate_snapshot(wallet.snapshot()),"refused state remains restorable")
	var room=_clone(partial); room.enable_grid_inventory()
	check(room.grid_equip_bag("backpack") and bool(room.grant_world_reward({"id":"new_world_weapon","kind":"weapon","item":"shotgun","ammo":20}).ok),"same world weapon and grid succeed with one receipt slot")
	wallet=_clone(full)
	check(wallet.spend(1,"old_spend") and not wallet.spend(2,"old_spend"),"old spend retry and conflict at cap")
	check(wallet.buy_ammo("pistol",1,"old_ammo") and not wallet.buy_ammo("pistol",2,"old_ammo"),"old ammo retry and conflict at cap")
	check(bool(wallet.purchase("supply","lockpick","old_purchase").ok) and not bool(wallet.purchase("weapon","pistol","old_purchase").ok),"old purchase retry and conflict at cap")
	check(not wallet.grant_reward("funds",1000000),"old reward remains once only at cap")
	check(wallet.grant_world_reward({"id":"old_world","kind":"cash","amount":10}).get("changed")==false,"world replay succeeds unchanged at cap")
	check(wallet.snapshot()==full,"all old retries leave exact state intact")
	var before: Dictionary=wallet.snapshot()
	check(not wallet.spend(36,"motocross_rental:1") and not wallet.grant_reward("motocross_prize:1",141) and wallet.snapshot()==before,"noncodec amounts refuse intact at opaque cap")
	var progress=MOTO.new()
	check(progress.rent(wallet) and wallet.spend(250,"ski_rental:1") and wallet.spend(100,"northgate_auto:1") and wallet.spend(20,"tonico_drink_1") and wallet.grant_reward("tonico_register_1",180),"all five V2 domains still admit at opaque cap")
	check(progress.begin(wallet,0) and progress.settle(wallet,true)==140,"Moto entry and prize complete at opaque cap")
	for course in COURSES:
		var data: Dictionary=wallet.snapshot()
		var settlement: Dictionary=SKI.ski_settlement(course,COURSES[course],100.0,null,data.transactions,data.get("receipt_ledger",{}))
		check(SKI.apply_ski_settlement(wallet,settlement),"authored Ski finish and record complete at cap")
	check(wallet.snapshot().transactions.size()==10000 and ECONOMY.validate_snapshot(wallet.snapshot()) and MOTO.validate_wallet(progress.snapshot(),wallet.snapshot()),"compact work adds no opaque slots and remains valid")
	var state=STATE.new(); state.economy=wallet; state.world_state.motocross=progress.snapshot()
	check(STATE.new().restore_snapshot(state.snapshot()),"full state cross-contracts valid at cap with V2/V3 history")
	before=wallet.snapshot()
	var generic: Dictionary=SKI.ski_settlement("unknown_course",{"reward":100,"bonus":40},30.0,null,before.transactions)
	check(not SKI.apply_ski_settlement(wallet,generic) and wallet.snapshot()==before,"unknown Ski refuses unchanged when opaque history is full")
	# The guard does not invent byte headroom or broaden nonreceipt dictionaries.
	check(ECONOMY.MAX_OPAQUE_RECEIPTS==10000,"receipt bound unchanged")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	_cap_contract()
	var file:=FileAccess.open("user://opaque-receipt-capacity.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t")); file.close()
	print("OPAQUE_RECEIPT_CAPACITY ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
