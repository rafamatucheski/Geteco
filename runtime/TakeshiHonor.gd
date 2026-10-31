extends RefCounted
## One optional duel, one permanent choice. Transient race/RAGE never persist here.
const KEY := "takeshi"
const CAR_ID := "takeshi_supra"
const DISCOVERY := "takeshi_honor"
const SABER_PRICE := 150000
const SABER_RECEIPT := "takeshi_saber"
const GIFT_PARTS := preload("res://data/TakeshiRewardSpec.gd").PARTS

static func defaults() -> Dictionary:
	return {"version":1,"won":false,"best_seconds":0.0,"reward":"","saber_unlocked":false,"saber_color":"40bfffff"}

static func data(world: Dictionary) -> Dictionary:
	return world.get(KEY,defaults()).duplicate(true)

static func can_race(_world: Dictionary) -> bool:
	return true

static func pending_reward(world: Dictionary) -> bool:
	var saved := data(world)
	return saved.won and saved.reward.is_empty()

static func record_finish(world: Dictionary, won: bool, seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds <= 0.0 or seconds > 600.0: return {"ok":false}
	var saved := data(world)
	var first_win: bool = won and not saved.won
	if saved.best_seconds <= 0.0 or seconds < saved.best_seconds: saved.best_seconds = seconds
	saved.won = saved.won or won
	world[KEY] = saved
	return {"ok":true,"rival_id":"takeshi","won":won,"first_win":first_win,"finished":true,"seconds":seconds}

static func claim_state(state, choice: String, car_record: Dictionary = {}) -> Dictionary:
	if choice not in ["car","katana"] or not pending_reward(state.world_state): return {"ok":false,"reason":"Prêmio já escolhido ou corrida ainda não vencida."}
	var saved := data(state.world_state)
	if choice == "katana":
		if not state.economy.snapshot().weapons.has("katana") and not state.grant_weapon("katana"):
			return {"ok":false,"reason":"Libere espaço no inventário ou no porta-malas para a katana."}
	else:
		if car_record.get("vehicle_id","") != CAR_ID or car_record.get("archetype","") != "supra_a80" or not preload("res://runtime/FleetState.gd").validate(car_record):
			return {"ok":false,"reason":"Libere a vaga de entrega para receber o Supra."}
		if not state.world_state.has("desert_fleet"): state.world_state.desert_fleet = {}
		state.world_state.desert_fleet[CAR_ID] = car_record.duplicate(true)
		var garage: Dictionary = preload("res://runtime/desert/DesertGarageState.gd").data(state.world_state)
		garage.vehicles[CAR_ID] = {"archetype":"supra_a80","parts":GIFT_PARTS.duplicate(),"owned":GIFT_PARTS.values(),"presets":{},"honor_gift":true}
		state.world_state.desert_garage = garage
	state.economy.discover(DISCOVERY)
	saved.reward = choice
	state.world_state[KEY] = saved
	return {"ok":true,"reason":"Supra recebido. A katana está disponível na Ammu-Nation por $300000." if choice == "car" else "Katana recebida. Sofrer dano carrega o RAGE."}

static func claim(session, choice: String) -> Dictionary:
	if session == null or session.controller.save_invalid or not pending_reward(session.state.world_state): return {"ok":false,"reason":"Prêmio indisponível."}
	if session.state.region_id != "desert" or not session.state.place_id.is_empty() or session.world.gameplay.health <= 0 or session.desert.drag.active: return {"ok":false,"reason":"Volte ao encontro para receber seu prêmio."}
	var car: CharacterBody3D
	var record := {}
	if choice == "car":
		# A entrega usa vagas de paddock checadas contra colisão, fora da reta cronometrada.
		var base: Vector3 = session.desert.drag.staging_point
		for offset in [Vector3(12,.15,-9),Vector3(16,.15,-9),Vector3(20,.15,-9),Vector3(-12,.15,-9)]:
			var point: Vector3 = base + offset
			session.controller.region.prepare_collision_at(point)
			car = session.controller.spawn_vehicle("supra_a80",point,PI)
			if not is_instance_valid(car): continue
			if session.controller.vehicle_position_clear(car,point,PI): break
			car.queue_free()
			car = null
		if not is_instance_valid(car): return {"ok":false,"reason":"Libere uma vaga no pátio e tente novamente."}
		car.vehicle_id = CAR_ID
		preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car,GIFT_PARTS)
		record = preload("res://runtime/FleetState.gd").capture(car,"desert")
	var result := claim_state(session.state,choice,record)
	if not result.ok:
		if is_instance_valid(car): car.queue_free()
		return result
	if is_instance_valid(car): session.desert._track_owned(car)
	if choice == "katana": session.state.equip_weapon("katana")
	session.save_game()
	return result

static func buy_saber(state, color: Color) -> Dictionary:
	if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not state.economy.snapshot().weapons.has("katana"): return {"ok":false,"reason":"Você precisa possuir a katana."}
	var saved := data(state.world_state)
	if saved.reward.is_empty() or not saved.won: return {"ok":false,"reason":"Vença Takeshi e escolha seu prêmio."}
	if not saved.saber_unlocked and not state.economy.spend(SABER_PRICE,SABER_RECEIPT): return {"ok":false,"reason":"Saldo insuficiente: $150000."}
	saved.saber_unlocked = true
	saved.saber_color = Color(clampf(color.r,0,1),clampf(color.g,0,1),clampf(color.b,0,1),1).to_html(true)
	state.world_state[KEY] = saved
	return {"ok":true,"reason":"Sabre de luz aplicado."}

static func validate_world(world: Dictionary, wallet: Dictionary) -> bool:
	var discovery: bool = DISCOVERY in wallet.get("discoveries",[])
	var paid: bool = wallet.get("transactions",{}).has("spend:"+SABER_RECEIPT)
	if not world.has(KEY):
		var legacy_garage: Variant = world.get("desert_garage",{})
		if not legacy_garage is Dictionary or not legacy_garage.get("vehicles",{}) is Dictionary: return false
		for record in legacy_garage.get("vehicles",{}).values():
			if record is Dictionary and record.get("honor_gift",false): return false
		return not discovery and not paid
	var value: Variant = world[KEY]
	if not value is Dictionary or value.get("version") != 1: return false
	if not value.get("won") is bool or not value.get("saber_unlocked") is bool: return false
	if value.get("reward") not in ["","car","katana"]: return false
	if typeof(value.get("best_seconds")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value.best_seconds)) or value.best_seconds < 0 or value.best_seconds > 600: return false
	if not value.get("saber_color") is String or value.saber_color.length() != 8 or not Color.html_is_valid(value.saber_color): return false
	if Color.html(value.saber_color).a != 1.0: return false
	if value.won and value.best_seconds <= 0: return false
	if not value.reward.is_empty() and not value.won: return false
	if discovery != (not value.reward.is_empty()): return false
	if value.reward == "katana" and not wallet.get("weapons",{}).has("katana"): return false
	var fleet: Variant = world.get("desert_fleet",{})
	if not fleet is Dictionary: return false
	if (value.reward == "car") != fleet.has(CAR_ID): return false
	if value.reward == "car" and (not fleet[CAR_ID] is Dictionary or fleet[CAR_ID].get("archetype","") != "supra_a80"): return false
	var garage: Variant = world.get("desert_garage",{})
	if not garage is Dictionary or not garage.get("vehicles",{}) is Dictionary: return false
	if value.reward == "car":
		var gift: Variant = garage.get("vehicles",{}).get(CAR_ID)
		if not gift is Dictionary or gift.get("honor_gift") != true or gift.get("archetype") != "supra_a80" or not gift.get("owned") is Array: return false
		for part in GIFT_PARTS.values():
			if part not in gift.owned: return false
	for id in garage.get("vehicles",{}):
		var record: Variant = garage.vehicles[id]
		if record is Dictionary and record.get("honor_gift",false) and (id != CAR_ID or value.reward != "car"): return false
	if value.saber_unlocked != paid: return false
	if value.saber_unlocked:
		if value.reward.is_empty() or not wallet.get("weapons",{}).has("katana"): return false
		var receipt: Dictionary = wallet.transactions["spend:"+SABER_RECEIPT]
		if receipt.get("amount") != SABER_PRICE or receipt.get("item") != SABER_RECEIPT or receipt.get("kind") != "spend": return false
	return true
