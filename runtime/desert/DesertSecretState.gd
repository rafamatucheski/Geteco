extends RefCounted
## Optional evidence, separate from the main-act flags. Reward receipts provide
## durable idempotence if a save restores the economy before the world marker.
const KEY := "desert_secrets"
const HOUSE_ID := "desert_abandoned_house"
const CABIN_ID := "desert_abandoned_cabin"
const IDS := [HOUSE_ID,CABIN_ID]
const CLUE := "No fundo do cofre, Dante encontra uma folha de transporte dos Cobras. Na margem, reconhece a letra de Vicente: 'Trocaram a rota. Vou seguir os caminhões.' A data é recente."

static func defaults() -> Dictionary:
	return {"version":1,HOUSE_ID:false,CABIN_ID:false}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for id in IDS:
		if not value.get(id) is bool: return false
	return true

static func data(world_state: Dictionary) -> Dictionary:
	var value: Variant=world_state.get(KEY,defaults())
	return value.duplicate(true) if valid(value) else defaults()

static func collected(world_state: Dictionary, id: String) -> bool:
	return id in IDS and bool(data(world_state).get(id,false))

static func reward(id: String) -> Dictionary:
	if id not in IDS: return {}
	return {"id":id+"_cache","kind":"cash","amount":5000}

static func claim(world_state: Dictionary, economy: RefCounted, id: String, player_alive: bool) -> Dictionary:
	if not player_alive: return {"ok":false,"reason":"player_dead","changed":false}
	if id not in IDS or not is_instance_valid(economy): return {"ok":false,"reason":"invalid_secret","changed":false}
	if collected(world_state,id): return {"ok":true,"reason":"already_collected","changed":false}
	var result: Dictionary=economy.grant_world_reward(reward(id))
	if not bool(result.get("ok",false)): return result
	var next := data(world_state)
	next[id]=true
	world_state[KEY]=next
	return {"ok":true,"reason":"collected","changed":true,"reward_changed":bool(result.get("changed",false)),"amount":int(reward(id).amount),"clue":CLUE if id==HOUSE_ID else ""}
