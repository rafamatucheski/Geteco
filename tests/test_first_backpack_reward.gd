extends SceneTree
const CAR = preload("res://runtime/PersonalCar.gd")
const ECONOMY = preload("res://systems/economy/Economy.gd")
const CAMPAIGN = preload("res://systems/campaign/CampaignRuntime.gd")
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	print("BACKPACK ","PASS " if ok else "FAIL ",label)
	if not ok: failures += 1; push_error(label)
func run():
	var economy = ECONOMY.new()
	economy.enable_grid_inventory()
	var campaign = CAMPAIGN.new()
	var car = CAR.new()
	car.session = {"ready_for_play":true,"controller":{"save_invalid":false},"state":{"economy":economy,"campaign":campaign},"field_inventory":null}
	check(not car.award_first_backpack() and economy.grid_snapshot().bag == "","no starting backpack")
	check(campaign.begin("primeiro_giro"),"mission starts")
	for target in ["helena","harbor_parcel","maciota"]:
		var step: Dictionary = campaign.current_step()
		check(bool(campaign.apply_event(step.event,{"target_id":target,"on_foot":true,"unarmed":true}).ok),"mission step "+target)
		if target != "maciota": check(not car.award_first_backpack(),"not awarded before final delivery")
	check(car.award_first_backpack() and economy.grid_snapshot().bag == "backpack","final mission awards backpack without car or trunk")
	check(not car.award_first_backpack(),"award is idempotent")
	var restored = ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(economy.snapshot()))) and restored.grid_snapshot().bag == "backpack" and car.BACKPACK_CLAIM in restored.grid_snapshot().claimed,"JSON save preserves bag and receipt")
	economy.grid_drop_bag("harbor","",Vector3.ZERO)
	check(not car.award_first_backpack() and economy.grid_snapshot().bag == "","dropping bag cannot regrant")
	var legacy: Dictionary = economy.grid_snapshot()
	legacy.claimed.erase(car.BACKPACK_CLAIM)
	economy._data.grid_inventory = legacy
	check(car.award_first_backpack() and economy.grid_snapshot().bag == "" and economy.grid_snapshot().ground.size() == 1,"legacy ground backpack stays recoverable without duplicate")
	economy = ECONOMY.new(); economy.enable_grid_inventory()
	car.session.state.economy = economy
	check(car.award_first_backpack() and economy.grid_snapshot().bag == "backpack","completed legacy save receives missing backpack")
	economy = ECONOMY.new(); economy.enable_grid_inventory(); economy.grid_equip_bag("handbag"); economy.grant_item("apple",3)
	car.session.state.economy = economy
	var before: Dictionary = economy.grid_snapshot()
	check(car.award_first_backpack() and economy.grid_snapshot().bag == "handbag" and economy.grid_snapshot().storage == before.storage and economy.grid_snapshot().pockets == before.pockets,"existing bag and contents preserved")
	car.free()
	print("FIRST_BACKPACK_REWARD checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
