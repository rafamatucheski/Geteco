extends SceneTree
## A malformed prerequisite must be rejected as data, without script errors or
## partially replacing the live wallet/progress during GameState restoration.
const GAME := preload("res://runtime/GameState.gd")
const COMMUNITY := preload("res://runtime/desert/community/DesertCommunityState.gd")
const CONTRACTS := preload("res://runtime/desert/DesertContractState.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("COMMUNITY_CORRUPT_SAVE timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var source := GAME.new()
	for step in 4:
		check(CONTRACTS.advance(source.world_state,source.economy,"rail",step).ok,"legitimate rail prerequisite advances")
	check(COMMUNITY.advance(source.world_state,source.economy,0).ok,"Santa Lua starts after legitimate rail completion")
	var valid_save: Dictionary = JSON.parse_string(JSON.stringify(source.snapshot()))
	var live := GAME.new()
	check(live.restore_snapshot(valid_save),"valid in-progress Santa Lua save restores")
	var before: Dictionary = live.snapshot()
	for malformed in [null,[],"broken",7,true]:
		var broken: Dictionary = valid_save.duplicate(true)
		broken.world[CONTRACTS.KEY] = malformed
		check(not COMMUNITY.validate_wallet(broken.world,broken.economy),"malformed prerequisite rejected by Santa Lua validator: "+str(malformed))
		check(not live.restore_snapshot(broken),"malformed prerequisite rejected by GameState: "+str(malformed))
		check(live.snapshot()==before,"failed restore preserves live progress and wallet: "+str(malformed))
		var untouched: Dictionary = broken.world.duplicate(true)
		CONTRACTS.track(broken.world,"")
		CONTRACTS.track(broken.world,"rail")
		check(broken.world==untouched,"tracking does not normalize or mutate malformed progress: "+str(malformed))
	var absent: Dictionary = valid_save.duplicate(true)
	absent.world.erase(CONTRACTS.KEY)
	check(not live.restore_snapshot(absent) and live.snapshot()==before,"missing prerequisite cannot turn active Santa Lua into a default save")
	check(live.restore_snapshot(valid_save) and live.snapshot()==before,"valid save still restores after failed attempts")
	print("COMMUNITY_CORRUPT_SAVE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
