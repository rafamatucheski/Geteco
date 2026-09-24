extends RefCounted
## Pure, deterministic adapter for the productive Geteco V1 save envelope.
## It never reads files, chooses a slot or publishes a save.

const GAME_STATE := preload("res://runtime/GameState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
const CANONICAL := preload("res://systems/campaign/CanonicalCampaign.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const OUTFITS := preload("res://data/catalogs/OutfitCatalog.gd")
const COLLECTIBLES := preload("res://data/catalogs/CollectibleCatalog.gd")
const ACHIEVEMENTS := preload("res://data/catalogs/AchievementCatalog.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const EXTRA_FLEET := preload("res://runtime/GarageRewardFleet.gd")
const ACTIVITIES := preload("res://activities/Activities.gd")
const MOUNTAIN := preload("res://activities/MountainProgression.gd")
const GARAGE := preload("res://runtime/GarageRewards.gd")

const V1_VEHICLE_SCRIPTS := [
	"res://characters/PlayerCar.gd",
	"res://prototypes/living_cast/HarborCoupe.gd",
	"res://world/mountain_pass/MountainSUV.gd",
	"res://world/mountain_pass/ArcticJeep.gd",
	"res://world/mountain_pass/MountainPickup.gd",
	"res://cars/traffic/TrafficVehicle.gd",
	"res://world/harbor/monaliza/MonalizaCar.gd",
]
const TOP_KEYS := ["save_version","timestamp","date_string","slot_id","summary","campaign","player","world","wanted"]
const CAMPAIGN_KEYS := ["schema_version","current_stage","completed_beats","unlocked_regions","unlocked_territories","campaign_flags","cobra_campaign","salvage_state","residence_state","race_best_times","bank_incident","npc_medical_care","coroner_cases","coroner_staff_serial"]
const PLAYER_KEYS := ["position","rotation","health","armor","money","active_weapon_id","weapon_inventory","weapon_customization","personal_car_state","personal_loadout_enabled","personal_loadout","mountain_thermal_coat","world_pickups_collected","weapon_ammo","current_outfit_id","owned_outfits","collectibles_found","secret_car_leads","races_finished","races_best_time_count","best_drift_score","drift_challenges_completed","chop_shop_deliveries","chop_shop_total_scrap","unlocked_achievements"]
const WORLD_KEYS := ["region","coordinates_version","temperature","weather_clock","north_access_lower","interior","exterior_return","vehicle"]

static func convert(source: Dictionary) -> Dictionary:
	var result := _result_shell()
	var original := source.duplicate(true)
	if not _validate_envelope(original,result):
		_finalize(result)
		return result
	var state = GAME_STATE.new()
	var proposal: Dictionary = state.snapshot()
	result.proposal = proposal
	var campaign: Dictionary = original.campaign
	var player: Dictionary = original.player
	var world: Dictionary = original.world
	_convert_economy(player,proposal,result)
	_convert_campaign(campaign,proposal,result)
	_convert_location(player,world,proposal,result)
	_convert_world_rewards(player,proposal,result)
	_convert_activities(player,campaign,proposal,result)
	_convert_vehicles(player,campaign,world,proposal,result)
	_convert_cold(player,world,proposal,result)
	_convert_unsupported(player,campaign,world,original,result)
	var validator = GAME_STATE.new()
	result.validator.checked = true
	result.validator.accepted = validator.restore_snapshot(proposal)
	if result.validator.accepted:
		result.proposal = validator.snapshot()
	else:
		_incompatible(result,"v2_validator_rejected","A proposta foi recusada pelo validador V2 atual.",{})
	_finalize(result)
	return result

static func _result_shell() -> Dictionary:
	return {"ok":false,"source_valid":false,"source_format":"productive_v1","target_schema":GAME_STATE.SCHEMA_VERSION,
		"proposal":{},"warnings":[],"unconverted_fields":[],"incompatibilities":[],"decisions_required":[],
		"aliases_applied":[],"transformations":[],"validator":{"checked":false,"accepted":false},"ready_for_publication":false}

static func _validate_envelope(source: Dictionary, result: Dictionary) -> bool:
	if int(source.get("save_version",-1)) != 1:
		_incompatible(result,"unsupported_save_version","Somente o envelope produtivo save_version=1 é aceito.",{"value":source.get("save_version")})
		return false
	for key in ["campaign","player","world","wanted"]:
		if not source.get(key) is Dictionary:
			_incompatible(result,"invalid_section","A seção obrigatória não é um dicionário.",{"field":key})
			return false
	var player: Dictionary = source.player
	for key in ["position","money","health","armor","weapon_inventory","weapon_ammo"]:
		if not player.has(key):
			_incompatible(result,"missing_player_field","Campo produtivo obrigatório ausente.",{"field":"player."+key})
			return false
	if not _position2(player.position):
		_incompatible(result,"invalid_player_position","player.position precisa conter duas coordenadas finitas.",{})
		return false
	for key in ["money","health","armor"]:
		if not _finite_number(player[key]):
			_incompatible(result,"invalid_number","Número inválido no snapshot V1.",{"field":"player."+key})
			return false
	if not player.weapon_inventory is Dictionary or not player.weapon_ammo is Dictionary:
		_incompatible(result,"invalid_weapon_state","Inventário ou munição V1 inválidos.",{})
		return false
	var region := str(source.world.get("region",""))
	if region not in ["harbor","mountain"]:
		_incompatible(result,"unsupported_region","A região V1 não possui destino V2 seguro.",{"region":region})
		return false
	result.source_valid = true
	return true

static func _convert_economy(player: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var wallet: Dictionary = ECONOMY.new().snapshot()
	var money := int(player.money)
	if money < 0 or money > ECONOMY.LIMIT:
		_incompatible(result,"money_out_of_range","O saldo V1 não cabe no contrato V2; nenhum corte foi aplicado.",{"value":money})
	else:
		wallet.balance = money
		_transform(result,"player.money","economy.balance","inteiro; mesma unidade e valor")
	var owned: Dictionary = player.weapon_inventory
	var ammo: Dictionary = player.weapon_ammo
	for id_value in owned:
		var id := str(id_value)
		if owned[id_value] != true: continue
		if not WEAPONS.WEAPONS.has(id):
			_unconverted(result,"player.weapon_inventory."+id,"unknown_weapon",owned[id_value],true)
			continue
		var source_ammo: Variant = ammo.get(id,{})
		if not source_ammo is Dictionary:
			_incompatible(result,"invalid_ammo","Munição V1 inválida.",{"weapon":id})
			continue
		var magazine := int(source_ammo.get("clip",-1 if int(WEAPONS.WEAPONS[id].magazine_size)<0 else 0))
		var reserve := int(source_ammo.get("reserve",magazine))
		if not _ammo_fits(id,magazine,reserve):
			_incompatible(result,"ammo_out_of_range","Munição V1 não cabe no contrato V2; nenhum corte foi aplicado.",{"weapon":id,"clip":magazine,"reserve":reserve})
			continue
		wallet.weapons[id] = {"magazine":magazine,"reserve":reserve}
	if not wallet.weapons.has("fists"): wallet.weapons.fists = {"magazine":-1,"reserve":-1}
	_transform(result,"player.weapon_inventory + player.weapon_ammo","economy.weapons","clip→magazine; reserve preservado")
	var equipped := str(player.get("active_weapon_id","fists"))
	if wallet.weapons.has(equipped): wallet.equipped_weapon = equipped
	else:
		wallet.equipped_weapon = "fists"
		_warn(result,"active_weapon_fallback","Arma ativa ausente ou não convertida; proposta equipa fists.",{"source":equipped})
	var outfits: Array = ["dante_classic"]
	var source_outfits: Variant = player.get("owned_outfits",{})
	if source_outfits is Dictionary:
		for id_value in source_outfits:
			var id := str(id_value)
			if source_outfits[id_value] != true: continue
			if OUTFITS.OUTFITS.has(id):
				if not outfits.has(id): outfits.append(id)
			else: _unconverted(result,"player.owned_outfits."+id,"unknown_outfit",true,true)
	else: _unconverted(result,"player.owned_outfits","invalid_type",source_outfits,true)
	wallet.outfits = outfits
	var outfit := str(player.get("current_outfit_id","dante_classic"))
	wallet.outfit = outfit if outfits.has(outfit) else "dante_classic"
	if wallet.outfit != outfit: _warn(result,"outfit_fallback","Roupa equipada não foi reconhecida; proposta usa dante_classic.",{"source":outfit})
	_convert_collectibles(player,wallet,result)
	_convert_achievements(player,wallet,result)
	_convert_loadout(player,wallet,result)
	proposal.economy = wallet
	var health := float(player.health)
	var armor := float(player.armor)
	if health < 0 or health > 100 or armor < 0 or armor > 100:
		_incompatible(result,"combat_value_out_of_range","Vida ou armadura V1 não cabem no contrato V2.",{"health":health,"armor":armor})
	else:
		proposal.combat = {"health":health,"armor":armor,"crime_points":0,"hidden_time":0.0,"customization":{}}
		_transform(result,"player.health + player.armor","combat.health + combat.armor","mesma escala 0..100")

static func _convert_collectibles(player: Dictionary, wallet: Dictionary, result: Dictionary) -> void:
	var values: Variant = player.get("collectibles_found",[])
	if not values is Array:
		_unconverted(result,"player.collectibles_found","invalid_type",values,true); return
	for value in values:
		var id := str(value)
		if not COLLECTIBLES.ENTRIES.has(id):
			_unconverted(result,"player.collectibles_found","unknown_collectible",id,true); continue
		if wallet.collectibles.has(id):
			_incompatible(result,"duplicate_collectible","Colecionável duplicado no V1.",{"id":id}); continue
		wallet.collectibles.append(id)
		var count: int = wallet.collectibles.size()
		var amount := int(COLLECTIBLES.FIND_CASH) + int(COLLECTIBLES.MILESTONE_CASH.get(count,0))
		wallet.transactions["reward:collectible:"+id] = {"kind":"reward","item":"collectible:"+id,"amount":amount}
	_transform(result,"player.collectibles_found","economy.collectibles + receipts","saldo não é alterado; recibos históricos evitam pagamento duplo")

static func _convert_achievements(player: Dictionary, wallet: Dictionary, result: Dictionary) -> void:
	var values: Variant = player.get("unlocked_achievements",[])
	if not values is Array:
		_unconverted(result,"player.unlocked_achievements","invalid_type",values,true); return
	for value in values:
		var id := str(value)
		if not ACHIEVEMENTS.ACHIEVEMENTS.has(id):
			_unconverted(result,"player.unlocked_achievements","unknown_achievement",id,true); continue
		if wallet.achievements.has(id):
			_incompatible(result,"duplicate_achievement","Conquista duplicada no V1.",{"id":id}); continue
		wallet.achievements.append(id)
		var amount := int(ACHIEVEMENTS.CASH_REWARDS.get(id,0))
		wallet.transactions["reward:achievement:"+id] = {"kind":"reward","item":"achievement:"+id,"amount":amount}
	_transform(result,"player.unlocked_achievements","economy.achievements + receipts","saldo não é alterado; recibos históricos evitam pagamento duplo")

static func _convert_loadout(player: Dictionary, wallet: Dictionary, result: Dictionary) -> void:
	if not bool(player.get("personal_loadout_enabled",false)): return
	var source: Variant = player.get("personal_loadout",{})
	if not source is Dictionary:
		_unconverted(result,"player.personal_loadout","invalid_type",source,true); return
	var loadout := {"curta":"","longa":"","corpo":"","granada":""}
	for slot in loadout:
		var id := str(source.get(slot,""))
		if id != "" and (not wallet.weapons.has(id) or not ECONOMY.PERSONAL_SLOTS[slot].has(id)):
			_unconverted(result,"player.personal_loadout."+slot,"invalid_or_unowned_weapon",id,true)
		else: loadout[slot] = id
	wallet.personal_loadout_enabled = true
	wallet.personal_loadout = loadout
	if wallet.equipped_weapon != "fists" and not loadout.values().has(wallet.equipped_weapon):
		wallet.equipped_weapon = "fists"

static func _convert_campaign(source: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var canonical_validator = CANONICAL.new()
	var completed_beats := _string_array(source.get("completed_beats",[]))
	var derived := _canonical_derived(canonical_validator.catalog,completed_beats)
	var canonical := {
		"version":1,
		"current_stage":str(source.get("current_stage","prologue_call")),
		"completed_beats":completed_beats,
		"completed_contracts":[],
		"flags":derived.flags,
		"regions":derived.regions,
		"territories":derived.territories,
	}
	var source_regions := _string_array(source.get("unlocked_regions",[]))
	var source_territories := _string_array(source.get("unlocked_territories",[]))
	var contract_ledger_may_exist: bool = canonical.current_stage == "contracts_arc" or completed_beats.has("contracts_arc") or completed_beats.size() > 6
	if source_regions != canonical.regions or source_territories != canonical.territories:
		_unconverted(result,"campaign unlocked regions/territories","not_derivable_from_canonical_beats",{"regions":source_regions,"territories":source_territories},true)
	if not contract_ledger_may_exist and canonical_validator.validate_snapshot(canonical):
		proposal.canonical_campaign = canonical
		_transform(result,"campaign canonical fields","canonical_campaign","beat IDs preservados; flags e desbloqueios derivados pelo catálogo V2; nenhum contrato inferido")
	else:
		proposal.canonical_campaign = canonical_validator.snapshot()
		_unconverted(result,"campaign canonical fields","requires_completed_contract_ledger",canonical,true)
		_decision(result,"canonical_campaign","O V1 não grava o ledger de contratos exigido pelo V2. A proposta mantém o ledger canônico no início até escolha explícita.",{"source_stage":canonical.current_stage})
	var runtime: Dictionary = CAMPAIGN.new().snapshot()
	var cobra: Dictionary = source.get("cobra_campaign",{}) if source.get("cobra_campaign",{}) is Dictionary else {}
	var flags: Dictionary = source.get("campaign_flags",{}) if source.get("campaign_flags",{}) is Dictionary else {}
	var first_complete := bool(flags.get("harbor_delivery_complete",false)) or _cobra_completed(cobra).has("primeiro_giro")
	var first_started := first_complete or bool(flags.get("harbor_delivery_started",false)) or bool(flags.get("harbor_first_favors_v3",false))
	if first_complete:
		# HarborArrivalMission pays synchronously before persisting completion.
		_runtime_complete(runtime,"primeiro_giro",true,proposal.economy)
	elif first_started:
		runtime.active_id = "primeiro_giro"
		runtime.step = 2 if bool(flags.get("harbor_delivery_picked_up",false)) else (1 if bool(flags.get("harbor_delivery_receipt",false)) else 0)
	var completed_v1 := _cobra_completed(cobra)
	for id in MISSIONS.ORDER.slice(1):
		if not completed_v1.has(id): continue
		if runtime.active_id != "" or runtime.completed.size() != MISSIONS.ORDER.find(id):
			_incompatible(result,"campaign_order_mismatch","Missões V1 não formam o prefixo obrigatório do V2.",{"mission":id}); continue
		_runtime_complete(runtime,id,_cobra_reward_claimed(cobra,id),proposal.economy)
	var active := str(cobra.get("active_id",""))
	if active != "" and not runtime.completed.has(active):
		if not MISSIONS.ORDER.has(active) or runtime.completed.size() != MISSIONS.ORDER.find(active):
			_incompatible(result,"invalid_active_mission","Missão ativa V1 não tem pré-requisitos V2 seguros.",{"mission":active})
		elif runtime.active_id == "":
			runtime.active_id = active
			runtime.step = 0
			runtime.failure = "import_restart_required"
			_decision(result,"active_mission_restart","O estágio interno da missão ativa V1 não equivale aos eventos físicos V2. A proposta reinicia a missão no passo 0.",{"mission":active,"v1_stage":cobra.get("stage")})
	proposal.campaign = runtime
	_transform(result,"campaign.cobra_campaign + campaign_flags","campaign","conclusões e recibos exatos; missão ativa somente como reinício explícito")
	_convert_arrival(flags,proposal,result)
	var known_flags: Array = canonical.flags.keys()
	known_flags.append_array(["harbor_arrival_seen","harbor_arrival_call_complete","harbor_delivery_started","harbor_first_favors_v3","harbor_delivery_receipt","harbor_delivery_picked_up","harbor_delivery_complete","maciota_met","harbor_maciota_met"])
	for flag_value in flags:
		var flag := str(flag_value)
		if not known_flags.has(flag): _unconverted(result,"campaign.campaign_flags."+flag,"unmapped_campaign_flag",flags[flag_value],true)

static func _canonical_derived(catalog: Dictionary, completed: Array[String]) -> Dictionary:
	var result := {"flags":{},"regions":["central"],"territories":["mercado_velho"]}
	for id in completed:
		var definition := {}
		for candidate in catalog.get("beats",[]):
			if str(candidate.get("id","")) == id: definition = candidate; break
		if definition.is_empty(): continue
		for flag in definition.get("sets_flags",[]): result.flags[str(flag)] = true
		for flag in definition.get("clears_flags",[]): result.flags[str(flag)] = false
		for region in definition.get("unlocks_regions",[]):
			if not result.regions.has(region): result.regions.append(region)
		for territory in definition.get("unlocks_territories",[]):
			if not result.territories.has(territory): result.territories.append(territory)
	return result

static func _runtime_complete(runtime: Dictionary, id: String, claimed: bool, wallet: Dictionary) -> void:
	if not runtime.completed.has(id): runtime.completed.append(id)
	for flag in MISSIONS.MISSIONS[id].sets_flags: runtime.flags[flag] = true
	var amount := int(MISSIONS.MISSIONS[id].reward)
	if claimed:
		runtime.claimed_rewards.append(id)
		wallet.transactions["reward:campaign:"+id] = {"kind":"reward","item":"campaign:"+id,"amount":amount}
	else: runtime.pending_rewards[id] = amount

static func _convert_arrival(flags: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var complete := bool(flags.get("harbor_maciota_met",false)) or bool(flags.get("maciota_met",false)) or bool(flags.get("harbor_delivery_started",false)) or bool(flags.get("harbor_delivery_complete",false))
	if complete:
		proposal.world.arrival = {"version":1,"phase":"complete","flags":{},"caption":-1,"opening_completed":true}
		_transform(result,"campaign_flags harbor arrival","world.arrival","chegada marcada completa para não repetir abertura")
	elif bool(flags.get("harbor_arrival_seen",false)) or bool(flags.get("harbor_arrival_call_complete",false)):
		var partial := {"harbor_arrival_seen":flags.get("harbor_arrival_seen",false),"harbor_arrival_call_complete":flags.get("harbor_arrival_call_complete",false)}
		_unconverted(result,"campaign partial arrival flags","no_exact_v2_phase",partial,true)
		_decision(result,"partial_arrival","A chegada V1 parcialmente executada não determina uma fase física V2 única.",partial)

static func _convert_location(player: Dictionary, world: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var region := str(world.region)
	proposal.region_id = region
	proposal.checkpoint_id = "maciota" if region == "harbor" else "mountain_pass"
	var interior := str(world.get("interior",""))
	if interior != "":
		var definition: Dictionary = PLACES.get_definition(interior)
		if not definition.is_empty() and definition.get("region","") == region:
			proposal.place_id = interior
			proposal.checkpoint_id = interior
			_transform(result,"world.interior","place_id + checkpoint_id","ID preservado")
			if world.has("exterior_return"):
				_unconverted(result,"world.exterior_return","v2_uses_authored_return",world.exterior_return,true)
				_decision(result,"interior_return","O retorno exterior V1 não é publicado silenciosamente; o V2 usa o retorno autorado do interior.",{"place_id":interior})
		else:
			proposal.place_id = ""
			_unconverted(result,"world.interior","unknown_or_wrong_region",interior,true)
			_decision(result,"unknown_interior","Interior V1 desconhecido; a proposta fica no exterior convertido.",{"interior":interior})
	else:
		proposal.place_id = ""
		proposal.world.pedestrian = {"region":region,"position":_position_v2(player.position,region,int(world.get("coordinates_version",0)))}
		_transform(result,"player.position","world.pedestrian.position","V1 pixels XY → V2 metros XZ: [x/16,0,y/16]")
		if region == "mountain" and int(world.get("coordinates_version",0)) < 2:
			_transform(result,"legacy mountain coordinates","world.pedestrian.position","offset V1 [4300,-4960] aplicado antes da escala")

static func _convert_world_rewards(player: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var contracts := _reward_contracts()
	var pickups: Variant = player.get("world_pickups_collected",[])
	if not pickups is Array:
		_unconverted(result,"player.world_pickups_collected","invalid_type",pickups,true); return
	for value in pickups:
		var id := str(value)
		var canonical := GAME_STATE._canonical_reward_id(id)
		if not contracts.has(canonical):
			_unconverted(result,"player.world_pickups_collected","unknown_reward",id,true); continue
		if proposal.world.rewards.has(id):
			_incompatible(result,"duplicate_world_reward","Recompensa mundial duplicada no V1.",{"id":id}); continue
		proposal.world.rewards.append(id)
		var contract: Dictionary = contracts[canonical]
		var kind := str(contract.get("kind",""))
		var item := str(contract.get("item",canonical))
		if kind == "cash":
			proposal.economy.transactions["reward:"+id] = {"kind":"reward","item":id,"amount":int(contract.get("amount",0))}
		elif kind == "weapon":
			if not proposal.economy.weapons.has(item):
				_incompatible(result,"reward_weapon_missing","Marcador de recompensa exige arma ausente.",{"reward":id,"weapon":item})
			var discovery := str(WEAPONS.WEAPONS.get(item,{}).get("discovery_pickup",""))
			if discovery != "" and discovery in [id,canonical] and not proposal.economy.discoveries.has(discovery):
				proposal.economy.discoveries.append(discovery)
			proposal.economy.transactions["reward:"+id] = {"kind":"reward","item":id,"amount":0}
		elif int(proposal.economy.inventory.get(item,0)) < int(contract.get("amount",1)):
			_incompatible(result,"reward_item_missing","Marcador de recompensa exige item ausente.",{"reward":id,"item":item})
		if id != canonical:
			result.aliases_applied.append({"source":id,"canonical":canonical,"v2_normalizes_to":GAME_STATE._reward_aliases(canonical)})
	_transform(result,"player.world_pickups_collected","world.rewards + economy.transactions","saldo não é alterado; recibos históricos preservam idempotência")

static func _reward_contracts() -> Dictionary:
	var result := {}
	for definition in PLACES.definitions():
		for reward in definition.get("rewards",[]):
			if reward is Dictionary and reward.get("id") is String:
				result[GAME_STATE._canonical_reward_id(reward.id)] = reward.duplicate(true)
	for reward in GAME_STATE.CARGO_REWARDS:
		result[GAME_STATE._canonical_reward_id(reward.id)] = reward.duplicate(true)
	return result

static func _convert_activities(player: Dictionary, campaign: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var node = ACTIVITIES.new()
	var activities: Dictionary = node.snapshot()
	node.free()
	activities.races_finished = maxi(0,int(player.get("races_finished",0)))
	activities.race_records = maxi(0,int(player.get("races_best_time_count",0)))
	activities.drift_finished = maxi(0,int(player.get("drift_challenges_completed",0)))
	var mountain: Dictionary = {"version":1,"rental":false,"equipment":false,"rental_serial":0,"best":{},"shadow_announced":false}
	var bests: Variant = campaign.get("race_best_times",{})
	if bests is Dictionary:
		for id_value in bests:
			var id := str(id_value)
			var elapsed: Variant = bests[id_value]
			if not _finite_number(elapsed) or float(elapsed) < 0:
				_unconverted(result,"campaign.race_best_times."+id,"invalid_time",elapsed,true)
			elif MOUNTAIN.COURSES.has(id): mountain.best[id] = float(elapsed)
			elif _activity_race_known(id): activities.race_best[id] = float(elapsed)
			else: _unconverted(result,"campaign.race_best_times."+id,"unknown_race",elapsed,true)
	else: _unconverted(result,"campaign.race_best_times","invalid_type",bests,true)
	var residence: Variant = campaign.get("residence_state",{})
	if residence is Dictionary and not residence.is_empty():
		var home: Dictionary = activities.home
		home.active_home = str(residence.get("active_home",""))
		home.purchases = maxi(0,int(residence.get("purchases",0)))
		var stored: Variant = residence.get("stored_vehicle",{})
		if stored is Dictionary and not stored.is_empty():
			home.stored_vehicle = _residence_vehicle(stored,result)
		activities.home = home
	proposal.world.activities = activities
	if not mountain.best.is_empty(): proposal.world.mountain_progression = mountain
	_transform(result,"player activity counters + campaign.race_best_times + residence_state","world.activities + world.mountain_progression","contadores, tempos e IDs preservados quando catalogados")
	if int(player.get("best_drift_score",0)) > 0:
		_unconverted(result,"player.best_drift_score","missing_drift_zone_id",player.best_drift_score,true)
		_decision(result,"best_drift_score","O V1 guarda somente o maior score global; o V2 exige o ID da zona.",{"score":player.best_drift_score})

static func _residence_vehicle(stored: Dictionary, result: Dictionary) -> Dictionary:
	var archetype := str(stored.get("archetype_id",stored.get("archetype","")))
	if FLEET.spec(archetype).is_empty():
		_unconverted(result,"campaign.residence_state.stored_vehicle","unknown_vehicle",stored,true); return {}
	var color := str(stored.get("color","ffffff"))
	if not Color.html_is_valid(color):
		_unconverted(result,"campaign.residence_state.stored_vehicle.color","invalid_color",color,true); return {}
	var health := float(stored.get("health",FLEET.spec(archetype).get("durability",100)))
	if health < 0 or health > float(FLEET.spec(archetype).get("durability",100)):
		_unconverted(result,"campaign.residence_state.stored_vehicle.health","out_of_range",health,true); return {}
	var status := str(stored.get("status","stored"))
	if status != "stored":
		_warn(result,"residence_vehicle_parked","V1 registrava o veículo como ativo; a proposta o guarda na residência para evitar posição inventada.",{"source_status":status})
		_decision(result,"residence_vehicle_status","Confirme guardar o veículo na residência; o V1 não fornece um ponto V2 seguro para retomada.",{"source_status":status})
	var record := {"archetype_id":archetype,"health":health,"color":color,"status":"stored"}
	if stored.has("garage_id"): record.garage_id = str(stored.garage_id)
	for key in ["nitro","puncture","punctured","nitro_level"]:
		if _meaningful(stored.get(key)):
			_unconverted(result,"campaign.residence_state.stored_vehicle."+key,"unsupported_vehicle_state",stored[key],true)
	return record

static func _convert_vehicles(player: Dictionary, campaign: Dictionary, world: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	var world_vehicle: Variant = world.get("vehicle",{})
	if world_vehicle is Dictionary and not world_vehicle.is_empty():
		var record := _fleet_record(world_vehicle,str(world.region),int(world.get("coordinates_version",0)),result)
		if not record.is_empty():
			if str(world_vehicle.get("script","")) == "res://world/harbor/monaliza/MonalizaCar.gd":
				_put_garage_vehicle(proposal,"personal_monaliza",record,"monaliza")
			else: proposal.world.vehicles.append(record)
	var garage: Dictionary = proposal.world.get("garage_rewards",_garage_default()).duplicate(true)
	var personal: Variant = player.get("personal_car_state",{})
	if personal is Dictionary and not personal.is_empty():
		var record := _personal_record(personal,result)
		if not record.is_empty(): garage.vehicles.personal_monaliza = record
	elif proposal.campaign.completed.has("primeiro_giro"):
		_decision(result,"missing_personal_car_state","O V2 poderia recriar a Monaliza automaticamente, mas o conversor não inventa estado do veículo.",{})
	var cobra: Dictionary = campaign.get("cobra_campaign",{}) if campaign.get("cobra_campaign",{}) is Dictionary else {}
	var boss_owned: Variant = cobra.get("boss_owned",{})
	if boss_owned is Dictionary and not boss_owned.is_empty():
		var boss := _garage_record(boss_owned,"cobra_boss_ironback","cobra_boss_ironback",result)
		if not boss.is_empty(): garage.vehicles.cobra_boss_ironback = boss
	elif proposal.campaign.completed.has("cobra_finale"):
		_decision(result,"missing_ironback_state","O V2 poderia recriar o Ironback automaticamente, mas o conversor não inventa estado do veículo.",{})
	var salvage: Variant = campaign.get("salvage_state",{})
	if salvage is Dictionary and salvage.has("port_boss") and salvage.port_boss is Dictionary:
		var port: Dictionary = salvage.port_boss
		garage.port_status = str(port.get("status","parked"))
		garage.alarm_remaining = float(port.get("alarm_remaining",-1.0))
		garage.police_called = bool(port.get("police_called",false))
		var car: Variant = port.get("car",{})
		if car is Dictionary and not car.is_empty() and garage.port_status != "delivered":
			var port_record := _garage_record(car,"port_garage_stock_2","porto_rosso",result)
			if not port_record.is_empty(): garage.vehicles.port_garage_stock_2 = port_record
		if garage.port_status == "delivered":
			proposal.economy.transactions["reward:port_boss_porto_rosso"] = {"kind":"reward","item":"port_boss_porto_rosso","amount":50000}
		_transform(result,"campaign.salvage_state.port_boss","world.garage_rewards","status, alarme, polícia e carro preservados")
	var secret_owned: Variant = cobra.get("secret_owned",{})
	if secret_owned is Dictionary:
		for secret_id in secret_owned:
			var original_secret: Variant = secret_owned[secret_id]
			if str(secret_id) != "ashbend_coupe" or not original_secret is Dictionary:
				_unconverted(result,"campaign.cobra_campaign.secret_owned."+str(secret_id),"unknown_secret_vehicle",original_secret,true)
				continue
			var source_point: Variant = original_secret.get("position",[])
			var paint := str(original_secret.get("paint","9f673f"))
			var source_health: Variant = original_secret.get("health",100)
			var source_yaw: Variant = original_secret.get("rotation",PI)
			if not _position2(source_point) or not Color.html_is_valid(paint) or not _finite_number(source_health) or not _finite_number(source_yaw):
				_unconverted(result,"campaign.cobra_campaign.secret_owned.ashbend_coupe","invalid_secret_car",original_secret,true)
				continue
			var point := _position_v2(source_point,"harbor",2)
			var record := {"position":point,"yaw":_yaw_v2(float(source_yaw)),"paint":paint,"health":clampf(float(source_health),0.0,140.0),"region":str(world.get("region","harbor")),"destroyed":float(source_health)<=0.0}
			if not preload("res://gameplay/urban_v1/CobraSecretCar3D.gd").validate_record(record):
				_unconverted(result,"campaign.cobra_campaign.secret_owned.ashbend_coupe","invalid_secret_car",original_secret,true)
				continue
			proposal.world.ashbend_secret_car_claimed = true
			proposal.world.ashbend_secret_car = record
			_transform(result,"campaign.cobra_campaign.secret_owned.ashbend_coupe","world.ashbend_secret_car","carro cobre, posição, pintura e integridade preservados")
	if not garage.vehicles.is_empty() or garage.port_status != "parked" or garage.police_called or garage.alarm_remaining != -1.0:
		proposal.world.garage_rewards = garage

static func _fleet_record(source: Dictionary, region: String, coordinates_version: int, result: Dictionary) -> Dictionary:
	var script := str(source.get("script",""))
	if script not in V1_VEHICLE_SCRIPTS:
		_unconverted(result,"world.vehicle","untrusted_vehicle_script",source,true); return {}
	var archetype := str(source.get("archetype",""))
	if FLEET.spec(archetype).is_empty():
		_unconverted(result,"world.vehicle.archetype","unknown_vehicle",archetype,true); return {}
	var paint := str(source.get("paint","ffffff"))
	if not Color.html_is_valid(paint):
		_unconverted(result,"world.vehicle.paint","invalid_color",paint,true); return {}
	var values: Dictionary = source.get("values",{}) if source.get("values",{}) is Dictionary else {}
	var health := float(values.get("health",FLEET.spec(archetype).get("durability",100)))
	if health < 0 or health > float(FLEET.spec(archetype).get("durability",100)):
		_unconverted(result,"world.vehicle.values.health","out_of_range",health,true); return {}
	for key in values:
		if key != "health" and _meaningful(values[key]): _unconverted(result,"world.vehicle.values."+str(key),"unsupported_vehicle_state",values[key],true)
	var position := _position_v2([source.get("x",0),source.get("y",0)],region,coordinates_version)
	var record := {"archetype":archetype,"vehicle_id":str(source.get("name","imported_v1_vehicle")),"was_driven":true,
		"paint":paint,"position":position,"yaw":_yaw_v2(float(source.get("rotation",0))),"health":health,"region":region,"equipment":{}}
	_transform(result,"world.vehicle","world.vehicles[]","posição /16; yaw=-rotation-PI/2; saúde e pintura preservadas")
	return record

static func _personal_record(source: Dictionary, result: Dictionary) -> Dictionary:
	if bool(source.get("impounded",false)):
		_unconverted(result,"player.personal_car_state.impounded","no_equivalent",true,true)
		_decision(result,"personal_car_impounded","O V2 não possui estado equivalente seguro para apreensão da Monaliza.",{})
	if bool(source.get("broken",false)) and float(source.get("health",0)) > 0:
		_unconverted(result,"player.personal_car_state.broken","no_equivalent_with_positive_health",true,true)
	if bool(source.get("introduction_seen",false)):
		_unconverted(result,"player.personal_car_state.introduction_seen","presentation_state_not_persisted_in_v2",true,true)
	var flat := source.duplicate(true)
	flat.archetype = "monaliza"
	return _garage_record(flat,"personal_monaliza","monaliza",result)

static func _garage_record(source: Dictionary, id: String, archetype: String, result: Dictionary) -> Dictionary:
	var spec: Dictionary = EXTRA_FLEET.spec(archetype) if archetype == EXTRA_FLEET.ID else FLEET.spec(archetype)
	if spec.is_empty(): return {}
	var position_value: Variant = source.get("position",[source.get("x",0),source.get("y",0)])
	if not _position2(position_value): position_value = [0,0]
	var position := _position_v2(position_value,"harbor",2)
	var place := str(source.get("place_id",""))
	if source.get("in_garage",false) or maxf(absf(float(position[0])),absf(float(position[2]))) > 1000:
		place = "maciota"
		position = [0.0,0.04,0.0]
		_decision(result,id+"_interior_position","Posição interna V1 não é compatível; a proposta usa a baia V2 autorada.",{})
	var paint := str(source.get("paint",source.get("paint_color",source.get("color","ffffff"))))
	if not Color.html_is_valid(paint): paint = "ffffff"
	var health := float(source.get("health",spec.get("durability",100)))
	if health < 0 or health > float(spec.get("durability",100)):
		_unconverted(result,"vehicle."+id+".health","out_of_range",health,true); return {}
	return {"archetype":archetype,"region_id":"harbor","place_id":place,"was_driven":bool(source.get("was_driven",false)),
		"paint":paint,"position":position,"yaw":_yaw_v2(float(source.get("rotation",0))),"health":health}

static func _put_garage_vehicle(proposal: Dictionary, id: String, record: Dictionary, archetype: String) -> void:
	var garage: Dictionary = proposal.world.get("garage_rewards",_garage_default())
	var converted := record.duplicate(true)
	converted.erase("region"); converted.region_id = proposal.region_id; converted.place_id = proposal.place_id
	converted.archetype = archetype
	garage.vehicles[id] = converted
	proposal.world.garage_rewards = garage

static func _garage_default() -> Dictionary:
	return {"version":1,"port_status":"parked","alarm_remaining":-1.0,"police_called":false,"vehicles":{}}

static func _convert_cold(player: Dictionary, world: Dictionary, proposal: Dictionary, result: Dictionary) -> void:
	if not world.has("temperature") and not world.has("weather_clock"): return
	var temperature: Variant = world.get("temperature",100.0)
	var clock: Variant = world.get("weather_clock",0.0)
	if not _finite_number(temperature) or float(temperature) < 0 or float(temperature) > 100:
		_unconverted(result,"world.temperature","out_of_range",temperature,true); return
	if not _finite_number(clock) or float(clock) < 0:
		_unconverted(result,"world.weather_clock","out_of_range",clock,true); return
	proposal.world.cold = {"version":1,"temperature":float(temperature),"exposure":0.0,"damage_fraction":0.0,"weather_clock":fposmod(float(clock),240.0)}
	_transform(result,"world.temperature + world.weather_clock","world.cold","temperatura preservada; relógio normalizado ao ciclo 0..240; exposição ausente inicia em zero")
	if bool(player.get("mountain_thermal_coat",false)) and not proposal.economy.outfits.has("dante_arctic"):
		_unconverted(result,"player.mountain_thermal_coat","ownership_not_proven",true,true)
		_decision(result,"thermal_coat","O booleano V1 não comprova qual roupa V2 deve ser concedida.",{})

static func _convert_unsupported(player: Dictionary, campaign: Dictionary, world: Dictionary, source: Dictionary, result: Dictionary) -> void:
	for key in ["bank_incident","npc_medical_care","coroner_cases"]:
		if _meaningful(campaign.get(key)):
			_unconverted(result,"campaign."+key,"no_v2_contract",campaign[key],true)
	if int(campaign.get("coroner_staff_serial",0)) != 0:
		_unconverted(result,"campaign.coroner_staff_serial","no_v2_contract",campaign.coroner_staff_serial,true)
	for key in ["secret_car_leads","chop_shop_deliveries","chop_shop_total_scrap"]:
		if int(player.get(key,0)) != 0:
			_unconverted(result,"player."+key,"no_v2_contract",player[key],true)
	if _meaningful(player.get("weapon_customization")):
		_unconverted(result,"player.weapon_customization","no_v2_save_field",player.weapon_customization,true)
	var cobra: Variant = campaign.get("cobra_campaign",{})
	if cobra is Dictionary:
		for key in ["day","day_elapsed","unlock_days","hour","unlocked","optional_flags","calendar","civilian_reputation","cobra_access"]:
			if _meaningful(cobra.get(key)):
				_unconverted(result,"campaign.cobra_campaign."+key,"no_exact_v2_equivalent",cobra[key],true)
		var defeated := bool(cobra.get("defeated",false))
		if defeated != _cobra_completed(cobra).has("cobra_finale"):
			_incompatible(result,"cobra_defeated_mismatch","O marcador defeated diverge da conclusão de cobra_finale.",{"defeated":defeated})
	if bool(world.get("north_access_lower",false)):
		_unconverted(result,"world.north_access_lower","runtime_topology_state",true,true)
	if source.wanted is Dictionary:
		var wanted: Dictionary = source.wanted
		for key in wanted:
			if key in ["current_stars","crime_points","hidden_time","dispatch_timer","deployed_this_pursuit"] and _meaningful(wanted[key]):
				_warn(result,"wanted_reset","O leitor produtivo V1 já restaura perseguição zerada; a proposta mantém crime_points=0.",{"field":key,"source":wanted[key]})
	_capture_unknown(source,TOP_KEYS,"",result)
	_capture_unknown(campaign,CAMPAIGN_KEYS,"campaign.",result)
	_capture_unknown(player,PLAYER_KEYS,"player.",result)
	_capture_unknown(world,WORLD_KEYS,"world.",result)

static func _capture_unknown(source: Dictionary, known: Array, prefix: String, result: Dictionary) -> void:
	for key_value in source:
		var key := str(key_value)
		if not known.has(key): _unconverted(result,prefix+key,"unknown_field",source[key_value],true)

static func _activity_race_known(id: String) -> bool:
	var definitions := preload("res://activities/ActivityDefinitions.gd")
	return definitions.RACES.RACES.has(id) or definitions.races("harbor").has(id)

static func _position_v2(value: Array, region: String, coordinates_version: int) -> Array:
	var x := float(value[0])
	var y := float(value[1])
	if region == "mountain" and coordinates_version < 2:
		x += 4300.0
		y -= 4960.0
	return [x/16.0,0.0,y/16.0]

static func _yaw_v2(rotation_2d: float) -> float:
	return -rotation_2d-PI/2.0

static func _ammo_fits(id: String, magazine: int, reserve: int) -> bool:
	var base := int(WEAPONS.WEAPONS[id].magazine_size)
	if base < 0: return magazine == -1 and reserve == -1
	var maximum := base
	if id in ["pistol","smg","ak47","m4a1"]: maximum = int(floor(float(base)*1.5))
	elif id == "shotgun": maximum += 2
	elif id == "hunting_rifle": maximum += 3
	return magazine >= 0 and magazine <= maximum and reserve >= 0 and reserve <= ECONOMY.MAX_AMMO

static func _cobra_completed(cobra: Dictionary) -> Array[String]:
	var raw: Variant = cobra.get("completed",cobra.get("completed_missions",[]))
	if raw is Dictionary:
		var result: Array[String] = []
		for id in raw:
			if raw[id] == true: result.append(str(id))
		return result
	return _string_array(raw)

static func _cobra_reward_claimed(cobra: Dictionary, id: String) -> bool:
	var value: Variant = cobra.get("reward_claimed",{})
	return value is Dictionary and value.get(id,false) == true

static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value: result.append(str(entry))
	return result

static func _position2(value: Variant) -> bool:
	return value is Array and value.size() >= 2 and _finite_number(value[0]) and _finite_number(value[1])

static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _meaningful(value: Variant) -> bool:
	if value == null: return false
	match typeof(value):
		TYPE_BOOL: return bool(value)
		TYPE_INT,TYPE_FLOAT: return float(value) != 0.0
		TYPE_STRING,TYPE_STRING_NAME: return not str(value).is_empty()
		TYPE_ARRAY,TYPE_DICTIONARY: return not value.is_empty()
	return true

static func _transform(result: Dictionary, source: String, target: String, rule: String) -> void:
	result.transformations.append({"source":source,"target":target,"rule":rule})

static func _warn(result: Dictionary, code: String, message: String, details: Dictionary) -> void:
	result.warnings.append({"code":code,"message":message,"details":details.duplicate(true)})

static func _incompatible(result: Dictionary, code: String, message: String, details: Dictionary) -> void:
	result.incompatibilities.append({"code":code,"message":message,"details":details.duplicate(true)})

static func _decision(result: Dictionary, code: String, message: String, details: Dictionary) -> void:
	result.decisions_required.append({"code":code,"message":message,"details":details.duplicate(true)})

static func _unconverted(result: Dictionary, path: String, reason: String, value: Variant, decision: bool) -> void:
	result.unconverted_fields.append({"path":path,"reason":reason,"value":value.duplicate(true) if value is Array or value is Dictionary else value})
	if decision: _decision(result,"unconverted:"+path,"Campo V1 não foi descartado silenciosamente.",{"path":path,"reason":reason})

static func _finalize(result: Dictionary) -> void:
	result.ok = result.source_valid and result.validator.accepted and result.incompatibilities.is_empty()
	result.ready_for_publication = result.ok and result.decisions_required.is_empty() and result.unconverted_fields.is_empty()
