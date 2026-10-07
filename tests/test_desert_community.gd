extends SceneTree
const STATE:=preload("res://runtime/desert/community/DesertCommunityState.gd")
const CONTRACTS:=preload("res://runtime/desert/DesertContractState.gd")
const ECONOMY:=preload("res://systems/economy/Economy.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize() -> void:
	var world:={}
	var wallet:=ECONOMY.new()
	check(STATE.validate_wallet(world,wallet.snapshot()),"Old save accepts absent optional quest")
	check(not STATE.advance(world,wallet,0).ok and world.is_empty(),"Cannot start before identifying cooperative cargo")
	for step in 4: check(CONTRACTS.advance(world,wallet,"rail",step).ok,"Complete prerequisite "+str(step))
	var untouched:=world.duplicate(true)
	check(not STATE.advance(world,wallet,2).ok,"Cannot install without collecting cargo")
	for step in STATE.LAST:
		check(STATE.advance(world,wallet,step).ok,"Ordered cooperative objective "+str(step))
		check(not STATE.advance(world,wallet,step).ok,"Repeated old action never advances or pays")
		var restored: Dictionary=JSON.parse_string(JSON.stringify(world))
		check(STATE.valid(restored[STATE.KEY]) and STATE.validate_wallet(restored,wallet.snapshot()),"JSON save roundtrip at objective "+str(step))
		if step<STATE.LAST-1:
			STATE.track(world,false)
			check(not STATE.data(world).active and STATE.data(world).step==step+1,"Untracking preserves progress")
			STATE.track(world,true)
	check(wallet.balance==4000,"Rail R$ 2200 plus one cooperative R$ 1800 reward")
	check(world[CONTRACTS.KEY]==untouched[CONTRACTS.KEY],"Rail and all other jobs unchanged")
	world.erase(STATE.KEY)
	check(world==untouched,"No campaign, Vicente or bridge writes")
	check(not STATE.validate_wallet(world,wallet.snapshot()),"Reward cannot exist without completion")
	var completed:=STATE.defaults(); completed.step=STATE.LAST
	world[STATE.KEY]=completed
	check(not STATE.validate_wallet(world,ECONOMY.new().snapshot()),"Forged completion without receipt rejected")
	var gated:={STATE.KEY:{"version":1,"step":1,"active":true}}
	check(not STATE.validate_wallet(gated,ECONOMY.new().snapshot()),"Progress without rail prerequisite rejected")
	for malformed in [-1,6,1.5,"1",true,INF,NAN]:
		var invalid:=STATE.defaults(); invalid.step=malformed
		check(not STATE.valid(invalid),"Malformed stage rejected "+str(malformed))
	for malformed in [0,1,"true",null]:
		var invalid:=STATE.defaults(); invalid.active=malformed
		check(not STATE.valid(invalid),"Malformed tracking flag rejected")
	var pending:=untouched.duplicate(true)
	var full:=ECONOMY.new()
	full.grant_reward("test_fill_community",ECONOMY.LIMIT)
	for step in STATE.LAST-1: check(STATE.advance(pending,full,step).ok,"Progress works before reward with full wallet")
	var before:=pending.duplicate(true)
	check(not STATE.advance(pending,full,4).ok and pending==before,"Full wallet leaves water restored and final payment pending")
	print("DESERT_COMMUNITY checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
