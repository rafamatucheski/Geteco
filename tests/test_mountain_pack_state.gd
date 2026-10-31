extends SceneTree
## Admissão de save do pacote combinado, independente de cenas ou saves pessoais.
const PACK := preload("res://systems/campaign/MountainPackState.gd")
const STORY := preload("res://systems/campaign/MountainStoryProgress.gd")
const DOWNHILL := preload("res://systems/campaign/MountainDownhillProgress.gd")
const JEEP := preload("res://systems/campaign/MountainJeepProgress.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var economy := ECONOMY.new()
	var old_world := {"unrelated_activity":{"completed":true}}
	var original := old_world.duplicate(true)
	check(PACK.validate_world(old_world,economy.snapshot()),"old saves require no mountain progress")
	check(old_world==original,"admission does not migrate or mutate an old save")
	var world := {"mountain_story":STORY.fresh_snapshot(),"mountain_downhill":DOWNHILL.defaults(),"mountain_jeep":JEEP.DEFAULT.duplicate(true)}
	check(PACK.validate_world(world,economy.snapshot()),"all unstarted activities coexist")
	for key in ["mountain_story","mountain_downhill","mountain_jeep"]:
		for malformed in [null,[],"bad",true,7,{}]:
			var corrupt := world.duplicate(true)
			corrupt[key]=malformed
			check(not PACK.validate_world(corrupt,economy.snapshot()),"invalid block rejected: "+key+" / "+str(malformed))
	check(DOWNHILL.record_finish(world,1,60.0),"winner result recorded")
	check(DOWNHILL.claim_reward(world,economy),"winner receipt issued")
	check(PACK.validate_world(world,economy.snapshot()),"consistent winner and wallet admitted")
	var missing_result := world.duplicate(true)
	missing_result.erase("mountain_downhill")
	check(not PACK.validate_world(missing_result,economy.snapshot()),"deleting downhill result cannot orphan its reward receipt")
	var missing_receipt := ECONOMY.new()
	check(not PACK.validate_world(world,missing_receipt.snapshot()),"deleting wallet receipt cannot preserve a paid result")
	var jeep_wallet := ECONOMY.new()
	check(jeep_wallet.grant_reward(JEEP.RECEIPT,JEEP.PRIZE),"jeep receipt fixture created")
	check(not PACK.validate_world({},jeep_wallet.snapshot()),"deleting jeep result cannot orphan its reward receipt")
	check(not PACK.validate_world({"mountain_jeep":JEEP.DEFAULT.duplicate(true)},jeep_wallet.snapshot()),"replacing jeep result with defaults cannot hide its receipt")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(world))
	check(PACK.validate_world(saved,JSON.parse_string(JSON.stringify(economy.snapshot()))),"combined admission survives JSON round trip")
	print("MOUNTAIN_PACK_STATE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
