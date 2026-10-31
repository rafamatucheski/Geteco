extends SceneTree
## Contrato diferencial da API pública mais um caso limitado de persistência de vida longa.
## A cópia original da Economy é obrigatória; o runtime candidato é aplicado só a
## um snapshot coordenado. Sem Main, renderização, afirmação de desempenho nem save real.
const ORIGINAL := preload("res://tests/fixtures/EconomyV1ReceiptReference.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const MOTO := preload("res://activities/motocross/MotocrossProgress.gd")
const COMMERCE := preload("res://gameplay/urban_v1/TruckersVillageCommerce.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
class QuestStub extends RefCounted:
	var session: Dictionary
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); print("FAIL ",label)

func _pair() -> Array:
	var original = ORIGINAL.new()
	var candidate = ECONOMY.new()
	check(original.grant_reward("test_funds",20000000) and candidate.grant_reward("test_funds",20000000),"pair funded through public API")
	return [original,candidate]

func _same_state(pair: Array, label: String) -> void:
	var a: Dictionary = pair[0].snapshot()
	var b: Dictionary = pair[1].snapshot()
	var a_payload := a.duplicate(true)
	var b_payload := b.duplicate(true)
	a_payload.erase("transactions"); a_payload.erase("receipt_ledger")
	b_payload.erase("transactions"); b_payload.erase("receipt_ledger")
	a_payload.erase("version"); b_payload.erase("version")
	check(a_payload==b_payload,label+": balance, ownership and inventory match original")
	var receipts_equal := true
	for key_value in a.transactions:
		var key := str(key_value)
		var split := key.find(":")
		if split<0 or RECEIPTS.lookup(b,key.substr(0,split),key.substr(split+1))!=a.transactions[key]: receipts_equal=false
	check(receipts_equal,label+": every original receipt has identical individual lookup")
	check(ECONOMY.validate_snapshot(b),label+": candidate snapshot is valid")

func _round(pair: Array, serial: int) -> void:
	var commands := [
		["spend",35,"motocross_rental:%d"%serial],
		["spend",250,"ski_rental:%d"%serial],
		["spend",100,"northgate_auto:%d"%serial],
		["spend",20,"tonico_drink_%d"%serial],
		["reward",180,"tonico_register_%d"%serial],
	]
	var matched := true
	for command in commands:
		var first: bool = pair[0].spend(command[1],command[2]) if command[0]=="spend" else pair[0].grant_reward(command[2],command[1])
		var second: bool = pair[1].spend(command[1],command[2]) if command[0]=="spend" else pair[1].grant_reward(command[2],command[1])
		matched = matched and first==second and second
	check(matched,"five deterministic recurring operations match at serial %d"%serial)

func _differential() -> void:
	var pair := _pair()
	for serial in range(1,9): _round(pair,serial)
	_same_state(pair,"fresh deterministic ranges")
	var compact: Dictionary = pair[1].snapshot()
	check(compact.transactions.size()==1 and compact.receipt_ledger.streams.size()==5,"snapshot keeps one opaque reward and five ranges without synthetic history")
	check(int(compact.version)==2 and not ORIGINAL.validate_snapshot(compact),"old build rejects new compact format instead of ignoring replay history")
	var opaque_match := true
	for wallet in pair:
		opaque_match = wallet.grant_weapon("pistol") and opaque_match
		opaque_match = wallet.buy_ammo("pistol",7,"opaque_ammo") and opaque_match
		opaque_match = wallet.spend(77,"opaque_service") and opaque_match
		opaque_match = bool(wallet.purchase("supply","lockpick","opaque_purchase").ok) and opaque_match
		opaque_match = wallet.grant_reward("unique_pickup",123) and opaque_match
	check(opaque_match,"variable purchases, ammo, services and unique rewards retain their public APIs")
	_same_state(pair,"opaque and permanent rewards alongside compact ranges")
	for id_value in ["motocross_rental:1","ski_rental:4","northgate_auto:8","tonico_drink_2"]:
		var entry: Dictionary = RECEIPTS.lookup(compact,"spend",id_value)
		var before: Dictionary = pair[1].snapshot()
		check(pair[0].spend(int(entry.amount),id_value)==pair[1].spend(int(entry.amount),id_value),"identical recurring spend retry matches original")
		check(not pair[0].spend(int(entry.amount)+1,id_value) and not pair[1].spend(int(entry.amount)+1,id_value),"conflicting recurring spend amount rejected")
		check(pair[1].snapshot()==before,"recurring retries do not debit or append")
	check(not pair[0].grant_reward("tonico_register_2",180) and not pair[1].grant_reward("tonico_register_2",180),"recurring reward never pays twice")
	check(pair[1].has_reward_receipt("tonico_register_2") and not pair[1].has_reward_receipt("tonico_register_9"),"membership distinguishes committed and future rewards")
	var definition := {"id":"tonico_register_2","kind":"cash","amount":180}
	check(pair[0].grant_world_reward(definition)==pair[1].grant_world_reward(definition),"world-reward retry preserves ok/changed semantics for a compact receipt")
	definition.amount=181
	check(pair[0].grant_world_reward(definition)==pair[1].grant_world_reward(definition),"world-reward conflicting payload remains rejected")
	var before_a: Dictionary = pair[0].snapshot()
	var before_b: Dictionary = pair[1].snapshot()
	_round(pair,9)
	check(pair[0].restore_snapshot(before_a) and pair[1].restore_snapshot(before_b),"rollback restores both opaque and compact state")
	_round(pair,9)
	_same_state(pair,"append after rollback")
	var restored = ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(pair[1].snapshot()))),"compact ranges survive JSON restore")
	check(restored.spend(35,"motocross_rental:2") and not restored.spend(36,"motocross_rental:2"),"loaded compact history preserves matching and conflict decisions")

func _legacy_and_gaps() -> void:
	var pair := _pair()
	for serial in range(1,4):
		pair[0].spend(20,"tonico_drink_%d"%serial)
		pair[0].grant_reward("tonico_register_%d"%serial,180)
	var legacy: Dictionary = pair[0].snapshot()
	check(pair[1].restore_snapshot(legacy) and pair[1].snapshot().transactions==legacy.transactions,"all existing V1 opaque receipts are preserved exactly")
	for serial in range(4,7):
		check(pair[0].spend(20,"tonico_drink_%d"%serial)==pair[1].spend(20,"tonico_drink_%d"%serial),"new sequence follows retained legacy history")
		check(pair[0].grant_reward("tonico_register_%d"%serial,180)==pair[1].grant_reward("tonico_register_%d"%serial,180),"new reward sequence follows retained history")
	var after: Dictionary = pair[1].snapshot()
	check(after.transactions==legacy.transactions and int(after.receipt_ledger.streams.tonico_drink.first)==4,"new ranges begin after legacy receipts without replacing them")
	_same_state(pair,"legacy plus compact suffix")
	var quest := QuestStub.new()
	quest.session={"state":{"economy":pair[1]}}
	var commerce = COMMERCE.new()
	commerce.configure(quest)
	check(int(commerce.data.drink_serial)==6 and int(commerce.data.robbery_serial)==6,"real Tonico reconciler combines legacy and compact high-water")
	var old := {"version":1,"drink_serial":0,"robbery_serial":0,"register_cooldown":0.0,"hostility":0.0}
	check(commerce.restore_snapshot(old) and int(commerce.data.robbery_serial)==6 and float(commerce.data.register_cooldown)==600.0 and float(commerce.data.hostility)==120.0,"replayed old Tonico marker restores cooldown instead of allowing another payout")
	pair=_pair()
	for command in [[20,"tonico_drink_1"],[20,"tonico_drink_3"],[20,"tonico_drink_2"],[20,"tonico_drink_4"],[21,"tonico_drink_5"],[20,"tonico_drink_01"]]:
		check(pair[0].spend(command[0],command[1])==pair[1].spend(command[0],command[1]),"gapped, noncanonical and variable-amount IDs retain original API decisions")
	check(not pair[1].spend(20,"tonico_drink_5"),"opaque divergent amount still rejects conflicting replay")
	_same_state(pair,"gaps and opaque exceptions")

func _invalid_ranges() -> void:
	var wallet = ECONOMY.new()
	wallet.grant_reward("funds",100)
	wallet.spend(20,"tonico_drink_1")
	var valid: Dictionary = wallet.snapshot()
	var invalid: Array[Dictionary] = []
	var value := valid.duplicate(true); value.receipt_ledger.version=999; invalid.append(value)
	value=valid.duplicate(true); value.version=1; invalid.append(value)
	value=valid.duplicate(true); value.erase("receipt_ledger"); invalid.append(value)
	value=valid.duplicate(true); value.receipt_ledger.streams.tonico_drink.first=2; invalid.append(value)
	value=valid.duplicate(true); value.receipt_ledger.streams.tonico_drink.through=1.5; invalid.append(value)
	value=valid.duplicate(true); value.receipt_ledger.streams.tonico_drink.through=1000001; invalid.append(value)
	value=valid.duplicate(true); value.receipt_ledger.streams.unknown={"first":1,"through":1}; invalid.append(value)
	value=valid.duplicate(true); value.transactions["spend:tonico_drink_1"]={"kind":"spend","item":"tonico_drink_1","amount":20}; invalid.append(value)
	value=valid.duplicate(true); value.receipt_ledger.streams.tonico_drink={"first":1}; invalid.append(value)
	for malformed in invalid:
		check(not wallet.restore_snapshot(malformed) and wallet.snapshot()==valid,"malformed/overlapping stream rejected atomically")

func _long_life() -> void:
	var state = STATE.new()
	var progress = MOTO.new()
	check(state.economy.grant_reward("long_life_funds",20000000),"long-life public wallet funded")
	var completed := 0
	var all_accepted := true
	for serial in range(1,20001):
		all_accepted = progress.rent(state.economy) and all_accepted
		all_accepted = state.economy.spend(250,"ski_rental:%d"%serial) and all_accepted
		all_accepted = state.economy.spend(100,"northgate_auto:%d"%serial) and all_accepted
		all_accepted = state.economy.spend(20,"tonico_drink_%d"%serial) and all_accepted
		all_accepted = state.economy.grant_reward("tonico_register_%d"%serial,180) and all_accepted
		completed+=5
	state.world_state.motocross=progress.snapshot()
	var data: Dictionary = state.snapshot()
	var bytes := JSON.stringify(data,"\t").to_utf8_buffer().size()
	check(all_accepted and completed==100000,"100000 deterministic recurring operations complete without blocking progression")
	check(data.economy.transactions.size()==1 and data.economy.receipt_ledger.streams.size()==5,"long-life snapshot retains bounded metadata instead of exporting historical entries")
	check(MOTO.validate_wallet(progress.snapshot(),data.economy) and STATE.new().restore_snapshot(data),"real Motocross and full GameState validate compact rental history")
	var wrong_progress: Dictionary = progress.snapshot(); wrong_progress.rental_serial-=1
	check(not MOTO.validate_wallet(wrong_progress,data.economy),"Moto rental counter cannot trail its compact history")
	check(bytes<16384 and bytes<STORE.MAX_BYTES,"100000-operation full save stays below fixed 16 KiB fixture budget and 2 MiB reader limit")
	var store = STORE.new()
	store.path="user://tests/recurring_receipts_%d/progress.json"%Time.get_ticks_usec()
	check(store.save(state)==OK,"long-life full save publishes")
	var loaded = STATE.new()
	check(bool(store.load_into(loaded).get("ok",false)) and loaded.economy.balance==state.economy.balance,"long-life save restores balance and history")
	check(loaded.economy.spend(35,"motocross_rental:1") and not loaded.economy.grant_reward("tonico_register_1",180),"oldest recurring receipts keep replay behavior after 100000 operations and reload")
	evidence={"operations":completed,"opaque_receipts":data.economy.transactions.size(),"streams":data.economy.receipt_ledger.streams,"save_bytes":bytes,"balance":state.economy.balance}

func _cross_contracts() -> void:
	var state = STATE.new()
	state.economy.grant_reward("cross_funds",100)
	state.economy.spend(20,"tonico_drink_1")
	var reward := {"id":"mountain_cargo_plane_treasure_01","kind":"cash","amount":1800}
	check(bool(state.economy.grant_world_reward(reward).ok),"permanent authored reward remains an exact opaque receipt")
	state.world_state.rewards.append(reward.id)
	var full: Dictionary = JSON.parse_string(JSON.stringify(state.snapshot()))
	var restored = STATE.new()
	check(restored.restore_snapshot(full) and restored.economy.snapshot().receipt_ledger==full.economy.receipt_ledger,"GameState clone preserves ledger with world cross-contracts")
	var before: Dictionary = restored.snapshot()
	var altered: Dictionary = full.duplicate(true)
	altered.economy.transactions["reward:"+reward.id].amount=1
	check(not restored.restore_snapshot(altered) and restored.snapshot()==before,"wrong permanent reward payload rejects whole restore before touching ledger")
	altered=full.duplicate(true)
	altered.economy.receipt_ledger.streams.tonico_drink.through=0
	check(not restored.restore_snapshot(altered) and restored.snapshot()==before,"malformed ledger rejects whole GameState atomically")
	var store = STORE.new()
	store.path="user://tests/recurring_import_%d/progress.json"%Time.get_ticks_usec()
	check(store.publish_import_snapshot(full)==OK,"import publication boundary preserves valid compact ledger")
	var imported = STATE.new()
	check(bool(store.load_into(imported).get("ok",false)) and imported.economy.spend(20,"tonico_drink_1") and imported.economy.balance==state.economy.balance,"imported state keeps old spend idempotence without another debit")
	store.path="user://tests/recurring_bad_import_%d/progress.json"%Time.get_ticks_usec()
	check(store.publish_import_snapshot(altered)!=OK and not FileAccess.file_exists(store.path) and not FileAccess.file_exists(store.path+".tmp"),"invalid compact import publishes no primary or temporary")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Requires isolated runner storage and --no-save")
		quit(2); return
	_differential()
	_legacy_and_gaps()
	_invalid_ranges()
	_cross_contracts()
	_long_life()
	var file := FileAccess.open("user://recurring-receipts-stage1.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"long_life":evidence},"\t")); file.close()
	print("RECURRING_RECEIPTS_STAGE1 ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
