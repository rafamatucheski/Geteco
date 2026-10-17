extends RefCounted
## Forja da Serra: regras das melhorias de lâmina e da pista do aço lendário.
##
## O nível de cada lâmina mora na entrada da arma em `Gameplay.customization`
## (`customization[id].forge`), então `WeaponCustomization.effective_data` aplica o
## efeito no mesmo caminho que dano/cadência/alcance já usam no combate. Cada nível
## pago deixa um recibo na economia; o save só aceita nível com recibo de verdade.
##
## A pista anda em `world_state.blade_forge.stage`:
##   unknown → met (falou com o ferreiro) → seek_hermit (ele indicou o mestre)
##   → seek_miner (o eremita mandou buscar o minério) → has_ore → done (lendária liberada).
const BLADES := ["knife", "axe", "katana"]
const TRACKS := ["edge", "temper"]
const MAX_LEVEL := 2
const STAGES := ["unknown", "met", "seek_hermit", "seek_miner", "has_ore", "done"]
const LABELS := {"knife":"Faca", "axe":"Machado", "katana":"Katana"}
const TRACK_LABELS := {"edge":"Afiação", "temper":"Têmpera"}
## Preço por nível (índice 0 = nível 1). A katana já custa caro na loja: o aço dela também.
const PRICES := {
	"knife": {"edge":[400, 1200], "temper":[400, 1200], "legendary":3500},
	"axe": {"edge":[600, 1600], "temper":[600, 1600], "legendary":4500},
	"katana": {"edge":[900, 2400], "temper":[900, 2400], "legendary":8000},
}
## Afiação: +12% de dano por nível. Têmpera: golpe 8% mais curto por nível.
## Lendária: +25% de dano, golpe 10% mais curto e +10% de alcance, sobre o resto.
const EDGE_DAMAGE := 0.12
const TEMPER_INTERVAL := 0.08
const LEGENDARY_DAMAGE := 1.25
const LEGENDARY_INTERVAL := 0.90
const LEGENDARY_RANGE := 1.10

static func is_blade(id: String) -> bool:
	return id in BLADES

static func fresh_quest() -> Dictionary:
	return {"version":1, "stage":"unknown"}

static func valid_quest(value: Variant) -> bool:
	return _valid_quest(value)

static func _valid_quest(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2: return false
	if typeof(value.get("version")) not in [TYPE_INT, TYPE_FLOAT] or float(value.version) != 1.0: return false
	return value.get("stage") is String and value.stage in STAGES

static func stage_index(stage: String) -> int:
	return maxi(0, STAGES.find(stage))

static func quest(world_state: Dictionary) -> Dictionary:
	var saved: Variant = world_state.get("blade_forge")
	if not _valid_quest(saved):
		saved = fresh_quest()
		world_state["blade_forge"] = saved
	return saved

static func _level(value: Variant) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)): return -1
	if float(value) != floorf(float(value)) or float(value) < 0.0 or float(value) > MAX_LEVEL: return -1
	return int(value)

## Copia só o que é válido, mantendo o tipo numérico que veio do save (JSON devolve
## float): `Gameplay.validate_snapshot` exige que a normalização seja idempotente.
static func normalize(id: String, value: Variant) -> Dictionary:
	if not is_blade(id) or not value is Dictionary: return {}
	var clean := {}
	for track in TRACKS:
		if _level(value.get(track, 0)) > 0: clean[track] = value[track]
	if value.get("legendary", false) == true: clean["legendary"] = true
	return clean

static func level(customization: Dictionary, id: String, track: String) -> int:
	return maxi(0, _level(customization.get(id, {}).get("forge", {}).get(track, 0)))

static func legendary(customization: Dictionary, id: String) -> bool:
	return customization.get(id, {}).get("forge", {}).get("legendary", false) == true

static func receipt(id: String, track: String, next_level: int = 0) -> String:
	if track == "legendary": return "blade_forge:%s:legendary" % id
	return "blade_forge:%s:%s:%d" % [id, track, next_level]

static func price(id: String, track: String, next_level: int = 0) -> int:
	if not PRICES.has(id): return -1
	if track == "legendary": return int(PRICES[id].legendary)
	if next_level < 1 or next_level > MAX_LEVEL: return -1
	return int(PRICES[id][track][next_level - 1])

## Efeito no dicionário de combate de uma arma (já com as peças da bancada).
static func apply(data: Dictionary, forge: Dictionary) -> void:
	if forge.is_empty() or not data.get("is_melee", false): return
	var edge := maxi(0, _level(forge.get("edge", 0)))
	var temper := maxi(0, _level(forge.get("temper", 0)))
	var damage := 1.0 + EDGE_DAMAGE * edge
	var interval := 1.0 - TEMPER_INTERVAL * temper
	var reach := 1.0
	if forge.get("legendary", false) == true:
		damage *= LEGENDARY_DAMAGE
		interval *= LEGENDARY_INTERVAL
		reach *= LEGENDARY_RANGE
	if data.has("damage"): data["damage"] = float(data.damage) * damage
	if data.has("fire_interval"): data["fire_interval"] = float(data.fire_interval) * interval
	if data.has("melee_range"): data["melee_range"] = float(data.melee_range) * reach
	data["forge_legendary"] = forge.get("legendary", false) == true

## O que pode ser comprado agora, com o motivo quando não pode.
static func offer(customization: Dictionary, quest_stage: String, id: String, track: String) -> Dictionary:
	if track == "legendary":
		if legendary(customization, id): return {"ok":false, "reason":"Já é lendária."}
		if quest_stage != "done": return {"ok":false, "reason":"Falta o aço do mestre."}
		for track_name in TRACKS:
			if level(customization, id, track_name) < MAX_LEVEL: return {"ok":false, "reason":"Afiação e têmpera no nível máximo primeiro."}
		return {"ok":true, "price":price(id, "legendary"), "receipt":receipt(id, "legendary")}
	var next_level := level(customization, id, track) + 1
	if next_level > MAX_LEVEL: return {"ok":false, "reason":"Nível máximo."}
	return {"ok":true, "level":next_level, "price":price(id, track, next_level), "receipt":receipt(id, track, next_level)}

## Grava o nível novo na entrada da arma (cria a entrada se a lâmina não tinha peças).
static func install(customization: Dictionary, id: String, track: String) -> void:
	var entry: Dictionary = customization.get(id, {"owned":false, "installed":false, "owned_parts":[], "parts":{}})
	var forge: Dictionary = entry.get("forge", {})
	if track == "legendary": forge["legendary"] = true
	else: forge[track] = level(customization, id, track) + 1
	entry["forge"] = forge
	customization[id] = entry

static func _paid(wallet: Dictionary, receipt_id: String, amount: int) -> bool:
	# Mesma consulta da economia: recibos recorrentes podem estar no livro compacto.
	var transaction: Dictionary = preload("res://systems/economy/RecurringReceipts.gd").lookup(wallet, "spend", receipt_id)
	return transaction.get("kind") == "spend" and typeof(transaction.get("amount")) in [TYPE_INT, TYPE_FLOAT] and int(transaction.amount) == amount

## Save: estágio válido, todo nível pago com o recibo do preço certo e lendária só depois da pista.
static func valid_save(world: Dictionary, combat: Dictionary, wallet: Dictionary) -> bool:
	if world.has("blade_forge") and not _valid_quest(world.blade_forge): return false
	var stage: String = str(world.get("blade_forge", fresh_quest()).get("stage", "unknown"))
	var customization: Variant = combat.get("customization", {})
	if not customization is Dictionary: return true
	for id in BLADES:
		var entry: Variant = customization.get(id, {})
		if not entry is Dictionary or not entry.has("forge"): continue
		if not entry.forge is Dictionary: return false
		var forge: Dictionary = normalize(id, entry.forge)
		if forge != entry.forge: return false
		for track in TRACKS:
			for next_level in range(1, maxi(0, _level(forge.get(track, 0))) + 1):
				if not _paid(wallet, receipt(id, track, next_level), price(id, track, next_level)): return false
		if forge.get("legendary", false) == true:
			if stage != "done": return false
			if not _paid(wallet, receipt(id, "legendary"), price(id, "legendary")): return false
	return true
