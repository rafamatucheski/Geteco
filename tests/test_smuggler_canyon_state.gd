extends SceneTree
const CANYON := preload("res://runtime/desert/canyon/CanyonState.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String]=[]
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	print("CANYON_STATE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	var state := STATE.new()
	check(STATE.new().restore_snapshot(state.snapshot()),"older saves without canyon remain valid")
	check(CANYON.valid(CANYON.defaults()),"default eight-slot state validates")
	check(not CANYON.claim(state.world_state,state.economy,0,true).ok,"armory cannot bypass undefeated defenders")
	for slot in CANYON.GUARD_COUNT: check(CANYON.defeat(state.world_state,slot),"authored defender slot persists "+str(slot))
	check(CANYON.defeat(state.world_state,0) and int(state.world_state[CANYON.KEY].defeated_mask)==255,"duplicate death cannot add another slot or reward")
	check(not CANYON.defeat(state.world_state,8) and not CANYON.defeat(state.world_state,-1),"out-of-range slots rejected")
	var before: Dictionary=state.snapshot()
	check(not CANYON.claim(state.world_state,state.economy,0,false).ok and state.snapshot()==before,"dead player cannot claim or mutate wallet")
	check(CANYON.claim(state.world_state,state.economy,0,true).ok and state.economy.owns_weapon("ak47"),"cleared armory grants real AK and catalog ammunition")
	before=state.snapshot()
	var retry: Dictionary=CANYON.claim(state.world_state,state.economy,0,true)
	check(retry.ok and not retry.changed and state.snapshot()==before,"repeat interaction is idempotent")
	check(state.economy.grant_weapon("grenade"),"already-owned grenade fixture")
	var reserve_before := int(state.economy.get_ammo("grenade").reserve)
	check(CANYON.claim(state.world_state,state.economy,1,true).ok and int(state.economy.get_ammo("grenade").reserve)==reserve_before+3,"owned weapon receives useful ammunition once")
	check(CANYON.validate_wallet(state.world_state,state.economy.snapshot()),"markers and durable receipts agree")
	var store := STORE.new()
	store.path="res://evidence/desert-canyon/state-%d.json"%Time.get_ticks_usec()
	check(store.save(state)==OK,"save writes isolated disk fixture")
	var loaded := STATE.new()
	check(store.load_into(loaded).get("ok",false),"cold restore accepts cleared camp and rewards")
	check(int(loaded.world_state.get(CANYON.KEY,{}).get("defeated_mask",0))==255,"cold restore preserves all defeated slots")
	before=loaded.economy.snapshot()
	check(not CANYON.claim(loaded.world_state,loaded.economy,0,true).changed and loaded.economy.snapshot()==before,"cold restore cannot farm armory")
	var valid_save := state.snapshot()
	for key in ["version","defeated_mask","cache_mask"]:
		for invalid in [null,true,-1,0.5,"1",INF,NAN,256]:
			var malformed: Dictionary=valid_save.duplicate(true)
			malformed.world[CANYON.KEY][key]=invalid
			check(not STATE.new().restore_snapshot(malformed),"reject malformed "+key+" "+str(invalid))
	var forged := valid_save.duplicate(true)
	forged.world[CANYON.KEY].defeated_mask=254
	check(not STATE.new().restore_snapshot(forged),"claimed armory with living defender rejected")
	forged=valid_save.duplicate(true)
	forged.economy.transactions.erase("reward:"+CANYON.RECEIPTS[0])
	check(not STATE.new().restore_snapshot(forged),"claimed cache without receipt rejected")
	forged=valid_save.duplicate(true)
	forged.world.erase(CANYON.KEY)
	check(not STATE.new().restore_snapshot(forged),"orphan reward receipt cannot reset encounter")
	forged=valid_save.duplicate(true)
	forged.economy.transactions["reward:"+CANYON.RECEIPTS[0]].amount=10
	check(not STATE.new().restore_snapshot(forged),"mismatched receipt rejected")
	var full := STATE.new()
	full.economy.grant_weapon("ak47")
	full.economy._data.weapons.ak47.reserve=full.economy.MAX_AMMO
	for slot in CANYON.GUARD_COUNT: CANYON.defeat(full.world_state,slot)
	before=full.snapshot()
	check(not CANYON.claim(full.world_state,full.economy,0,true).ok and full.snapshot()==before,"capacity failure rolls back receipt marker and ammunition")
	print("CANYON_STATE checks=",checks," failures=",failures.size()," isolated_save=",store.path)
	quit(0 if failures.is_empty() else 1)
