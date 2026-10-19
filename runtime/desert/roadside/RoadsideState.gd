extends RefCounted
## Estado salvo da beira de estrada: o que a torre de rádio já revelou no mapa e um contador
## para os recibos dos serviços repetíveis (cada pagamento tem recibo próprio na carteira, como
## os reboques: "desert_roadside:<tipo>:<n>"). Tudo opcional para saves antigos; um bloco
## inválido volta ao padrão em vez de recusar o save.
const KEY := "desert_roadside"
const VERSION := 1
const MAX_REVEALED := 64

static func defaults() -> Dictionary:
	return {"version": VERSION, "revealed": [], "serial": 0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION: return false
	var revealed: Variant = value.get("revealed")
	if not revealed is Array or revealed.size() > MAX_REVEALED: return false
	for id in revealed:
		if not id is String or id.is_empty() or id.length() > 64: return false
	var serial: Variant = value.get("serial")
	return typeof(serial) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(serial)) and float(serial) >= 0 and float(serial) == floorf(float(serial)) and float(serial) < 100000000

static func data(world_state: Dictionary) -> Dictionary:
	var value: Variant = world_state.get(KEY, defaults())
	return value.duplicate(true) if valid(value) else defaults()

static func next_receipt(world_state: Dictionary, kind: String) -> String:
	var value := data(world_state)
	value.serial = int(value.serial) + 1
	world_state[KEY] = value
	return "desert_roadside:%s:%d" % [kind, int(value.serial)]

## Devolve só os ids que ainda não estavam revelados.
static func reveal(world_state: Dictionary, ids: Array) -> Array:
	var value := data(world_state)
	var added := []
	for id in ids:
		if value.revealed.size() >= MAX_REVEALED: break
		if not value.revealed.has(id):
			value.revealed.append(str(id))
			added.append(str(id))
	world_state[KEY] = value
	return added
