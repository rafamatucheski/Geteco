extends SceneTree
## Contratos lógicos puros; só user:// isolado. Os tempos com jogo concorrente são
## diagnósticos de escala, nunca evidência de tempo de quadro nem de desempenho global.
const OLD := preload("res://tests/fixtures/EconomyV1ReceiptReference.gd")
const V2 := preload("res://tests/fixtures/EconomyV2RaceReference.gd")
const OLD_MOTO := preload("res://tests/fixtures/MotocrossProgressRaceReference.gd")
const OLD_SKI := preload("res://tests/fixtures/SkiPolicyRaceReference.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const RACES := preload("res://systems/economy/RaceReceipts.gd")
const MOTO := preload("res://activities/motocross/MotocrossProgress.gd")
const SKI := preload("res://activities/V1OptionalRewardPolicy.gd")
const MOUNTAIN := preload("res://activities/MountainProgression.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var failures: Array[String] = []
var evidence := {"scaling":[],"microseconds_are_not_fps":true}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); print("FAIL ",label)

func pair() -> Array:
	var a=OLD.new(); var b=ECONOMY.new()
	check(a.grant_reward("funds",20000000) and b.grant_reward("funds",20000000),"funded pair")
	return [a,b]

func same(wallets: Array, label: String) -> void:
	var a: Dictionary=wallets[0].snapshot(); var b: Dictionary=wallets[1].snapshot()
	var left:=a.duplicate(true); var right:=b.duplicate(true)
	for key in ["version","transactions","receipt_ledger"]: left.erase(key); right.erase(key)
	check(left==right,label+": same money/items/ownership")
	var equal:=true
	for key in a.transactions:
		var split:=str(key).find(":")
		if RECEIPTS.lookup(b,str(key).substr(0,split),str(key).substr(split+1))!=a.transactions[key]: equal=false
	check(equal,label+": exact receipt payloads")
	check(ECONOMY.validate_snapshot(b),label+": valid wallet")

func _symbols_and_sparse() -> void:
	var wallets:=pair()
	for entry in 5:
		for prize in 5:
			var serial:=entry*5+prize+1
			if entry>0:
				var id:="motocross_entry:%d"%serial
				check(wallets[0].spend(MOTO.LEVELS[entry-1].fee,id)==wallets[1].spend(MOTO.LEVELS[entry-1].fee,id),"entry state %d"%serial)
			if prize>0:
				var id:="motocross_prize:%d"%serial
				var amount:=int(MOTO.LEVELS[prize-1].fee)+int(MOTO.LEVELS[prize-1].bonus)
				check(wallets[0].grant_reward(id,amount)==wallets[1].grant_reward(id,amount),"independent prize state %d"%serial)
	for course in MOUNTAIN.COURSES:
		for bits in range(1,4):
			for side in 2:
				if (bits&(1<<side))==0: continue
				var id:=("ski_finish:" if side==0 else "ski_record:")+str(course)+":"+str(bits)
				var amount:=int(MOUNTAIN.COURSES[course].reward if side==0 else MOUNTAIN.COURSES[course].bonus)
				check(wallets[0].grant_reward(id,amount)==wallets[1].grant_reward(id,amount),"independent ski side")
	same(wallets,"all independent symbols")
	var after: Dictionary=wallets[1].snapshot()
	check(after.version==3 and not V2.validate_snapshot(after) and not OLD.validate_snapshot(after),"both old readers reject V3")
	check(after.transactions.size()==1 and after.receipt_ledger.events.pages.size()==4,"snapshot exposes pages, never synthetic history")
	check(RECEIPTS.lookup(after,"spend","motocross_entry:1").is_empty() and RECEIPTS.lookup(after,"reward","motocross_prize:1").is_empty(),"empty symbol stays absent")
	for suffix in ["256","257","9999999","10000000","10000001","01","0","-1","1.0"]:
		var id: String="motocross_entry:"+str(suffix)
		check(wallets[0].spend(200,id)==wallets[1].spend(200,id),"sparse or opaque serial "+suffix)
	for wallets_item in wallets:
		wallets_item.spend(101,"motocross_entry:500")
		wallets_item.grant_reward("ski_finish:unknown_course:1",260)
		wallets_item.grant_reward("ski_finish:ski_primeira_descida:500",261)
	same(wallets,"sparse and opaque prices")
	check(wallets[1].snapshot().receipt_ledger.events.pages.motocross.size()==3,"far serial allocates only touched pages")
	var before: Dictionary=wallets[1].snapshot()
	check(wallets[1].spend(200,"motocross_entry:10000000") and not wallets[1].spend(100,"motocross_entry:10000000"),"far old retry keeps exact price")
	check(not wallets[1].grant_reward("motocross_prize:2",999) and wallets[1].snapshot()==before,"old reward cannot pay again with new payload")
	check(wallets[0].grant_world_reward({"id":"motocross_prize:2","kind":"cash","amount":140})==wallets[1].grant_world_reward({"id":"motocross_prize:2","kind":"cash","amount":140}),"world reward matching replay result unchanged")
	check(wallets[0].grant_world_reward({"id":"motocross_prize:2","kind":"cash","amount":141})==wallets[1].grant_world_reward({"id":"motocross_prize:2","kind":"cash","amount":141}),"world reward mismatch result unchanged")
	var restored=ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(before))),"sparse pages survive JSON")
	check(restored.spend(200,"motocross_entry:257") and not restored.spend(201,"motocross_entry:257"),"reloaded price conflict and replay")

func _legacy_v2_and_atomicity() -> void:
	var original=OLD.new(); original.grant_reward("funds",10000)
	original.spend(100,"motocross_entry:1"); original.grant_reward("motocross_prize:1",140)
	var old: Dictionary=original.snapshot()
	var wallet=ECONOMY.new()
	check(wallet.restore_snapshot(old),"restore V1 history")
	check(wallet.spend(35,"motocross_rental:1"),"V2 range can precede V3")
	var v2: Dictionary=wallet.snapshot()
	check(v2.version==2 and V2.validate_snapshot(v2),"stage1 remains V2 before race append")
	check(wallet.spend(200,"motocross_entry:2") and wallet.grant_reward("motocross_prize:2",280),"new race records beside opaque legacy")
	check(wallet.spend(35,"motocross_rental:2") and wallet.snapshot().version==3,"range extension never downgrades V3")
	check(wallet.snapshot().transactions==old.transactions and RECEIPTS.compact_count(wallet.snapshot(),"motocross_rental")==2,"legacy preserved and V2 streams unchanged")
	var before: Dictionary=wallet.snapshot()
	wallet.spend(350,"motocross_entry:3")
	check(before.receipt_ledger.events.pages.motocross["0"]!=wallet.snapshot().receipt_ledger.events.pages.motocross["0"],"snapshot retains prior immutable page")
	check(wallet.restore_snapshot(before) and wallet.spend(350,"motocross_entry:3"),"rollback restores page plus balance and permits original command")
	var json:=JSON.stringify(wallet.snapshot(),"",true)
	var parsed: Dictionary=JSON.parse_string(json)
	check(parsed.receipt_ledger.events.pages==wallet.snapshot().receipt_ledger.events.pages and ECONOMY.validate_snapshot(parsed),"canonical string page keys and symbols survive JSON numeric normalization")
	var state=STATE.new(); state.economy=wallet
	var full: Dictionary=state.snapshot(); var restored=STATE.new()
	check(restored.restore_snapshot(full),"full state retains V3")
	var malformed: Dictionary=full.duplicate(true)
	malformed.economy.receipt_ledger.events.codec="race_symbols_v999"
	var intact: Dictionary=restored.snapshot()
	check(not restored.restore_snapshot(malformed) and restored.snapshot()==intact,"invalid codec rejects full restore atomically")

func _malformed() -> void:
	var wallet=ECONOMY.new(); wallet.grant_reward("funds",1000); wallet.spend(100,"motocross_entry:1")
	var valid: Dictionary=wallet.snapshot()
	var bad: Array[Dictionary]=[]
	var b:=valid.duplicate(true); b.version=2; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.version=2; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.codec="unknown"; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.extra=1; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.pages={}; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.pages.motocross={}; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.pages.unknown={"0":"B".repeat(256)}; bad.append(b)
	for key in ["00","-1","1.0","39063"]:
		b=valid.duplicate(true); b.receipt_ledger.events.pages.motocross={key:"B".repeat(256)}; bad.append(b)
	for page in ["","B".repeat(255),"B".repeat(257),"A".repeat(256),"Z".repeat(256),"Ã©".repeat(256),"@".repeat(256)]:
		b=valid.duplicate(true); b.receipt_ledger.events.pages.motocross["0"]=page; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.pages.motocross={"39062":"B".repeat(256)}; bad.append(b)
	b=valid.duplicate(true); b.receipt_ledger.events.pages.ski_primeira_descida={"0":"E".repeat(256)}; bad.append(b)
	b=valid.duplicate(true); b.transactions["spend:motocross_entry:1"]={"kind":"spend","item":"motocross_entry:1","amount":101}; bad.append(b)
	for value in bad:
		check(not wallet.restore_snapshot(value) and wallet.snapshot()==valid,"invalid page/codec/overlap rejected atomically")
	# Lados diferentes de um serial podem pertencer a armazenamentos diferentes.
	b=valid.duplicate(true); b.transactions["reward:motocross_prize:1"]={"kind":"reward","item":"motocross_prize:1","amount":141}
	check(wallet.restore_snapshot(b) and not wallet.grant_reward("motocross_prize:1",140),"opaque mismatch on the other side stays authoritative")

func _real_moto() -> void:
	var wallets:=pair(); var progresses: Array=[OLD_MOTO.new(),MOTO.new()]
	for i in 12:
		var level:=mini(i,3)
		var began_a: bool=progresses[0].begin(wallets[0],level)
		var began_b: bool=progresses[1].begin(wallets[1],level)
		check(began_a==began_b and began_b,"real Moto admission")
		check(OLD_MOTO.validate_wallet(progresses[0].snapshot(),wallets[0].snapshot())==MOTO.validate_wallet(progresses[1].snapshot(),wallets[1].snapshot()),"active Moto wallet parity")
		var won:=i<4 or i%2==0
		check(progresses[0].settle(wallets[0],won)==progresses[1].settle(wallets[1],won),"real Moto win/loss settlement")
		check(progresses[0].snapshot()==progresses[1].snapshot() and MOTO.validate_wallet(progresses[1].snapshot(),wallets[1].snapshot()),"Moto counters/prices/active consistency")
	same(wallets,"Moto authored progression")
	var wrong: Dictionary=progresses[1].snapshot(); wrong.wins[3]+=1
	check(not MOTO.validate_wallet(wrong,wallets[1].snapshot()),"false win counter remains invalid")
	# Original policy ignores orphan prizes until an associated entry exists.
	var orphan:=pair(); orphan[0].grant_reward("motocross_prize:1",140); orphan[1].grant_reward("motocross_prize:1",140)
	var zero: Dictionary=MOTO.new().snapshot()
	check(OLD_MOTO.validate_wallet(zero,orphan[0].snapshot())==MOTO.validate_wallet(zero,orphan[1].snapshot()),"orphan reward validator semantics preserved")
	orphan[0].spend(200,"motocross_entry:1"); orphan[1].spend(200,"motocross_entry:1")
	zero.serial=1
	check(not OLD_MOTO.validate_wallet(zero,orphan[0].snapshot()) and not MOTO.validate_wallet(zero,orphan[1].snapshot()),"mismatched entry/prize still rejected")
	var invalid: Dictionary=orphan[1].snapshot()
	invalid.receipt_ledger.events.pages.motocross["0"]="B"+"A".repeat(255)
	invalid.transactions["reward:motocross_prize:1"]="malformed"
	check(not MOTO.validate_wallet(zero,invalid),"standalone Moto validator rejects non-dictionary opaque prize without runtime error")

func _real_ski() -> void:
	var wallets:=pair()
	for course in MOUNTAIN.COURSES:
		var best: Variant=null
		for elapsed in [120.0,130.0,110.0,140.0]:
			var a: Dictionary=OLD_SKI.ski_settlement(course,MOUNTAIN.COURSES[course],elapsed,best,wallets[0].snapshot().transactions)
			var data: Dictionary=wallets[1].snapshot()
			var b: Dictionary=SKI.ski_settlement(course,MOUNTAIN.COURSES[course],elapsed,best,data.transactions,data.get("receipt_ledger",{}))
			check(a==b and bool(b.ok),"Ski serial/record decision parity")
			check(OLD_SKI.apply_ski_settlement(wallets[0],a)==SKI.apply_ski_settlement(wallets[1],b),"Ski atomic settlement parity")
			if b.record: best=elapsed
	same(wallets,"Ski three authored courses")
	var course:="ski_primeira_descida"
	wallets[1].grant_reward("ski_record:"+course+":99",120)
	var data: Dictionary=wallets[1].snapshot()
	var next: Dictionary=SKI.ski_settlement(course,MOUNTAIN.COURSES[course],100.0,null,data.transactions,data.receipt_ledger)
	check(str(next.finish_receipt).ends_with(":100"),"record-only sparse high serial participates in next serial")
	var forced: Dictionary=next.duplicate(true); forced.record_receipt="ski_record:"+course+":99"
	check(not SKI.apply_ski_settlement(wallets[1],forced) and wallets[1].snapshot()==data,"second payment failure rolls back first payment and page")
	check(SKI.apply_ski_settlement(wallets[1],next),"original next serial remains payable after rollback")
	var unknown:=SKI.ski_settlement("boundary_course",{"reward":100,"bonus":40},100.0,null,{})
	check(bool(unknown.ok) and SKI.apply_ski_settlement(wallets[1],unknown) and wallets[1].snapshot().transactions.has("reward:ski_finish:boundary_course:1"),"generic unknown course API stays opaque")
	wallets[1].grant_reward("ski_finish:"+course+":10000000",260)
	data=wallets[1].snapshot()
	check(SKI.ski_settlement(course,MOUNTAIN.COURSES[course],100.0,null,data.transactions,data.receipt_ledger).get("reason")=="receipt_limit","highest legal serial preserves exhaustion rule")
	var separate=ECONOMY.new(); separate.grant_reward("funds",1000); separate.spend(100,"motocross_entry:20")
	data=separate.snapshot()
	check(OLD_SKI.ski_settlement("motocross",{"reward":100,"bonus":40},100.0,null,data.transactions)==SKI.ski_settlement("motocross",{"reward":100,"bonus":40},100.0,null,data.transactions,data.receipt_ledger),"unknown Ski course cannot consume Moto namespace high-water")

func _mixed_moto() -> void:
	for opaque_entry in [true,false]:
		for prize in [140,141]:
			var old=OLD.new(); old.grant_reward("funds",1000)
			if opaque_entry: old.spend(100,"motocross_entry:1")
			else: old.grant_reward("motocross_prize:1",prize)
			var current=ECONOMY.new(); check(current.restore_snapshot(old.snapshot()),"mixed Moto legacy restore")
			if opaque_entry:
				old.grant_reward("motocross_prize:1",prize); current.grant_reward("motocross_prize:1",prize)
			else:
				old.spend(100,"motocross_entry:1"); current.spend(100,"motocross_entry:1")
			var progress: Dictionary=MOTO.new().snapshot()
			progress.serial=1; progress.wins[0]=1; progress.unlocked=1
			check(OLD_MOTO.validate_wallet(progress,old.snapshot())==MOTO.validate_wallet(progress,current.snapshot()) and MOTO.validate_wallet(progress,current.snapshot())==(prize==140),"mixed entry/prize exact or conflicting amount")
			progress.active=0
			check(not OLD_MOTO.validate_wallet(progress,old.snapshot()) and not MOTO.validate_wallet(progress,current.snapshot()),"mixed paid last serial cannot still be active")
	# Preserva o tratamento do original para grafias numéricas legadas, incluindo
	# os apelidos numéricos duplicados dele. Este codec não pode apertar esse contrato.
	var old=OLD.new(); old.grant_reward("funds",1000)
	old.spend(100,"motocross_entry:01"); old.spend(100,"motocross_entry:1")
	old.grant_reward("motocross_prize:1",140)
	var current=ECONOMY.new(); check(current.restore_snapshot(old.snapshot()),"noncanonical legacy receipts restore unchanged")
	var progress: Dictionary=MOTO.new().snapshot(); progress.serial=2; progress.wins[0]=2; progress.unlocked=1
	check(OLD_MOTO.validate_wallet(progress,old.snapshot()) and MOTO.validate_wallet(progress,current.snapshot()),"legacy duplicate numeric aliases keep original validator semantics")
	old=OLD.new(); old.grant_reward("funds",1000); old.grant_reward("motocross_prize:01",140)
	current=ECONOMY.new(); current.restore_snapshot(old.snapshot())
	old.spend(100,"motocross_entry:1"); current.spend(100,"motocross_entry:1")
	progress=MOTO.new().snapshot(); progress.serial=1
	check(OLD_MOTO.validate_wallet(progress,old.snapshot()) and MOTO.validate_wallet(progress,current.snapshot()),"noncanonical reward is not canonical membership")
	for malformed in [null,"bad"]:
		var a: Dictionary=old.snapshot(); var b: Dictionary=current.snapshot()
		a.transactions["reward:motocross_prize:1"]=malformed; b.transactions["reward:motocross_prize:1"]=malformed
		check(OLD_MOTO.validate_wallet(progress,a)==MOTO.validate_wallet(progress,b),"standalone null/string prize behavior matches original")

func _probe(state, progress, activities: int, batch_us: int) -> void:
	var started:=Time.get_ticks_usec()
	var saved: Dictionary=state.snapshot()
	var snapshot_us:=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	var valid: bool=STATE.new().restore_snapshot(saved)
	var restore_us:=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	var repeated:=true
	for i in 100:
		repeated=state.economy.spend(100,"motocross_entry:1") and repeated
		repeated=not state.economy.grant_reward("motocross_prize:1",140) and repeated
	var retries_us:=Time.get_ticks_usec()-started
	var append_wallet=ECONOMY.new(); append_wallet.restore_snapshot(saved.economy)
	var appended:=true; started=Time.get_ticks_usec()
	for i in range(1,101): appended=append_wallet.spend(100,"motocross_entry:%d"%(int(progress.data.serial)+i)) and appended
	var append_us:=Time.get_ticks_usec()-started
	var bytes:=JSON.stringify(saved,"\t").to_utf8_buffer().size()
	check(valid and repeated and appended and MOTO.validate_wallet(progress.snapshot(),saved.economy),"scale snapshot/restore/retries at %d activities"%activities)
	evidence.scaling.append({"activities":activities,"last_1000_activity_pairs_us":batch_us,"snapshot_us":snapshot_us,"restore_us":restore_us,"200_retries_us":retries_us,"100_appends_us":append_us,"save_bytes":bytes,"opaque_receipts":saved.economy.transactions.size(),"pages":saved.economy.receipt_ledger.events.pages})
	# A evidência registra contagens, não o histórico compacto inteiro.
	var page_counts:={}
	for domain in saved.economy.receipt_ledger.events.pages: page_counts[domain]=saved.economy.receipt_ledger.events.pages[domain].size()
	evidence.scaling[-1].pages=page_counts

func _long_life() -> void:
	var state=STATE.new(); var progress=MOTO.new()
	check(state.economy.grant_reward("funds",20000000),"long-life funding")
	var best:={}; var courses: Array=MOUNTAIN.COURSES.keys()
	var accepted:=true; var batch_start:=Time.get_ticks_usec()
	var last_batch_us:=0
	for serial in range(1,50001):
		var level:=mini(serial-1,3) if serial<5 else serial%4
		accepted=progress.begin(state.economy,level) and accepted
		var won:=serial<=4 or serial%3!=0
		var prize: int=progress.settle(state.economy,won)
		if won and prize<=0: accepted=false
		var course: String=courses[serial%3]
		var elapsed:=100.0+1.0/serial if serial%4!=0 else 150.0
		var data: Dictionary=state.economy.snapshot()
		var settlement: Dictionary=SKI.ski_settlement(course,MOUNTAIN.COURSES[course],elapsed,best.get(course),data.transactions,data.get("receipt_ledger",{}))
		accepted=SKI.apply_ski_settlement(state.economy,settlement) and accepted
		if settlement.get("record",false): best[course]=elapsed
		if serial%1000==0:
			last_batch_us=Time.get_ticks_usec()-batch_start
			batch_start=Time.get_ticks_usec()
		if serial in [1000,10000,50000]:
			state.world_state.motocross=progress.snapshot()
			_probe(state,progress,serial*2,last_batch_us)
			batch_start=Time.get_ticks_usec()
	check(accepted and int(progress.data.serial)==50000,"100000 real Moto/Ski activities accepted")
	state.world_state.motocross=progress.snapshot()
	var full: Dictionary=state.snapshot()
	var bytes:=JSON.stringify(full,"\t").to_utf8_buffer().size()
	check(bytes<262144 and bytes<STORE.MAX_BYTES,"100000-activity full fixture save below 256KiB budget and unchanged2MiB cap")
	check(full.economy.transactions.size()==1,"only funding remains opaque after100000 activities")
	var store=STORE.new(); store.path="user://tests/race_receipts_%d/progress.json"%Time.get_ticks_usec()
	var started:=Time.get_ticks_usec(); var code: int=store.save(state); var save_us:=Time.get_ticks_usec()-started
	check(code==OK,"long-life save accepted")
	var loaded=STATE.new(); started=Time.get_ticks_usec(); var result: Dictionary=store.load_into(loaded); var load_us:=Time.get_ticks_usec()-started
	check(bool(result.get("ok",false)) and loaded.economy.balance==state.economy.balance,"long-life load preserves exact wallet")
	check(loaded.economy.spend(100,"motocross_entry:1") and not loaded.economy.spend(101,"motocross_entry:1") and not loaded.economy.grant_reward("motocross_prize:1",140),"oldest entry/prize replay after save/reload")
	evidence.long_life={"activities":100000,"moto":50000,"ski":50000,"save_bytes":bytes,"save_us":save_us,"load_us":load_us,"balance":loaded.economy.balance}

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	_symbols_and_sparse()
	_legacy_v2_and_atomicity()
	_malformed()
	_real_moto()
	_mixed_moto()
	_real_ski()
	_long_life()
	var file:=FileAccess.open("user://race-receipts-stage2.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence},"\t")); file.close()
	print("RACE_RECEIPTS_STAGE2 ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
