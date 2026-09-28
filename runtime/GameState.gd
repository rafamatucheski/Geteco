extends RefCounted
const ECONOMY := preload("res://systems/economy/Economy.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
const CANONICAL_CAMPAIGN := preload("res://systems/campaign/CanonicalCampaign.gd")
const INTRO := preload("res://systems/Progression.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SCHEMA_VERSION := 3
const RPG_REWARD_CANONICAL := "mountain_waterfall_secret_rpg_01"
const RPG_REWARD_V2_ALIAS := "mountain_cave_rpg"
const CARGO_REWARDS := [
	{"id":"mountain_cargo_plane_treasure_01","kind":"cash","amount":1800},
	{"id":"mountain_cargo_plane_smg_01","kind":"weapon","item":"smg","amount":1,"ammo":20},
]
var economy = ECONOMY.new()
var campaign = CAMPAIGN.new()
var canonical_campaign = CANONICAL_CAMPAIGN.new()
var intro = INTRO.new()
var world
var region_id := "harbor"
var place_id := ""
var checkpoint_id := "maciota"
var world_state: Dictionary = {"time":.32,"weather":0,"vehicles":[],"rewards":[],"outfit":"dante_classic"}
var combat_state: Dictionary = {}
var equipped_weapon: String:
	get: return economy.equipped_weapon
func owns_weapon(id: String) -> bool: return economy.owns_weapon(id)
func get_ammo(id: String) -> Dictionary: return economy.get_ammo(id)
func consume_ammo(id: String, amount: int = 1) -> bool: return can_attack() and economy.consume_ammo(id,amount)
func add_ammo(id: String, amount: int) -> bool: return economy.add_ammo(id,amount)
func reload_weapon(id: String, capacity: int = -1) -> bool: return weapons_allowed() and economy.reload_weapon(id,capacity)
func spend(amount: int, receipt: String) -> bool: return economy.spend(amount,receipt)
func grant_weapon(id: String) -> bool: return economy.grant_weapon(id)
func equip_weapon(id: String) -> bool:
	if id == "": id = "fists"
	if id != "fists" and not weapons_allowed(): return false
	if economy.grid_handbag() and id in preload("res://systems/inventory/GridInventory.gd").LONG: return false
	if id != "fists" and is_instance_valid(world) and is_instance_valid(world.player.ski_controller) and world.player.ski_controller.skiing: return false
	return economy.equip_weapon(id)
func weapons_allowed() -> bool: return place_id != "maciota" and place_id != "harbor_garage"
func can_attack() -> bool:
	if not weapons_allowed(): return false
	if economy.grid_handbag() and equipped_weapon in preload("res://systems/inventory/GridInventory.gd").LONG: return false
	if is_instance_valid(world):
		if is_instance_valid(world.player.ski_controller) and world.player.ski_controller.skiing: return false
		if world.player.input_locked or world.driving.occupied: return false
		if world.gameplay and world.gameplay.health <= 0: return false
	return true
func set_location(region: String, place: String = "") -> void:
	region_id = region
	place_id = place
	if not weapons_allowed(): economy.equip_weapon("fists")
func snapshot() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION,"game":"geteco_v2","region_id":region_id,"place_id":place_id,"checkpoint_id":checkpoint_id,
		"economy":economy.snapshot(),"campaign":campaign.snapshot(),"canonical_campaign":canonical_campaign.snapshot(),
		"intro":intro.snapshot(),"world":world_state.duplicate(true),"combat":combat_state.duplicate(true)}
func restore_snapshot(data: Dictionary) -> bool:
	if data.get("game") != "geteco_v2": return false
	var schema := int(data.get("schema_version",0))
	if schema == 1: return _migrate_intro(data)
	if schema == 2: return _migrate_schema_2(data)
	if schema != SCHEMA_VERSION: return false
	for key in ["economy","campaign","canonical_campaign","intro","world","combat"]:
		if not data.get(key) is Dictionary: return false
	if not data.combat.is_empty() and not preload("res://gameplay/Gameplay.gd").validate_snapshot(data.combat): return false
	for key in ["region_id","place_id","checkpoint_id"]:
		if not data.get(key) is String or str(data[key]).length() > 128: return false
	if data.region_id not in ["harbor","mountain"]: return false
	# Reject the entire snapshot before touching live state. Maciota is a native
	# Harbor interior and deliberately does not live in PlaceCatalog.
	if not _location_is_compatible(data.region_id,data.place_id): return false
	if data.world.has("pedestrian"):
		var pedestrian: Variant = data.world.pedestrian
		if not pedestrian is Dictionary or pedestrian.get("region","") != data.region_id: return false
		var position: Variant = pedestrian.get("position")
		if not position is Array or position.size() != 3: return false
		for coordinate in position:
			if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)) or absf(float(coordinate)) > 100000: return false
	var next_economy = ECONOMY.new()
	var next_campaign = CAMPAIGN.new()
	var next_canonical_campaign = CANONICAL_CAMPAIGN.new()
	var next_intro = INTRO.new()
	if not next_economy.restore_snapshot(data.economy) or not next_campaign.restore_snapshot(data.campaign): return false
	if not next_canonical_campaign.restore_snapshot(data.canonical_campaign) or not next_intro.restore_snapshot(data.intro): return false
	var time_value: Variant = data.world.get("time",.32)
	if typeof(time_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(time_value)) or time_value < 0 or time_value > 1: return false
	if not data.world.get("rewards",[]) is Array or not data.world.get("vehicles",[]) is Array: return false
	if data.world.has("ashbend_secret_car_claimed") and not data.world.ashbend_secret_car_claimed is bool: return false
	if data.world.has("ashbend_secret_car") and (not data.world.ashbend_secret_car is Dictionary or not preload("res://gameplay/urban_v1/CobraSecretCar3D.gd").validate_record(data.world.ashbend_secret_car)): return false
	if data.world.get("vehicles",[]).size() > 64: return false
	for vehicle in data.world.get("vehicles",[]):
		if not vehicle is Dictionary or not preload("res://runtime/FleetState.gd").validate(vehicle): return false
	if data.world.has("motocross") and (not data.world.motocross is Dictionary or not preload("res://activities/motocross/MotocrossProgress.gd").validate_snapshot(data.world.motocross)): return false
	if data.world.has("motocross") and not preload("res://activities/motocross/MotocrossProgress.gd").validate_wallet(data.world.motocross,data.economy): return false
	if data.world.has("activities"):
		if not data.world.activities is Dictionary: return false
		if not preload("res://activities/Activities.gd").validate_snapshot(data.world.activities): return false
	if data.world.has("mountain_progression"):
		if not data.world.mountain_progression is Dictionary or not preload("res://activities/MountainProgression.gd").validate_snapshot(data.world.mountain_progression): return false
	if data.world.has("mission_world"):
		if not data.world.mission_world is Dictionary: return false
		var contract: Dictionary = data.world.get("activities",{}).get("tow_contract",{})
		if not preload("res://runtime/MissionWorld.gd").validate_ownership(data.world.mission_world,next_campaign.active_id,contract): return false
	if data.world.has("services"):
		if not data.world.services is Dictionary or not preload("res://runtime/Services.gd").validate_snapshot(data.world.services): return false
	if data.world.has("robberies"):
		if not data.world.robberies is Dictionary or not preload("res://runtime/Robberies.gd").validate_snapshot(data.world.robberies): return false
	if data.world.has("arrival"):
		if not data.world.arrival is Dictionary or not preload("res://runtime/Arrival.gd").validate_snapshot(data.world.arrival): return false
	if data.world.has("garage_rewards"):
		if not data.world.garage_rewards is Dictionary or not preload("res://runtime/GarageRewards.gd").validate_snapshot(data.world.garage_rewards): return false
		if data.world.garage_rewards.vehicles.has("personal_monaliza") and not data.campaign.completed.has("primeiro_giro"): return false
	if data.world.has("cold"):
		if not data.world.cold is Dictionary or not preload("res://runtime/ColdSurvival.gd").validate_snapshot(data.world.cold): return false
	if data.world.has("port_containers") and not preload("res://gameplay/urban_v1/PortContainerState.gd").validate_snapshot(data.world.port_containers): return false
	# Optional for compatibility with V2 saves written before port/cemetery state
	# existed. Once present, both halves are mandatory and validated atomically.
	if data.world.has("urban_operations"):
		if not data.world.urban_operations is Dictionary or not preload("res://gameplay/urban_v1/UrbanOperations.gd").validate_snapshot(data.world.urban_operations): return false
	if not _validate_cross_contracts(next_economy,next_campaign,next_canonical_campaign,data.world): return false
	var next_world: Dictionary = _normalize_reward_aliases(data.world)
	economy = next_economy
	campaign = next_campaign
	canonical_campaign = next_canonical_campaign
	intro = next_intro
	world_state = next_world
	combat_state = data.combat.duplicate(true)
	checkpoint_id = data.checkpoint_id
	set_location(data.region_id,data.place_id)
	return true

func _migrate_schema_2(data: Dictionary) -> bool:
	# Schema 2 predates the canonical nine-beat ledger. There is no trustworthy
	# field to infer it from, so compatibility is explicit: start that independent
	# ledger at its authored initial state and preserve every existing V2 field.
	var migrated := data.duplicate(true)
	migrated.schema_version = SCHEMA_VERSION
	migrated.canonical_campaign = CANONICAL_CAMPAIGN.new().snapshot()
	return restore_snapshot(migrated)

func _migrate_intro(data: Dictionary) -> bool:
	var legacy = INTRO.new()
	if not legacy.restore_snapshot(data): return false
	intro = legacy
	economy = ECONOMY.new()
	campaign = CAMPAIGN.new()
	canonical_campaign = CANONICAL_CAMPAIGN.new()
	for item in legacy.snapshot().inventory:
		if item == "garage_part": economy.grant_item(item)
		elif preload("res://gameplay/WeaponCatalog.gd").WEAPONS.has(item): economy.grant_weapon(item)
	checkpoint_id = "maciota"
	set_location("harbor","maciota" if legacy.location_id == "harbor_garage" else "")
	return true

static func _location_is_compatible(region: String, place: String) -> bool:
	if place.is_empty(): return true
	if place == "maciota": return region == "harbor"
	var definition: Dictionary = PLACES.get_definition(place)
	return not definition.is_empty() and definition.get("region","") == region

static func _canonical_reward_id(id: String) -> String:
	return RPG_REWARD_CANONICAL if id in [RPG_REWARD_CANONICAL,RPG_REWARD_V2_ALIAS] else id

static func _reward_aliases(id: String) -> Array[String]:
	if _canonical_reward_id(id) == RPG_REWARD_CANONICAL:
		return [RPG_REWARD_CANONICAL,RPG_REWARD_V2_ALIAS]
	return [id]

static func _world_reward_contracts() -> Dictionary:
	var result := {}
	for definition in PLACES.definitions():
		for reward in definition.get("rewards",[]):
			if reward is Dictionary and reward.get("id") is String:
				result[_canonical_reward_id(reward.id)] = reward.duplicate(true)
	for reward in CARGO_REWARDS:
		result[_canonical_reward_id(reward.id)] = reward.duplicate(true)
	return result

static func _reward_receipt(transactions: Dictionary, canonical_id: String, amount: int) -> bool:
	for alias in _reward_aliases(canonical_id):
		var entry: Variant = transactions.get("reward:"+alias)
		if entry is Dictionary and entry.get("kind","") == "reward" and entry.get("item","") == alias and int(entry.get("amount",-1)) == amount:
			return true
	return false

static func _validate_cross_contracts(next_economy, next_campaign, next_canonical_campaign, saved_world: Dictionary) -> bool:
	var wallet: Dictionary = next_economy.snapshot()
	var transactions: Dictionary = wallet.transactions
	var campaign_data: Dictionary = next_campaign.snapshot()
	for id in campaign_data.claimed_rewards:
		var amount := int(MISSIONS.MISSIONS[id].reward)
		if not _reward_receipt(transactions,"campaign:"+str(id),amount): return false
	for id in campaign_data.pending_rewards:
		var key := "reward:campaign:"+str(id)
		if transactions.has(key) and not _reward_receipt(transactions,"campaign:"+str(id),int(campaign_data.pending_rewards[id])): return false
	for key_value in transactions.keys():
		var key := str(key_value)
		if key.begins_with("reward:campaign:"):
			var id := key.trim_prefix("reward:campaign:")
			if not MISSIONS.ORDER.has(id) or not campaign_data.completed.has(id): return false
			if not _reward_receipt(transactions,"campaign:"+id,int(MISSIONS.MISSIONS[id].reward)): return false
	var canonical_data: Dictionary = next_canonical_campaign.snapshot()
	for id in canonical_data.completed_contracts:
		var definition := {}
		for candidate in next_canonical_campaign.catalog.get("district_one_contracts",[]):
			if candidate.get("id","") == id: definition = candidate; break
		if definition.is_empty() or not _reward_receipt(transactions,"canonical_contract:"+str(id),int(definition.reward)): return false
	for key_value in transactions.keys():
		var key := str(key_value)
		if key.begins_with("reward:canonical_contract:"):
			var id := key.trim_prefix("reward:canonical_contract:")
			if not canonical_data.completed_contracts.has(id): return false
	var contracts := _world_reward_contracts()
	# A receipt may legitimately precede its world marker when a save is
	# interrupted between wallet publication and marker reconciliation. Validate
	# the receipt payload here, but keep that state loadable so the pickup can add
	# only the missing marker without paying again.
	for canonical_id_value in contracts:
		var canonical_id := str(canonical_id_value)
		var contract: Dictionary = contracts[canonical_id]
		var has_receipt := false
		for alias in _reward_aliases(canonical_id):
			if transactions.has("reward:"+alias): has_receipt = true
		if not has_receipt: continue
		var expected_amount := int(contract.get("amount",0)) if contract.get("kind","") == "cash" else 0
		if not _reward_receipt(transactions,canonical_id,expected_amount): return false
		if contract.get("kind","") == "weapon" and not wallet.weapons.has(contract.get("item","")): return false
	var seen := {}
	for value in saved_world.get("rewards",[]):
		if not value is String or value.length() > 128 or seen.has(value): return false
		seen[value] = true
		var canonical_id := _canonical_reward_id(value)
		if not contracts.has(canonical_id): return false
		var contract: Dictionary = contracts[canonical_id]
		match str(contract.get("kind","")):
			"cash":
				if not _reward_receipt(transactions,canonical_id,int(contract.get("amount",0))): return false
			"weapon":
				if not wallet.weapons.has(contract.get("item","")): return false
			_:
				if int(wallet.inventory.get(contract.get("item",""),0)) < int(contract.get("amount",1)): return false
	return true

static func _normalize_reward_aliases(saved_world: Dictionary) -> Dictionary:
	var result := saved_world.duplicate(true)
	var rewards: Array = result.get("rewards",[])
	if rewards.has(RPG_REWARD_CANONICAL) or rewards.has(RPG_REWARD_V2_ALIAS):
		if not rewards.has(RPG_REWARD_CANONICAL): rewards.append(RPG_REWARD_CANONICAL)
		if not rewards.has(RPG_REWARD_V2_ALIAS): rewards.append(RPG_REWARD_V2_ALIAS)
	result.rewards = rewards
	return result
