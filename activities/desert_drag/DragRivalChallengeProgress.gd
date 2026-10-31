extends RefCounted
## Bounded, optional ledger. Proofs, tuning ownership and wallet provenance agree.
const KEY := "drag_rival_challenges"
const CATALOG := preload("res://activities/desert_drag/DragRivalChallengeCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const NIGHT := preload("res://activities/desert_drag/DragNightProgress.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const MAX_ATTEMPTS := 1000000
const MAX_RECORDS := 192
const BONUS := 200
const MAX_BONUSES := 5

static func defaults() -> Dictionary:
	return {"version":1,"next_attempt":1,"proofs":{},"records":{},"bonuses":{},"current":{},"last":{},"reference":{}}

static func data(world: Dictionary) -> Dictionary:
	var raw: Variant=world.get(KEY,defaults())
	return raw.duplicate(true) if raw is Dictionary else {}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=low and value<=high

static func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value>=low and value<=high

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length()<=128

static func _entry(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=7: return false
	if not _integer(value.get("id"),1,MAX_ATTEMPTS) or value.get("rival_id") not in CATALOG.IDS or not _integer(value.get("step"),0,1): return false
	for field in ["vehicle_id","archetype","profile"]:
		if not _id(value.get(field)): return false
	return not TUNING.base_spec(value.profile).is_empty() and value.get("parts") is Dictionary and value.parts==NIGHT.mechanical_parts(value.parts)

static func _metrics(value: Variant, metres: float) -> bool:
	if not value is Dictionary or value.size()!=14: return false
	if value.get("launch") not in ["LARGADA IDEAL","BOA LARGADA","PATINOU","GIRO BAIXO"]: return false
	for field in ["good_shifts","bad_shifts","shift_count"]:
		if not _integer(value.get(field),0,128): return false
	if value.good_shifts+value.bad_shifts!=value.shift_count: return false
	for field in ["limiter_seconds","late_limiter_seconds","nitro_seconds","spin60_seconds","first60_seconds","observed_seconds"]:
		if not _number(value.get(field),0.0,65.0): return false
	for field in ["tail_entry_speed","tail_min_speed","finish_speed"]:
		if not _number(value.get(field),0.0,300.0): return false
	if not _number(value.get("max_offset"),metres-.01,metres+.01): return false
	return value.observed_seconds>0.0 and value.first60_seconds>0.0 and value.spin60_seconds<=value.first60_seconds and value.late_limiter_seconds<=value.limiter_seconds and value.limiter_seconds<=value.observed_seconds and value.nitro_seconds<=value.observed_seconds and value.tail_min_speed<=value.tail_entry_speed

static func _run(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=5 or not _entry(value.get("entry")): return false
	if not _number(value.get("seconds"),.001,65.0) or not (_number(value.get("rival_seconds"),.001,65.0) or value.get("rival_seconds")==-1.0): return false
	var entry: Dictionary=value.entry
	if not _metrics(value.get("metrics"),float(CATALOG.goal(entry.rival_id,int(entry.step)).distance)): return false
	if not value.get("reference") is Dictionary: return false
	if entry.rival_id=="jessica" and int(entry.step)==1:
		if not _reference(value.reference) or not same_preparation(entry,value.reference.entry): return false
	elif not value.reference.is_empty(): return false
	return true

static func _reference(value: Variant) -> bool:
	return value is Dictionary and value.size()==2 and _entry(value.get("entry")) and value.entry.rival_id=="jessica" and value.entry.step==0 and _number(value.get("seconds"),.001,65.0)

static func same_preparation(a: Dictionary, b: Dictionary) -> bool:
	return a.get("vehicle_id","")==b.get("vehicle_id","") and a.get("profile","")==b.get("profile","") and a.get("parts",{})==b.get("parts",{})

static func mastered(value: Dictionary, rival: String) -> bool:
	var proofs: Variant=value.get("proofs",{}).get(rival,[])
	return proofs is Array and proofs.size()==2 and proofs[0] is Dictionary and proofs[1] is Dictionary and not proofs[0].is_empty() and not proofs[1].is_empty()

static func accessible(value: Dictionary, rival: String) -> bool:
	var index := CATALOG.IDS.find(rival)
	if index<0: return false
	for i in index:
		if not mastered(value,str(CATALOG.IDS[i])): return false
	return true

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=8 or value.get("version")!=1 or not _integer(value.get("next_attempt"),1,MAX_ATTEMPTS+1): return false
	for field in ["proofs","records","bonuses","current","last","reference"]:
		if not value.get(field) is Dictionary: return false
	if value.proofs.size()>6 or value.bonuses.size()>6 or value.records.size()>MAX_RECORDS: return false
	for rival in value.proofs:
		if rival not in CATALOG.IDS or not accessible(value,rival): return false
		var rows: Variant=value.proofs[rival]
		if not rows is Array or rows.size()!=2: return false
		for step in 2:
			if not rows[step] is Dictionary: return false
			if rows[step].is_empty():
				if step==0 and not rows[1].is_empty(): return false
				continue
			if not _run(rows[step]): return false
			var entry: Dictionary=rows[step].entry
			if entry.rival_id!=rival or entry.step!=step or entry.id>=value.next_attempt: return false
			if not CATALOG.evaluate(rival,step,rows[step].metrics,float(rows[step].seconds),rows[step].reference).success: return false
	for rival in value.bonuses:
		if rival not in CATALOG.IDS or not accessible(value,rival) or not _integer(value.bonuses[rival],0,MAX_BONUSES): return false
	for key in value.records:
		var row: Variant=value.records[key]
		if not row is Dictionary or row.size()!=5 or row.get("rival_id") not in CATALOG.IDS or not _integer(row.get("step"),0,1): return false
		if not _id(row.get("profile")) or TUNING.base_spec(row.profile).is_empty() or not row.get("parts") is Dictionary or row.parts!=NIGHT.mechanical_parts(row.parts) or not _number(row.get("seconds"),.001,65.0): return false
		if key!=record_key(row.rival_id,int(row.step),row.profile,row.parts) or not accessible(value,row.rival_id): return false
	if not value.current.is_empty():
		if not _entry(value.current) or value.current.id!=value.next_attempt-1 or not accessible(value,value.current.rival_id): return false
		if int(value.current.step)==1 and value.proofs.get(value.current.rival_id,[{},{}])[0].is_empty(): return false
		if value.current.rival_id=="jessica" and value.current.step==1 and (not _reference(value.reference) or not same_preparation(value.current,value.reference.entry)): return false
	if not value.last.is_empty():
		if not _run(value.last) or value.last.entry.id>=value.next_attempt or not accessible(value,value.last.entry.rival_id): return false
		if not value.current.is_empty() and value.current.id<=value.last.entry.id: return false
	if not value.reference.is_empty() and (not _reference(value.reference) or value.reference.entry.id>=value.next_attempt or not accessible(value,"jessica")): return false
	return true

static func record_key(rival: String, step: int, profile: String, parts: Dictionary) -> String:
	return ("rival1|"+rival+"|"+str(step)+"|"+profile+"|"+JSON.stringify(NIGHT.mechanical_parts(parts))).sha256_text()

static func current_rival(world: Dictionary) -> String:
	var value := data(world)
	if not validate_snapshot(value): return ""
	for rival in CATALOG.IDS:
		if not mastered(value,rival): return rival
	return str(CATALOG.IDS.back())

static func status(world: Dictionary, rival: String, requested_step := -1) -> Dictionary:
	var value := data(world)
	if not validate_snapshot(value) or rival not in CATALOG.IDS: return {}
	var rows: Array=value.proofs.get(rival,[{},{}])
	var stamps := int(not rows[0].is_empty())+int(not rows[1].is_empty())
	var step := requested_step if requested_step in [0,1] else (0 if rows[0].is_empty() else 1)
	var spec := CATALOG.spec(rival)
	var goal := CATALOG.goal(rival,step)
	var part: Dictionary=TUNING.PARTS.get(spec.part,{})
	return {"rival_id":rival,"name":spec.name,"theme":spec.theme,"available":accessible(value,rival),"step":step,"objective":goal.objective,"goal_name":goal.name,"distance":goal.distance,"stamps":stamps,"mastered":stamps==2,"reward_part":spec.part,"reward_label":part.get("label",spec.part),"reward_effect":part.get("effect",""),"proofs":rows.duplicate(true),"reference":value.reference.duplicate(true),"bonuses_left":MAX_BONUSES-int(value.bonuses.get(rival,0))}

static func begin(world: Dictionary, rival: String, step: int, vehicle_id: String, archetype: String, profile: String, parts: Dictionary) -> Dictionary:
	var value := data(world)
	if not validate_snapshot(value) or not value.current.is_empty(): return {"ok":false,"reason":"Encerre a inscrição atual antes de iniciar outra."}
	if not accessible(value,rival) or step not in [0,1] or value.next_attempt>MAX_ATTEMPTS: return {"ok":false,"reason":"Conclua os dois desafios do rival anterior."}
	if step==1 and value.proofs.get(rival,[{},{}])[0].is_empty(): return {"ok":false,"reason":"Complete o primeiro desafio antes."}
	var entry := {"id":int(value.next_attempt),"rival_id":rival,"step":step,"vehicle_id":vehicle_id,"archetype":archetype,"profile":profile,"parts":NIGHT.mechanical_parts(parts)}
	if not _entry(entry): return {"ok":false,"reason":"Este carro não tem preparação válida."}
	if rival=="jessica" and step==1 and (value.reference.is_empty() or not same_preparation(entry,value.reference.entry)): return {"ok":false,"reason":"Use o carro e acerto da referência ou registre uma nova."}
	value.current=entry
	value.next_attempt+=1
	world[KEY]=value
	return {"ok":true,"entry":entry.duplicate(true)}

static func cancel(world: Dictionary) -> bool:
	var value := data(world)
	if not validate_snapshot(value) or value.current.is_empty(): return false
	value.current={}
	world[KEY]=value
	return true

static func record_finish(world: Dictionary, attempt: int, vehicle_id: String, profile: String, parts: Dictionary, seconds: float, rival_seconds: float, metres: float, metrics: Dictionary) -> Dictionary:
	var value := data(world)
	if not validate_snapshot(value) or value.current.is_empty(): return {}
	var entry: Dictionary=value.current
	if entry.id!=attempt or entry.vehicle_id!=vehicle_id or entry.profile!=profile or entry.parts!=NIGHT.mechanical_parts(parts): return {}
	var rival := str(entry.rival_id)
	var step := int(entry.step)
	if metres!=CATALOG.goal(rival,step).distance: return {}
	var reference: Dictionary=value.reference.duplicate(true) if rival=="jessica" and step==1 else {}
	var run := {"entry":entry.duplicate(true),"seconds":seconds,"rival_seconds":rival_seconds if is_finite(rival_seconds) else -1.0,"metrics":metrics.duplicate(true),"reference":reference}
	if not _run(run): return {}
	var evaluation := CATALOG.evaluate(rival,step,metrics,seconds,reference)
	var was_mastered := mastered(value,rival)
	var rows: Array=value.proofs.get(rival,[{},{}])
	if evaluation.success:
		if rows[step].is_empty(): rows[step]=run.duplicate(true)
		value.proofs[rival]=rows
		if rival=="jessica" and step==0: value.reference={"entry":entry.duplicate(true),"seconds":seconds}
	var key := record_key(rival,step,profile,parts)
	var previous := float(value.records.get(key,{}).get("seconds",0.0))
	var improved: bool=evaluation.success and (previous<=0.0 or seconds<previous)
	var bonus_earned: bool=evaluation.success and previous>0.0 and seconds<previous-.01 and int(value.bonuses.get(rival,0))<MAX_BONUSES
	if improved:
		if not value.records.has(key) and value.records.size()>=MAX_RECORDS: value.records.erase(value.records.keys()[0])
		value.records[key]={"rival_id":rival,"step":step,"profile":profile,"parts":entry.parts.duplicate(true),"seconds":seconds}
	if bonus_earned: value.bonuses[rival]=int(value.bonuses.get(rival,0))+1
	value.current={}
	value.last=run
	world[KEY]=value
	var done := mastered(value,rival)
	var granted := grant_part(world,rival,vehicle_id,str(entry.archetype)) if done else false
	return {"finished":true,"challenge":true,"first_win":false,"rival_id":rival,"won":seconds<(rival_seconds if rival_seconds>0.0 else INF),"seconds":seconds,"rival_seconds":run.rival_seconds,"distance":metres,"best_seconds":seconds if improved else previous,"record_improved":improved,"challenge_step":step,"challenge_success":evaluation.success,"challenge_detail":evaluation.detail,"challenge_done":done,"challenge_new_mastery":done and not was_mastered,"challenge_reward":str(TUNING.PARTS[CATALOG.RIVALS[rival].part].label),"challenge_granted":granted,"challenge_bonus":BONUS if bonus_earned else 0,"challenge_metrics":metrics.duplicate(true)}

static func grant_part(world: Dictionary, rival: String, vehicle_id: String, archetype: String) -> bool:
	var value := data(world)
	if not validate_snapshot(value) or not mastered(value,rival) or not _id(vehicle_id) or not _id(archetype): return false
	var garage := GARAGE.data(world)
	if not garage.vehicles.has(vehicle_id) and garage.vehicles.size()>=128: return false
	var record := GARAGE.vehicle(world,vehicle_id,archetype)
	if record.archetype!=archetype: return false
	var part := str(CATALOG.RIVALS[rival].part)
	if part in record.owned: return false
	record.owned.append(part)
	garage.vehicles[vehicle_id]=record
	world.desert_garage=garage
	return true

static func validate_world(world: Dictionary, wallet: Dictionary) -> bool:
	var value := data(world)
	if not validate_snapshot(value): return false
	var garage: Variant=world.get("desert_garage",{})
	if not garage is Dictionary or not garage.get("vehicles",{}) is Dictionary: return false
	for key in wallet.get("transactions",{}):
		if not str(key).begins_with("reward:drag_rival_record:"): continue
		var suffix := str(key).trim_prefix("reward:drag_rival_record:")
		var fields := suffix.split(":")
		if fields.size()!=2 or fields[0] not in CATALOG.IDS or not fields[1].is_valid_int(): return false
		var serial := int(fields[1])
		if str(serial)!=fields[1] or serial<1 or serial>int(value.bonuses.get(fields[0],0)): return false
		if wallet.transactions[key].get("amount",-1)!=BONUS: return false
	for record in garage.get("vehicles",{}).values():
		if not record is Dictionary or not record.get("owned",[]) is Array: return false
		for part in record.get("owned",[]):
			var rival := str(TUNING.PARTS.get(part,{}).get("rival_reward",""))
			if not rival.is_empty() and not mastered(value,rival): return false
	return true

static func claim_rewards(world: Dictionary, economy) -> int:
	var value := data(world)
	var wallet: Dictionary=economy.snapshot()
	if not validate_world(world,wallet): return 0
	var paid := 0
	for rival in CATALOG.IDS:
		for serial in range(1,int(value.bonuses.get(rival,0))+1):
			var id: String="drag_rival_record:"+str(rival)+":"+str(serial)
			if not RECEIPTS.lookup(wallet,"reward",id).is_empty(): continue
			if not economy.grant_reward(id,BONUS,"Recorde de arrancada"): return paid
			paid+=BONUS
	return paid

static func pending_reward(world: Dictionary, wallet: Dictionary) -> int:
	if not validate_world(world,wallet): return 0
	var amount := 0
	var value := data(world)
	for rival in CATALOG.IDS:
		for serial in range(1,int(value.bonuses.get(rival,0))+1):
			if RECEIPTS.lookup(wallet,"reward","drag_rival_record:"+rival+":"+str(serial)).is_empty(): amount+=BONUS
	return amount
