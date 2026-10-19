extends RefCounted
## Optional V1 ledger. A series is saved between physical passes; active driving
## stays transient. Legacy ranked wins and their one-time receipts are untouched.
const KEY := "drag_night"
const RANKED := preload("res://activities/desert_drag/DesertDragProgress.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const CATALOG := preload("res://activities/desert_drag/DragNightCatalog.gd")
const DISTANCES := [201.0,402.0,402.0,800.0]
const ROUNDS := [1,2,2,3]
const LABELS := ["Saída","Marca · primeira passagem","Marca · segunda passagem","Desafio"]
const FINISH_PRIZE := 600
const WIN_PRIZE := 300
const MAX_EPISODES := 1000000
const MAX_RECORDS := 256
const COSMETIC_SLOTS := ["paint","finish","wheels","neon"]

static func defaults() -> Dictionary:
	return {"version":1,"next_episode":1,"finishes":0,"wins":0,"won_rivals":[],"current":{},"last":{},"records":{}}

static func data(world: Dictionary) -> Dictionary:
	var value: Variant=world.get(KEY,defaults())
	return value.duplicate(true) if value is Dictionary else {}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=minimum and value<=maximum

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length()<=128

static func _time(value: Variant, dnf := false) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and ((dnf and float(value)==-1.0) or (float(value)>0.0 and float(value)<=65.0))

static func _parts(value: Variant) -> bool:
	return value is Dictionary and value==TUNING.clean_parts(value)

static func mechanical_parts(parts: Dictionary) -> Dictionary:
	var clean := TUNING.clean_parts(parts)
	var result := {}
	for slot in TUNING.SLOTS:
		if slot not in COSMETIC_SLOTS and clean.has(slot): result[slot]=clean[slot]
	return result

static func record_key(profile: String, parts: Dictionary, metres: float, category := "livre") -> String:
	var signature := "rules1|"+profile+"|"+str(int(metres))+"|"+JSON.stringify(mechanical_parts(parts))
	# Keep the original Livre namespace byte-for-byte for existing saves.
	if category!="livre": signature+="|category:"+category
	return signature.sha256_text()

static func _valid_episode(value: Variant, completed: bool) -> bool:
	if not value is Dictionary or value.size() not in [6,7]: return false
	if value.size()==7 and not value.has("category"): return false
	if value.get("category","livre") not in CATALOG.CATEGORIES: return false
	if not _integer(value.get("id"),1,MAX_EPISODES) or value.get("rival_id") not in RANKED.RIVALS: return false
	for key in ["vehicle_id","archetype","profile"]:
		if not _id(value.get(key)): return false
	if TUNING.base_spec(value.profile).is_empty(): return false
	if not value.get("results") is Array: return false
	var runs: Array=value.results
	if (completed and runs.size()!=4) or (not completed and runs.size()>3): return false
	for i in runs.size():
		var run: Variant=runs[i]
		if not run is Dictionary or run.size()!=4 or run.get("distance")!=DISTANCES[i]: return false
		if not _time(run.get("seconds")) or not _time(run.get("rival_seconds"),true) or not _parts(run.get("parts")): return false
		if not CATALOG.fits_category(run.parts,str(value.get("category","livre"))): return false
	if runs.size()>=3 and mechanical_parts(runs[1].parts)!=mechanical_parts(runs[2].parts): return false
	return true

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=8 or not _integer(value.get("version"),1,1): return false
	if not _integer(value.get("next_episode"),1,MAX_EPISODES+1) or not _integer(value.get("finishes"),0,MAX_EPISODES) or not _integer(value.get("wins"),0,int(value.get("finishes",0))): return false
	if value.finishes>=value.next_episode: return false
	if not value.get("won_rivals") is Array or value.won_rivals.size()>RANKED.RIVALS.size() or value.won_rivals.size()>value.wins: return false
	if (value.wins==0)!=value.won_rivals.is_empty(): return false
	var seen := []
	for rival in value.won_rivals:
		if rival not in RANKED.RIVALS or rival in seen: return false
		seen.append(rival)
	if not value.get("current") is Dictionary or not value.get("last") is Dictionary or not value.get("records") is Dictionary: return false
	if not value.current.is_empty():
		if not _valid_episode(value.current,false) or value.current.id!=value.next_episode-1: return false
	if not value.last.is_empty():
		if not _valid_episode(value.last,true) or value.last.id>=value.next_episode or value.finishes==0: return false
		if not value.current.is_empty() and value.current.id<=value.last.id: return false
		if points(value.last.results)>=2 and (value.wins==0 or value.last.rival_id not in value.won_rivals): return false
	elif value.finishes!=0: return false
	if value.records.size()>MAX_RECORDS: return false
	for key in value.records:
		var row: Variant=value.records[key]
		if not key is String or not row is Dictionary or row.size() not in [4,5]: return false
		if row.size()==5 and not row.has("category"): return false
		var category := str(row.get("category","livre"))
		if category not in CATALOG.CATEGORIES: return false
		if not _id(row.get("profile")) or TUNING.base_spec(row.profile).is_empty() or row.get("distance") not in DISTANCES: return false
		if not _parts(row.get("parts")) or not _time(row.get("seconds")): return false
		if not CATALOG.fits_category(row.parts,category) or key!=record_key(row.profile,row.parts,float(row.distance),category): return false
	return true

static func current(world: Dictionary) -> Dictionary:
	var value := data(world)
	return value.current.duplicate(true) if validate_snapshot(value) else {}

static func next_pass(world: Dictionary) -> Dictionary:
	var episode := current(world)
	if episode.is_empty(): return {}
	var step: int=episode.results.size()
	return {"episode_id":int(episode.id),"step":step,"pass":step+1,"round":ROUNDS[step],"distance":DISTANCES[step],"label":LABELS[step],"rival_id":episode.rival_id,"vehicle_id":episode.vehicle_id,"profile":episode.profile,"points":points(episode.results),"category":str(episode.get("category","livre"))}

static func begin(world: Dictionary, rival: String, vehicle_id: String, archetype: String, profile: String, category := "livre") -> Dictionary:
	var value := data(world)
	if not validate_snapshot(value) or not value.current.is_empty(): return {"ok":false,"reason":"Conclua ou encerre a noite em andamento."}
	if value.next_episode>MAX_EPISODES or not RANKED.can_race(world,rival): return {"ok":false,"reason":"Adversário indisponível."}
	if category not in CATALOG.CATEGORIES: return {"ok":false,"reason":"Categoria indisponível."}
	if not _id(vehicle_id) or not _id(archetype) or not _id(profile) or TUNING.base_spec(profile).is_empty(): return {"ok":false,"reason":"Este carro não tem uma preparação válida."}
	value.current={"id":int(value.next_episode),"rival_id":rival,"vehicle_id":vehicle_id,"archetype":archetype,"profile":profile,"results":[],"category":category}
	value.next_episode+=1
	world[KEY]=value
	return {"ok":true,"episode_id":value.current.id}

static func abandon(world: Dictionary) -> bool:
	var value := data(world)
	if not validate_snapshot(value) or value.current.is_empty(): return false
	value.current={}
	world[KEY]=value
	return true

static func _rival_time(run: Dictionary) -> float:
	return float(run.rival_seconds) if float(run.rival_seconds)>0.0 else INF

static func points(runs: Array) -> int:
	var total := 0
	if runs.size()>=1 and float(runs[0].seconds)<_rival_time(runs[0]): total+=1
	if runs.size()>=3 and minf(float(runs[1].seconds),float(runs[2].seconds))<minf(_rival_time(runs[1]),_rival_time(runs[2])): total+=1
	if runs.size()==4 and float(runs[3].seconds)<_rival_time(runs[3]): total+=1
	return total

static func record_finish(world: Dictionary, episode_id: int, step: int, vehicle_id: String, profile: String, parts: Dictionary, seconds: float, rival_seconds: float, metres: float) -> Dictionary:
	var value := data(world)
	if not validate_snapshot(value) or value.current.is_empty(): return {}
	var episode: Dictionary=value.current
	if episode.id!=episode_id or episode.results.size()!=step or step<0 or step>=4: return {}
	if episode.vehicle_id!=vehicle_id or episode.profile!=profile or metres!=DISTANCES[step]: return {}
	if not _parts(parts) or not _time(seconds) or not _time(rival_seconds,true): return {}
	var category := str(episode.get("category","livre"))
	if not CATALOG.fits_category(parts,category): return {}
	if step==2 and mechanical_parts(episode.results[1].parts)!=mechanical_parts(parts): return {}
	var signature := record_key(profile,parts,metres,category)
	var previous: float=float(value.records.get(signature,{}).get("seconds",0.0))
	var improved := previous<=0.0 or seconds<previous
	if improved:
		# Bounded history of different setups; existing record updates do not evict.
		if not value.records.has(signature) and value.records.size()>=MAX_RECORDS: value.records.erase(value.records.keys()[0])
		value.records[signature]={"profile":profile,"parts":mechanical_parts(parts),"distance":metres,"seconds":seconds}
		if category!="livre": value.records[signature]["category"]=category
	episode.results.append({"distance":metres,"seconds":seconds,"rival_seconds":rival_seconds,"parts":parts.duplicate(true)})
	var score := points(episode.results)
	var done: bool=episode.results.size()==4
	var won := done and score>=2
	var first_merit: bool=won and value.wins==0
	if done:
		value.finishes+=1
		if won:
			value.wins+=1
			if episode.rival_id not in value.won_rivals: value.won_rivals.append(episode.rival_id)
		value.last=episode.duplicate(true)
		value.current={}
	world[KEY]=value
	return {"finished":true,"night":true,"first_win":false,"rival_id":episode.rival_id,"won":seconds<(rival_seconds if rival_seconds>0 else INF),"seconds":seconds,"rival_seconds":rival_seconds,"distance":metres,"best_seconds":seconds if improved else previous,"record_improved":improved,"night_id":episode_id,"night_round":ROUNDS[step],"night_pass":step+1,"night_done":done,"night_points":score,"night_won":won,"night_merit":first_merit,"night_consistency":absf(float(episode.results[1].seconds)-float(episode.results[2].seconds)) if step>=2 else -1.0,"reward_due":FINISH_PRIZE+(WIN_PRIZE if won else 0) if done else 0}

static func merit_count(world: Dictionary) -> int:
	var value := data(world)
	return 1 if validate_snapshot(value) and value.wins>0 else 0

static func _paid(wallet: Dictionary, domain: String) -> int:
	return RECEIPTS.compact_count(wallet,domain)

static func pending_reward_amount(world: Dictionary, wallet: Dictionary) -> int:
	if not validate_world(world,wallet): return 0
	var value := data(world)
	return (int(value.finishes)-_paid(wallet,"drag_night_finish"))*FINISH_PRIZE+(int(value.wins)-_paid(wallet,"drag_night_win"))*WIN_PRIZE

static func validate_world(world: Dictionary, wallet: Dictionary) -> bool:
	var value := data(world)
	if not validate_snapshot(value) or not RECEIPTS.validate(wallet): return false
	for episode in [value.current,value.last]:
		if not episode.is_empty() and not RANKED.can_race(world,str(episode.rival_id)): return false
	for rival in value.won_rivals:
		if not RANKED.can_race(world,str(rival)): return false
	for domain in ["drag_night_finish","drag_night_win"]:
		var limit: int=int(value.finishes if domain=="drag_night_finish" else value.wins)
		var stream: Dictionary=wallet.get("receipt_ledger",{}).get("streams",{}).get(domain,{})
		if not stream.is_empty() and (int(stream.first)!=1 or int(stream.through)>limit): return false
		# These domains are born compact at serial one. Opaque lookalikes imply
		# a skipped serial, altered amount or forged payment and are never adopted.
		for key in wallet.get("transactions",{}):
			if str(key).begins_with("reward:"+domain+":"): return false
	return true

static func claim_rewards(world: Dictionary, economy) -> int:
	var wallet: Dictionary=economy.snapshot()
	if not validate_world(world,wallet): return 0
	var value := data(world)
	var paid := 0
	for domain in ["drag_night_finish","drag_night_win"]:
		var total: int=int(value.finishes if domain=="drag_night_finish" else value.wins)
		var through := _paid(wallet,domain)
		var amount := FINISH_PRIZE if domain=="drag_night_finish" else WIN_PRIZE
		# A loaded backlog is settled in bounded batches when opening the board.
		for serial in range(through+1,mini(total,through+8)+1):
			if not economy.grant_reward(domain+":"+str(serial),amount): break
			paid+=amount
	return paid
