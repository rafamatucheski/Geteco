extends RefCounted
## Extensão opcional do save: acessórios comprados na Union e o que está em cada encaixe.
## O pagamento fica na carteira (recibo "spend:accessory:<id>"); aqui só a posse e o uso.
const CATALOG := preload("res://data/catalogs/AccessoryCatalog.gd")
const PARK := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
const KEY := "wardrobe_accessories"
## Encaixe da Union -> encaixe equivalente dos achados do parque. Os dois não somam no mesmo rosto.
const PARK_SLOT := {"eyes":"glasses", "face":"mask"}

static func fresh() -> Dictionary:
	return {"version":1, "owned":[], "head":"", "eyes":"", "face":"", "neck":""}

static func data(world: Dictionary) -> Dictionary:
	var saved: Variant = world.get(KEY, fresh())
	return saved.duplicate(true) if saved is Dictionary else {}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 + CATALOG.SLOTS.size() or value.get("version") != 1: return false
	if not value.get("owned") is Array or value.owned.size() > CATALOG.ITEMS.size(): return false
	var seen := {}
	for id in value.owned:
		if not id is String or not CATALOG.ITEMS.has(id) or seen.has(id): return false
		seen[id] = true
	for slot in CATALOG.SLOTS:
		var selected: Variant = value.get(slot)
		if not selected is String: return false
		if selected != "" and (not seen.has(selected) or CATALOG.ITEMS[selected].slot != slot): return false
	return true

static func validate_world(world: Dictionary) -> bool:
	return not world.has(KEY) or valid(world[KEY])

static func owns(world: Dictionary, id: String) -> bool:
	return data(world).get("owned", []).has(id)

static func equipped(world: Dictionary) -> Dictionary:
	var saved := data(world)
	var result := {}
	if not valid(saved): return result
	for slot in CATALOG.SLOTS:
		if not str(saved[slot]).is_empty(): result[slot] = saved[slot]
	return result

## Cobra uma vez por item; recompra depois de um save antigo reaproveita o recibo.
static func purchase(world: Dictionary, economy, id: String) -> String:
	if not CATALOG.ITEMS.has(id): return "unknown_item"
	var saved := data(world)
	if not valid(saved): return "invalid_save"
	if saved.owned.has(id): return "already_owned"
	var price := int(CATALOG.ITEMS[id].price)
	if economy.balance < price: return "insufficient_funds"
	if not economy.spend(price, "accessory:" + id): return "payment_failed"
	saved.owned.append(id)
	world[KEY] = saved
	return "purchased"

static func equip(world: Dictionary, id: String) -> bool:
	var saved := data(world)
	if not valid(saved) or not saved.owned.has(id): return false
	var slot: String = CATALOG.ITEMS[id].slot
	saved[slot] = id
	world[KEY] = saved
	if PARK_SLOT.has(slot) and world.has(PARK.KEY): PARK.remove(world, PARK_SLOT[slot])
	return true

static func remove(world: Dictionary, slot: String) -> bool:
	if slot not in CATALOG.SLOTS: return false
	var saved := data(world)
	if not valid(saved): return false
	saved[slot] = ""
	world[KEY] = saved
	return true

## Chamado quando o jogador veste óculos ou máscara do parque.
static func yield_to_park(world: Dictionary, park_slot: String) -> void:
	for slot in PARK_SLOT:
		if PARK_SLOT[slot] == park_slot and world.has(KEY): remove(world, slot)
