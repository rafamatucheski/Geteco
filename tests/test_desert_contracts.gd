extends SceneTree
const JOBS=preload("res://runtime/desert/DesertContractState.gd")
const ECONOMY=preload("res://systems/economy/Economy.gd")
const GAME=preload("res://runtime/GameState.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize() -> void:
	var world:={}
	var wallet:=ECONOMY.new()
	check(JOBS.validate_wallet(world,wallet.snapshot()),"Old saves remain accepted")
	check(not JOBS.advance(world,wallet,"parts",1).ok,"Cannot deliver without accepting")
	check(not JOBS.advance(world,wallet,"unknown",0).ok,"Unknown job rejected")
	for id in ["parts","rail"]:
		for step in range(int(JOBS.LAST[id])):
			check(JOBS.advance(world,wallet,id,step).ok,"Ordered step "+id+str(step))
			check(not JOBS.advance(world,wallet,id,step).ok,"Duplicate step cannot advance/pay")
			var restored: Dictionary=JSON.parse_string(JSON.stringify(world))
			check(JOBS.valid(restored[JOBS.KEY]) and JOBS.validate_wallet(restored,wallet.snapshot()),"JSON roundtrip each step")
	check(wallet.balance==3400,"Exact total, one payment each")
	check(world.keys()==[JOBS.KEY],"Campaign, bridge, discoveries stay unchanged")
	var full:=ECONOMY.new()
	full.grant_reward("fill_test_wallet",ECONOMY.LIMIT)
	var blocked:={}
	JOBS.advance(blocked,full,"parts",0)
	JOBS.advance(blocked,full,"parts",1)
	check(not JOBS.advance(blocked,full,"parts",2).ok and blocked[JOBS.KEY].parts==2,"Full wallet preserves pending turn-in")
	var forged:=JOBS.defaults()
	forged.parts=3
	check(not JOBS.validate_wallet({JOBS.KEY:forged},ECONOMY.new().snapshot()),"Completion without receipt rejected")
	check(not JOBS.validate_wallet({},wallet.snapshot()),"Receipt without completion rejected")
	for malformed in [-1,4,1.5,"1",true]:
		forged=JOBS.defaults(); forged.parts=malformed
		check(not JOBS.valid(forged),"Invalid stage rejected "+str(malformed))
	forged=JOBS.defaults(); forged.active="parts"
	check(not JOBS.valid(forged),"Cannot track unaccepted job")
	var parallel:={}
	var other:=ECONOMY.new()
	JOBS.advance(parallel,other,"parts",0)
	JOBS.advance(parallel,other,"rail",0)
	JOBS.track(parallel,"parts")
	check(parallel[JOBS.KEY].active=="parts" and parallel[JOBS.KEY].rail==1,"Switch preserves both jobs")
	JOBS.track(parallel,"")
	check(parallel[JOBS.KEY].active=="" and parallel[JOBS.KEY].parts==1,"Main story tracking preserves job")
	var state:=GAME.new()
	state.world_state.merge(world,true)
	check(state.economy.restore_snapshot(wallet.snapshot()),"Wallet restored")
	check(GAME.new().restore_snapshot(JSON.parse_string(JSON.stringify(state.snapshot()))),"Full game save contract accepts completed jobs")
	print("DESERT_CONTRACTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
