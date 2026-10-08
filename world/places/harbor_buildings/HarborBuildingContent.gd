extends RefCounted
## Stable content varies by storey, with persistent rewards in every building.
## The catalog exposes ALL receipts, while only the active floor spawns them.
const PROGRAMS := {
	"residential":["family", "bedroom", "artist", "library", "music", "shared_kitchen"],
	"office":["reception", "drafting", "records", "meeting", "press", "staff"],
	"retail":["shop", "tailor", "stockroom", "studio", "staff"],
	"industrial":["workshop", "packing", "dispatch", "toolroom", "staff"],
	"hospitality":["cafe", "guest", "kitchen", "lounge", "laundry"],
	"civic":["reception", "records", "meeting", "library", "staff"],
}
const PALETTES := [
	{"wood":"805a3c","cloth":"677b74","wall":"c4bda7","accent":"947248"},
	{"wood":"694e3f","cloth":"6a788b","wall":"bfc2b5","accent":"a57753"},
	{"wood":"91714a","cloth":"98745f","wall":"c7bfaa","accent":"5e7774"},
	{"wood":"6f6251","cloth":"8b797e","wall":"b5b5a8","accent":"7c8b66"},
]

static func family(definition: Dictionary) -> String:
	var value := str(definition.get("archetype", ""))
	if PROGRAMS.has(value): return value
	var kind := str(definition.get("building_kind", ""))
	if "warehouse" in kind or "workshop" in kind or "industrial" in kind: return "industrial"
	if "shop" in kind or "laundromat" in kind: return "retail"
	if "office" in kind or "customs" in str(definition.id): return "office"
	if "hotel" in kind or "cafe" in kind: return "hospitality"
	return "residential"

static func floor_spec(definition: Dictionary, floor_index: int) -> Dictionary:
	var seed_value := absi(hash(str(definition.id)))
	if floor_index == int(definition.floor_count):
		return {"program":"rooftop", "family":family(definition), "occupants":[], "rewards":[rooftop_reward(definition)]}
	var kind := family(definition)
	var choices: Array = PROGRAMS[kind]
	var program: String = choices[(seed_value + floor_index) % choices.size()]
	# Public ground floors keep their recognisable street purpose.
	if floor_index == 0:
		if kind == "office" or kind == "civic": program = "reception"
		elif kind == "retail": program = "laundry" if "laundromat" in str(definition.get("building_kind", "")) else "shop"
		elif kind == "industrial": program = "workshop"
		elif kind == "hospitality": program = "cafe"
		if str(definition.get("source_id", "")) == "Aquarium": program = "aquarium"
		elif str(definition.get("source_id", "")) == "MaritimeMuseum": program = "gallery"
	var size: Vector2 = definition.size
	var compact := size.x < 8.8 or size.y < 8.4
	var x := size.x * .29 if not compact else size.x * .5 - 1.15
	var back := -size.y * .5 + (1.15 if not compact else .65)
	var front := size.y * .5 - 1.40
	var entrance: Vector3 = definition.get("entrance_local", Vector3(0, 0, size.y * .5))
	var front_side := -1.0 if floor_index == 0 and entrance.x > 1.3 else 1.0
	var cash_point := Vector3(-x, .03, size.y * .5 - 1.15) if not compact else Vector3(x, .03, size.y * .5 - .85)
	if front_side < 0 and not compact: cash_point = Vector3(1.6, .03, -2.3)
	var supply_point := Vector3(1.60, .03, -.40) if not compact else Vector3(x, .03, .65)
	var prefix := str(definition.id) + "_floor_%02d" % floor_index
	var supply: String = ["water", "first_aid", "sandwich", "lockpick", "cereal_bar"][(seed_value + floor_index * 3) % 5]
	var rewards: Array[Dictionary] = []
	if floor_index == 0 or (seed_value + floor_index) % 3 == 0:
		rewards.append({"id":prefix + "_supply", "kind":"item", "item":supply, "amount":1, "local_position":supply_point, "floor":floor_index})
	var secret := secret_spec(definition, floor_index)
	if not secret.is_empty(): cash_point = secret.reward_position
	if not secret.is_empty() or (seed_value + floor_index) % 3 == 1:
		rewards.append({"id":prefix + "_cache", "kind":"cash", "amount":80 + (seed_value % 11) * 25 + floor_index * 65,
			"local_position":cash_point, "floor":floor_index, "secret":true, "locked":not secret.is_empty()})
	var activity := "read"
	if program in ["workshop", "toolroom", "drafting", "studio", "artist", "tailor"]: activity = "repair"
	elif program in ["kitchen", "shared_kitchen", "cafe", "staff"]: activity = "cook"
	elif program in ["packing", "stockroom", "dispatch", "shop", "laundry", "aquarium"]: activity = "check"
	elif program in ["reception", "meeting", "press", "gallery"]: activity = "write"
	var occupants: Array[Dictionary] = [
		{"id":prefix + "_worker", "name":["Lia", "Rui", "Helena", "Caio", "Marta", "Joel"][(seed_value + floor_index) % 6],
			"position":Vector3(x, .03, back + .98), "yaw":PI, "activity":activity, "identity":seed_value % 9000 + floor_index * 7,
			"appearance":{"female":(seed_value + floor_index) % 2 == 0, "top":1, "coat":PALETTES[seed_value % 4].cloth}},
	]
	# A second human occupies the distinct front room in medium and large lots.
	if not compact and size.x >= 10.0 and size.y >= 10.5:
		occupants.append({"id":prefix + "_visitor", "name":["Nina", "Pedro", "Isa", "André"][(seed_value + floor_index) % 4],
			"position":Vector3(x * front_side, .03, front - 1.23), "yaw":0.0, "activity":"phone" if floor_index % 2 == 0 else "read",
			"identity":(seed_value + 831) % 9000 + floor_index * 7, "appearance":{"female":seed_value % 2 != 0, "top":5, "coat":"877567"}})
	# Vacant flats, working shifts and occupied illicit storage coexist by lot.
	var abandoned := kind == "industrial" and seed_value % 5 == 0
	if abandoned and floor_index % 2 == 1: occupants.clear()
	elif floor_index > 0 and (seed_value + floor_index) % 7 == 0: occupants.clear()
	return {"seed":seed_value, "family":kind, "program":program, "palette":PALETTES[(seed_value + floor_index) % 4].duplicate(),
		"size":size, "x":x, "back":back, "front":front, "front_side":front_side, "entrance":entrance,
		"compact":compact, "source_id":str(definition.get("source_id", "")), "abandoned":abandoned,
		"illicit":kind == "industrial" and seed_value % 4 == 0, "floor":floor_index, "rewards":rewards, "occupants":occupants}

static func all_rewards(definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in int(definition.floor_count): result.append_array(floor_spec(definition, index).rewards)
	result.append(rooftop_reward(definition))
	return result

static func rooftop_reward(definition: Dictionary) -> Dictionary:
	var size: Vector2 = definition.size
	return {"id":str(definition.id) + "_rooftop_cache", "kind":"cash", "amount":450 + absi(hash(str(definition.id))) % 700,
		"local_position":definition.get("roof_cache_position", Vector3(size.x * .26, .03, size.y * .22)), "floor":int(definition.floor_count), "secret":true}

static func secret_spec(definition: Dictionary, floor_index: int) -> Dictionary:
	var size: Vector2 = definition.size
	if size.x < 9.5 or size.y < 10.5 or floor_index >= int(definition.floor_count): return {}
	var seed_value := absi(hash(str(definition.id)))
	var selected := seed_value % int(definition.floor_count)
	if floor_index != selected: return {}
	return {"id":str(definition.id) + "_locked_%02d" % floor_index,
		"door_position":Vector3(-1.05, 0, -size.y * .5 + 2.30),
		"reward_position":Vector3(-size.x * .5 + .72, .03, -2.55),
		"room_left":-size.x * .5 + .24, "room_back":-size.y * .5 + .24, "room_front":-1.85}

static func valid_unlocks(value: Variant, definitions: Array) -> bool:
	if not value is Dictionary: return false
	var known := {}
	for definition in definitions:
		for index in int(definition.floor_count):
			var secret := secret_spec(definition, index)
			if not secret.is_empty(): known[secret.id] = true
	for id in value:
		if not known.has(id) or not value[id] is bool or value[id] != true: return false
	return true

static func floor_rewards(definition: Dictionary, index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reward in all_rewards(definition):
		if int(reward.floor) == index: result.append(reward)
	return result
