extends RefCounted
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const SECRETS := preload("res://runtime/desert/DesertSecretState.gd")
const BANDITS := preload("res://runtime/desert/DesertBanditEncounter.gd")
static func valid(world: Dictionary, economy: Dictionary) -> bool:
	if not preload("res://runtime/desert/DesertContractState.gd").validate_wallet(world,economy): return false
	if world.has(SECRETS.KEY) and not SECRETS.valid(world[SECRETS.KEY]): return false
	if world.has(BANDITS.STATE_KEY) and not BANDITS.valid_state(world[BANDITS.STATE_KEY]): return false
	if world.has("desert_discoveries") and not preload("res://runtime/desert/expansion/DesertDiscoveryState.gd").valid(world.desert_discoveries): return false
	if world.has("desert_story") and not STORY.valid(world.desert_story): return false
	if not RACE.validate_wallet(RACE.data(world),economy): return false
	if world.has("desert_garage") and not GARAGE.valid(world.desert_garage,economy): return false
	if world.has("desert_fleet"):
		if not world.desert_fleet is Dictionary or world.desert_fleet.size()>5: return false
		var bought: Dictionary = GARAGE.data(world).purchased
		for id in world.desert_fleet:
			var car: Variant = world.desert_fleet[id]
			if not car is Dictionary or car.get("vehicle_id","")!=id: return false
			if bought.get(car.get("archetype",""),"")!=id: return false
			if not preload("res://runtime/FleetState.gd").validate(car): return false
	if world.has("desert_drag"):
		if "digo" in world.desert_drag.get("completed_rivals",[]) and not world.get("digo",{}).get("desert_raced",false): return false
	return true
