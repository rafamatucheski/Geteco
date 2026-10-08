extends SceneTree
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var world := {}
	check(PROGRESS.validate_snapshot(PROGRESS.data(world)),"existing saves have valid empty drag defaults")
	check(world.is_empty(),"reading defaults does not mutate old save")
	check(not PROGRESS.validate_snapshot(PROGRESS.data({"desert_drag":"corrupt"})),"invalid top-level save type fails safely")
	check(PROGRESS.current_rival(world)=="digo","Digo is first actual opponent")
	check(PROGRESS.record_finish(world,"livia",true,20).is_empty(),"cannot bypass first opponent")
	for invalid in [NAN,INF,-1.0,0.0,66.0]:
		check(PROGRESS.record_finish(world,"digo",true,invalid).is_empty(),"nonfinite or invalid completion rejected")
	var result := PROGRESS.record_finish(world,"digo",false,24.8)
	check(result.finished and not result.won and not result.first_win,"Digo loss remains a completed race")
	check(PROGRESS.data(world).completed_rivals==["digo"],"friendship can reconcile a completed Digo loss")
	check(PROGRESS.current_rival(world)=="digo","loss grants no win upgrade or next opponent")
	result = PROGRESS.record_finish(world,"digo",true,21.7)
	check(result.first_win and result.tier==1,"actual first win identifies one-time reward")
	check(PROGRESS.current_rival(world)=="livia","win opens next opponent")
	result = PROGRESS.record_finish(world,"digo",true,20)
	check(result.finished and not result.first_win,"beaten rival accepts rematch without another first-win reward")
	check(PROGRESS.current_rival(world)=="livia" and PROGRESS.data(world).best.digo==20,"rematch improves record without regressing ladder")
	check(not PROGRESS.can_race(world,"raul") and not PROGRESS.can_race(world,"unknown"),"rematch cannot unlock later or unknown rivals")
	for rival in ["livia","raul","jessica","nadir"]:
		check(not PROGRESS.record_finish(world,rival,true,22).is_empty(),"real result advances ordered rival "+rival)
	result = PROGRESS.record_finish(world,"nadir",true,20)
	check(not result.first_win and result.won,"champion rematch has no duplicate first-win reward")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PROGRESS.data(world)))
	check(PROGRESS.validate_snapshot(saved),"result ledger survives JSON save/load")
	check(saved.best.nadir==20 and saved.finishes==8,"best result updates independently from one-time unlock")
	var economy := ECONOMY.new()
	check(PROGRESS.validate_wallet(saved,economy.snapshot()),"unpaid legitimate wins remain valid pending prizes")
	check(PROGRESS.pending_rewards(world,economy.snapshot()).size()==5,"five first victories produce five pending prizes")
	check(economy.grant_reward("fixture_full",ECONOMY.LIMIT),"isolated full-wallet fixture accepted")
	check(PROGRESS.claim_rewards(world,economy)==0,"full wallet cannot partially over-credit reward")
	check(PROGRESS.validate_wallet(saved,economy.snapshot()) and PROGRESS.pending_rewards(world,economy.snapshot()).size()==5,"failed payment preserves valid save and all pending prizes")
	check(economy.spend(30000,"fixture_space"),"purchase makes space for pending prizes")
	check(PROGRESS.claim_rewards(world,economy)==30000,"all pending first-win prizes settle after space becomes available")
	var paid_balance: int = economy.balance
	check(PROGRESS.claim_rewards(world,economy)==0 and economy.balance==paid_balance,"reward retry is idempotent")
	check(PROGRESS.validate_wallet(saved,economy.snapshot()),"paid ledger validates after real wallet transactions")
	check(not PROGRESS.validate_wallet(PROGRESS.defaults(),economy.snapshot()),"receipt without physical race result is rejected")
	var wrong := ECONOMY.new()
	wrong.grant_reward("desert_drag:digo",1)
	check(not PROGRESS.validate_wallet(saved,wrong.snapshot()),"changed reward amount is rejected")
	wrong = ECONOMY.new()
	wrong.grant_reward("desert_drag:unknown",100)
	check(not PROGRESS.validate_wallet(saved,wrong.snapshot()),"unknown race receipt cannot create a fictitious championship reward")
	for invalid in [true,"3",1.5,-1,NAN]:
		var bad := saved.duplicate(true)
		bad.finishes = invalid
		check(not PROGRESS.validate_snapshot(bad),"invalid completion counter rejected")
	var bad := saved.duplicate(true)
	bad.wins.append("nadir")
	check(not PROGRESS.validate_snapshot(bad),"duplicate unlocks rejected")
	bad = saved.duplicate(true)
	bad.completed_rivals.erase("digo")
	check(not PROGRESS.validate_snapshot(bad),"missing completion provenance rejected")
	bad = PROGRESS.defaults()
	bad.finishes = 1
	bad.best = {"jessica":20}
	bad.completed_rivals = ["jessica"]
	bad.last_rival = "jessica"
	check(not PROGRESS.validate_snapshot(bad),"cannot restore skipped championship ladder")
	check(is_inf(PROGRESS.crossing_time(90,95,100,4,.1)),"before finish remains unfinished")
	check(is_inf(PROGRESS.crossing_time(102,98,100,4,.1)),"backward crossing does not finish")
	check(is_equal_approx(PROGRESS.crossing_time(99,103,100,4,.1),4.025),"swept crossing interpolates within physics frame")
	var first := PROGRESS.crossing_time(99,103,100,4,.1)
	var second := PROGRESS.crossing_time(98,102,100,4,.1)
	check(first<second,"same-frame finish preserves physical arrival order")
	print("DESERT_DRAG_PROGRESS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
