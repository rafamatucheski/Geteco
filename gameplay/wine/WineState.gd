extends RefCounted
const CATALOG := preload("res://gameplay/wine/WineCatalog.gd")
const MAX_SERVINGS := 36
const MAX_ALCOHOL := 100.0
const SOBER_RATE := 0.42
const SIP_COOLDOWN := 2.5
const SERIAL_LIMIT := 1000000
const GIFT_WINE := "zacharias_malagousia"
## Contrato de recibo persistido. Mantém válidas as quantidades antigas se um catálogo posterior mudar.
const RECEIPT_PRICES_V1 := [75,85,95,100,115,125,145,155]
var data := {"version":1,"servings":{},"alcohol":0.0,"cooldown":0.0,"serial":0,"gift_claimed":false}

func total_servings() -> int:
	var total := 0
	for amount in data.servings.values(): total += int(amount)
	return total
func count(id: String) -> int: return int(data.servings.get(id,0))
func intensity() -> float: return float(data.alcohol)/MAX_ALCOHOL
func stage() -> String:
	if data.alcohol >= 90.0: return "Embriaguez extrema"
	if data.alcohol >= 80.0: return "Muito bêbado"
	if data.alcohol >= 50.0: return "Bêbado"
	if data.alcohol >= 15.0: return "Levemente alcoolizado"
	if data.alcohol > 0.0: return "Recuperando o equilíbrio"
	return "Sóbrio"

func claim_gift() -> bool:
	if data.gift_claimed or total_servings()+CATALOG.SERVINGS>MAX_SERVINGS: return false
	data.gift_claimed=true
	data.servings[GIFT_WINE]=count(GIFT_WINE)+CATALOG.SERVINGS
	return true

func purchase(id: String, economy) -> Dictionary:
	var wine := CATALOG.spec(id)
	if wine.is_empty(): return _result(false,"unknown_wine")
	if total_servings()+CATALOG.SERVINGS > MAX_SERVINGS: return _result(false,"bag_full")
	if int(data.serial)>=SERIAL_LIMIT: return _result(false,"purchase_limit")
	var serial := int(data.serial)+1
	var receipt := "curitiba_wine_%d"%serial
	# spend() is idempotent: a paid receipt must not produce a second bottle.
	if economy.snapshot().get("transactions",{}).has("spend:"+receipt): return _result(false,"receipt_conflict")
	if int(economy.balance)<int(wine.price): return _result(false,"insufficient_funds")
	if not economy.spend(int(wine.price),receipt): return _result(false,"payment_refused")
	data.serial=serial
	data.servings[id]=count(id)+CATALOG.SERVINGS
	return _result(true,"purchased")

func drink_reason(id: String, health: float) -> String:
	var wine := CATALOG.spec(id)
	if wine.is_empty(): return "unknown_wine"
	if not is_finite(health) or health<=0.0: return "unavailable"
	if count(id)<=0: return "empty"
	if float(data.cooldown)>0.0: return "cooldown"
	if float(data.alcohol)+float(wine.alcohol)>MAX_ALCOHOL: return "alcohol_limit"
	return ""
func drink(id: String, health: float) -> Dictionary:
	var reason := drink_reason(id,health)
	if not reason.is_empty(): return _result(false,reason)
	var wine := CATALOG.spec(id)
	data.servings[id]=count(id)-1
	if count(id)==0: data.servings.erase(id)
	data.alcohol=minf(MAX_ALCOHOL,float(data.alcohol)+float(wine.alcohol))
	data.cooldown=SIP_COOLDOWN
	return {"ok":true,"reason":"consumed","heal":minf(float(wine.heal),maxf(0.0,100.0-health))}
func tick(delta: float) -> void:
	if not is_finite(delta) or delta<=0.0: return
	data.alcohol=maxf(0.0,float(data.alcohol)-delta*SOBER_RATE)
	data.cooldown=maxf(0.0,float(data.cooldown)-delta)
func recover() -> void:
	data.alcohol=0.0
	data.cooldown=0.0
func snapshot() -> Dictionary: return data.duplicate(true)
func restore_snapshot(value: Variant) -> bool:
	if not validate_snapshot(value): return false
	data=value.duplicate(true)
	data.serial=int(data.serial)
	for id in data.servings: data.servings[id]=int(data.servings[id])
	return true
static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _integer(value.get("version"),1,1) or not _integer(value.get("serial"),0,SERIAL_LIMIT): return false
	if not value.get("gift_claimed") is bool: return false
	if not value.get("servings") is Dictionary or value.servings.size()>CATALOG.ORDER.size(): return false
	var total := 0
	for id in value.servings:
		if not id is String or not CATALOG.WINES.has(id) or not _integer(value.servings[id],1,MAX_SERVINGS): return false
		total+=int(value.servings[id])
	if total>MAX_SERVINGS or total>(int(value.serial)+(1 if value.gift_claimed else 0))*CATALOG.SERVINGS: return false
	return _number(value.get("alcohol"),0,MAX_ALCOHOL) and _number(value.get("cooldown"),0,SIP_COOLDOWN)
static func validate_wallet(value: Variant, wallet: Dictionary) -> bool:
	if not validate_snapshot(value): return false
	var serial := int(value.serial)
	var count_receipts := 0
	for key in wallet.get("transactions",{}):
		if not str(key).begins_with("spend:curitiba_wine_"): continue
		var suffix := str(key).trim_prefix("spend:curitiba_wine_")
		if not suffix.is_valid_int() or str(int(suffix))!=suffix or int(suffix)<1 or int(suffix)>serial: return false
		var receipt: Variant=wallet.transactions[key]
		if not receipt is Dictionary or receipt.get("kind")!="spend" or receipt.get("item")!="curitiba_wine_"+suffix: return false
		if not _integer(receipt.get("amount"),1,100000): return false
		if int(receipt.amount) not in RECEIPT_PRICES_V1: return false
		count_receipts+=1
	return count_receipts==serial
static func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and float(value)==floor(float(value))
static func _result(ok: bool, reason: String) -> Dictionary: return {"ok":ok,"reason":reason}
