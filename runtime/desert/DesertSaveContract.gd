extends RefCounted
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const INSTRUMENTS := preload("res://activities/desert_drag/DragInstrumentStyles.gd")
const SECRETS := preload("res://runtime/desert/DesertSecretState.gd")
const BANDITS := preload("res://runtime/desert/DesertBanditEncounter.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
static func valid(world: Dictionary, economy: Dictionary) -> bool:
	if not preload("res://activities/desert_drag/DragRivalChallengeProgress.gd").validate_world(world,economy): return false
	if not preload("res://activities/desert_drag/DragNightProgress.gd").validate_world(world,economy): return false
	if world.has("desert_cargo_heist") and not preload("res://gameplay/desert_heist/DesertHeistState.gd").valid(world.desert_cargo_heist): return false
	if not preload("res://runtime/desert/canyon/CanyonState.gd").validate_wallet(world,economy): return false
	if not preload("res://runtime/TakeshiHonor.gd").validate_world(world,economy): return false
	if not preload("res://runtime/desert/community/DesertCommunityState.gd").validate_wallet(world,economy): return false
	if not preload("res://activities/desert_wash/DesertWashState.gd").validate_world(world,economy): return false
	if not preload("res://gameplay/mining/jobs/MiningYardJobState.gd").validate_wallet(world,economy): return false
	if world.has("secret_fast_travel") and not preload("res://runtime/secret_travel/SecretTravelState.gd").valid(world.secret_fast_travel): return false
	if not preload("res://runtime/desert/DesertContractState.gd").validate_wallet(world,economy): return false
	if world.has(SECRETS.KEY) and not SECRETS.valid(world[SECRETS.KEY]): return false
	if world.has(BANDITS.STATE_KEY) and not BANDITS.valid_state(world[BANDITS.STATE_KEY]): return false
	if world.has("desert_discoveries") and not preload("res://runtime/desert/expansion/DesertDiscoveryState.gd").valid(world.desert_discoveries): return false
	if world.has("desert_story") and not STORY.valid(world.desert_story): return false
	if not preload("res://runtime/desert/act2/VicenteAct2State.gd").validate_wallet(world,economy): return false
	if not RACE.validate_wallet(RACE.data(world),economy): return false
	if not INSTRUMENTS.validate_wallet(world,economy): return false
	if world.has("desert_garage") and not GARAGE.valid(world.desert_garage,economy): return false
	if world.has("desert_fleet"):
		# Catalogue editions and the one honor prize share this persistent fleet.
		if not world.desert_fleet is Dictionary or world.desert_fleet.size()>preload("res://gameplay/desert_cars/DesertCarCatalog.gd").IDS.size()+2: return false
		var bought: Dictionary = GARAGE.data(world).purchased
		for id in world.desert_fleet:
			var car: Variant = world.desert_fleet[id]
			if not car is Dictionary or car.get("vehicle_id","")!=id: return false
			if id == "takeshi_supra":
				if world.get("takeshi",{}).get("reward","") != "car" or car.get("archetype","") != "supra_a80": return false
			elif id == LETTERS.CAR_ID:
				if car.get("archetype","") != LETTERS.CAR_ARCHETYPE or RECEIPTS.lookup(economy,"reward",LETTERS.CAR_RECEIPT).is_empty(): return false
			elif bought.get(car.get("archetype",""),"")!=id: return false
			if not preload("res://runtime/FleetState.gd").validate(car): return false
	if world.has("desert_cave_ammo") and not preload("res://runtime/desert/wilds/CaveBuild.gd").valid_ammo_state(world.desert_cave_ammo): return false
	if world.has("desert_drag"):
		if "digo" in world.desert_drag.get("completed_rivals",[]) and not world.get("digo",{}).get("desert_raced",false): return false
	return true
