extends RefCounted
## Entry debit and settlement share the existing wallet's durable receipts.
const LEVELS := [
	{"name":"Iniciante","fee":100,"bonus":40,"laps":2,"rivals":3,"speed":10.5,"width":9.0},
	{"name":"Intermediário","fee":200,"bonus":80,"laps":2,"rivals":4,"speed":12.5,"width":8.0},
	{"name":"Avançado","fee":350,"bonus":140,"laps":3,"rivals":5,"speed":14.0,"width":7.0},
	{"name":"Expert","fee":500,"bonus":200,"laps":3,"rivals":5,"speed":15.5,"width":6.5}]
var data := {"version":1,"serial":0,"active":-1,"unlocked":0,"wins":[0,0,0,0],"owned":false,"rental_serial":0,"bike_model":0}

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
		if not wallet.grant_reward("motocross_prize:%d"%int(data.serial),prize): return 0
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
	return true

static func validate_snapshot(value: Dictionary) -> bool:
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
	if not validate_snapshot(value): return false
	var transactions: Dictionary = wallet.get("transactions",{})
	var wins := [0,0,0,0]
	var entries := 0
	var rentals := 0
	for key in transactions:
		if str(key).begins_with("spend:motocross_rental:"):
			var rental_id := str(key).trim_prefix("spend:motocross_rental:").to_int()
			if rental_id < 1 or rental_id > int(value.get("rental_serial",0)) or int(transactions[key].get("amount",-1)) != 35: return false
			rentals += 1
		if not str(key).begins_with("spend:motocross_entry:"): continue
		var serial := str(key).trim_prefix("spend:motocross_entry:").to_int()
		if serial < 1 or serial > int(value.serial): return false
		var amount := int(transactions[key].get("amount",-1))
		var level := -1
		for i in LEVELS.size():
			if amount == int(LEVELS[i].fee): level = i
		if level < 0: return false
		entries += 1
		var reward: Variant = transactions.get("reward:motocross_prize:%d"%serial)
		if reward != null:
			if not reward is Dictionary or int(reward.get("amount",-1)) != amount+int(LEVELS[level].bonus): return false
			if serial == int(value.serial) and int(value.active) >= 0: return false
			wins[level] += 1
	if entries != int(value.serial) or rentals != int(value.get("rental_serial",0)): return false
	# JSON numbers restore as floats; compare validated counts numerically.
	for level in wins.size():
		if wins[level] != int(value.wins[level]): return false
	if int(value.active) >= 0:
		var last: Dictionary = transactions.get("spend:motocross_entry:%d"%int(value.serial),{})
		if int(last.get("amount",-1)) != int(LEVELS[int(value.active)].fee): return false
	return true
