extends RefCounted
## O débito de inscrição e a liquidação dividem os recibos duráveis da carteira existente.
const LEVELS := [
	{"name":"Iniciante","fee":100,"bonus":40,"laps":2,"rivals":3,"speed":10.5,"width":9.0},
	{"name":"Intermediário","fee":200,"bonus":80,"laps":2,"rivals":4,"speed":12.5,"width":8.0},
	{"name":"Avançado","fee":350,"bonus":140,"laps":3,"rivals":5,"speed":14.0,"width":7.0},
	{"name":"Expert","fee":500,"bonus":200,"laps":3,"rivals":5,"speed":15.5,"width":6.5}]
## Uma volta de 402 m aos 18 m/s do modelo mais rápido dá ~22 s; qualquer coisa abaixo disso é
## falha de cronometragem ou save editado, nunca um recorde real.
const MIN_LAP := 15.0
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const RACES := preload("res://systems/economy/RaceReceipts.gd")
var data := {"version":1,"serial":0,"active":-1,"unlocked":0,"wins":[0,0,0,0],"owned":false,"rental_serial":0,"bike_model":0,"best_lap":0.0}

## Voltas de corrida e de treino dividem um recorde da pista. Devolve true para uma nova melhor.
func record_lap(seconds: float) -> bool:
	if not is_finite(seconds) or seconds < MIN_LAP or seconds > 3600.0: return false
	var best := float(data.get("best_lap",0.0))
	if best > 0.0 and seconds >= best: return false
	data.best_lap = seconds
	return true

func rent(wallet) -> bool:
	if data.active != -1: return false
	var serial := int(data.get("rental_serial",0))+1
	if not wallet.spend(35,"motocross_rental:%d"%serial): return false
	data.rental_serial = serial
	return true

func begin(wallet, level: int) -> bool:
	if data.active != -1 or level < 0 or level > int(data.unlocked) or level >= LEVELS.size(): return false
	var serial := int(data.serial)+1
	if not wallet.spend(int(LEVELS[level].fee),"motocross_entry:%d"%serial): return false
	data.serial = serial
	data.active = level
	return true

func settle(wallet, won: bool) -> int:
	var level := int(data.active)
	if level < 0: return 0
	var prize := 0
	if won:
		prize = int(LEVELS[level].fee)+int(LEVELS[level].bonus)
		if not wallet.grant_reward("motocross_prize:%d"%int(data.serial),prize,"Motocross"): return 0
		data.wins[level] += 1
		data.unlocked = maxi(int(data.unlocked),mini(3,level+1))
		if level >= 1: data.owned = true
	data.active = -1
	return prize

func snapshot() -> Dictionary: return data.duplicate(true)
func restore_snapshot(value: Dictionary) -> bool:
	if not validate_snapshot(value): return false
	data = value.duplicate(true)
	if not data.has("rental_serial"): data.rental_serial = 0
	if not data.has("bike_model"): data.bike_model = 0
	if not data.has("best_lap"): data.best_lap = 0.0
	return true

static func validate_snapshot(value: Dictionary) -> bool:
	var best_lap: Variant = value.get("best_lap",0.0)
	if typeof(best_lap) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(best_lap)) or (float(best_lap) != 0.0 and (float(best_lap) < MIN_LAP or float(best_lap) > 3600.0)): return false
	var model: Variant = value.get("bike_model",0)
	if typeof(model) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(model)) or model < 0 or model > 2 or float(model) != floor(float(model)): return false
	var rental: Variant = value.get("rental_serial",0)
	if typeof(rental) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(rental)) or rental < 0 or rental > 10000000 or float(rental) != floor(float(rental)): return false
	for key in ["version","serial","active","unlocked"]:
		if typeof(value.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[key])) or float(value[key]) != floor(float(value[key])): return false
	if value.version != 1 or value.serial < 0 or value.serial > 10000000 or value.active < -1 or value.active > 3 or value.unlocked < 0 or value.unlocked > 3: return false
	if value.active > value.unlocked or not value.get("owned") is bool or not value.get("wins") is Array or value.wins.size() != 4: return false
	for win in value.wins:
		if typeof(win) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(win)) or win < 0 or win > value.serial or float(win) != floor(float(win)): return false
	if value.wins.reduce(func(a,b): return a+b,0) > value.serial: return false
	if value.owned != (value.wins[1]+value.wins[2]+value.wins[3] > 0): return false
	for level in range(1,4):
		if value.unlocked >= level and value.wins[level-1] == 0: return false
	return true

static func validate_wallet(value: Dictionary, wallet: Dictionary) -> bool:
	if not validate_snapshot(value) or not RECEIPTS.validate(wallet): return false
	if RECEIPTS.compact_highest(wallet,"motocross_rental")>int(value.get("rental_serial",0)): return false
	var transactions: Dictionary = wallet.get("transactions",{})
	var totals := {"entries":0,"wins":[0,0,0,0]}
	var rentals := RECEIPTS.compact_count(wallet,"motocross_rental")
	for key in transactions:
		if str(key).begins_with("spend:motocross_rental:"):
			var rental_id := str(key).trim_prefix("spend:motocross_rental:").to_int()
			if rental_id < 1 or rental_id > int(value.get("rental_serial",0)) or int(transactions[key].get("amount",-1)) != 35: return false
			rentals += 1
		if not str(key).begins_with("spend:motocross_entry:"): continue
		var serial := str(key).trim_prefix("spend:motocross_entry:").to_int()
		if serial < 1 or serial > int(value.serial): return false
		if not _tally_entry(value,wallet,serial,int(transactions[key].get("amount",-1)),totals): return false
	if not _tally_compact_entries(value,wallet,totals): return false
	if int(totals.entries) != int(value.serial) or rentals != int(value.get("rental_serial",0)): return false
	# JSON numbers restore as floats; compare validated counts numerically.
	for level in totals.wins.size():
		if int(totals.wins[level]) != int(value.wins[level]): return false
	if int(value.active) >= 0:
		var last := RECEIPTS.lookup(wallet,"spend","motocross_entry:%d"%int(value.serial))
		if int(last.get("amount",-1)) != int(LEVELS[int(value.active)].fee): return false
	return true

static func _tally_entry(value: Dictionary, wallet: Dictionary, serial: int, amount: int, totals: Dictionary) -> bool:
	if serial<1 or serial>int(value.serial): return false
	var level := -1
	for i in LEVELS.size():
		if amount==int(LEVELS[i].fee): level=i
	if level<0: return false
	totals.entries+=1
	var reward: Variant = wallet.get("transactions",{}).get("reward:motocross_prize:%d"%serial)
	if reward==null:
		var compact := RACES.lookup(wallet,"reward","motocross_prize:%d"%serial)
		if not compact.is_empty(): reward=compact
	if reward!=null:
		if not reward is Dictionary or int(reward.get("amount",-1))!=amount+int(LEVELS[level].bonus): return false
		if serial==int(value.serial) and int(value.active)>=0: return false
		totals.wins[level]+=1
	return true

static func _tally_compact_entries(value: Dictionary, wallet: Dictionary, totals: Dictionary) -> bool:
	var summary := RACES.motocross_summary(wallet)
	if int(summary.highest_entry)>int(value.serial): return false
	for code in range(1,25):
		var count := int(summary.counts[code])
		if count==0: continue
		var amount := int(RACES.MOTO_FEES[code%5-1])
		var level := -1
		for i in LEVELS.size():
			if amount==int(LEVELS[i].fee): level=i
		if level<0: return false
		var prize: int = floori(float(code)/5.0)
		if prize>0:
			if int(RACES.MOTO_PRIZES[prize-1])!=amount+int(LEVELS[level].bonus): return false
			totals.wins[level]+=count
		totals.entries+=count
	# Saves mistos podem ter a inscrição numa página e o prêmio no mapa opaco.
	# IDs de prêmio não canônicos continuam ignorados exatamente como a consulta original fazia.
	var transactions: Dictionary = wallet.get("transactions",{})
	for key in transactions:
		var prefix := "reward:motocross_prize:"
		if not str(key).begins_with(prefix): continue
		var suffix := str(key).trim_prefix(prefix)
		if not suffix.is_valid_int() or suffix!=str(suffix.to_int()): continue
		var serial := suffix.to_int()
		var entry := RACES.lookup(wallet,"spend","motocross_entry:%d"%serial)
		if entry.is_empty(): continue
		var level := -1
		for i in LEVELS.size():
			if int(entry.amount)==int(LEVELS[i].fee): level=i
		if level<0: return false
		var reward: Variant = transactions[key]
		if reward==null: continue
		if not reward is Dictionary or int(reward.get("amount",-1))!=int(entry.amount)+int(LEVELS[level].bonus): return false
		if serial==int(value.serial) and int(value.active)>=0: return false
		totals.wins[level]+=1
	if int(value.active)>=0 and not RACES.lookup(wallet,"spend","motocross_entry:%d"%int(value.serial)).is_empty():
		if not RACES.lookup(wallet,"reward","motocross_prize:%d"%int(value.serial)).is_empty(): return false
	return true
