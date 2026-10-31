extends RefCounted
## Esconderijos opcionais têm chave de save própria e nunca avançam flags da história.
## O recibo da economia é o oficial quando um save restaura a carteira primeiro.
const KEY := "desert_discoveries"
const REWARDS := {"desert_relic_station":950,"desert_relic_mine":1650,"desert_relic_wagon":1250,"desert_relic_wreck":700}

static func defaults() -> Dictionary:
	var result := {"version":1}
	for id in REWARDS: result[id] = false
	return result

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for id in REWARDS:
		if not value.get(id) is bool: return false
	return true

static func data(world_state: Dictionary) -> Dictionary:
	var value: Variant = world_state.get(KEY,defaults())
	return value.duplicate(true) if valid(value) else defaults()

static func collected(world_state: Dictionary, id: String) -> bool:
	return REWARDS.has(id) and bool(data(world_state).get(id,false))

static func reward(id: String) -> Dictionary:
	if not REWARDS.has(id): return {}
	return {"id":id+"_cache","kind":"cash","amount":int(REWARDS[id]),"label":"Achado do deserto"}

static func claim(world_state: Dictionary, economy: RefCounted, id: String, player_alive: bool) -> Dictionary:
	if not player_alive: return {"ok":false,"reason":"player_dead","changed":false}
	if not REWARDS.has(id) or not is_instance_valid(economy) or not economy.has_method("grant_world_reward"):
		return {"ok":false,"reason":"invalid_discovery","changed":false}
	if collected(world_state,id): return {"ok":true,"reason":"already_collected","changed":false}
	var result: Dictionary = economy.grant_world_reward(reward(id))
	if not bool(result.get("ok",false)): return result
	var next := data(world_state)
	next[id] = true
	world_state[KEY] = next
	return {"ok":true,"reason":"collected","changed":true,"reward_changed":bool(result.get("changed",false)),"amount":int(REWARDS[id])}
