extends RefCounted
## O conteúdo estável varia por andar, com recompensas persistentes em todo prédio.
## O catálogo expõe TODOS os recibos, mas só o andar ativo os gera.
## Rework de variedade (15/10/2026): programa, planta, paleta, estações e
## pessoas saem de um gerador estável por prédio/andar (mesmo prédio sempre
## igual entre visitas e streaming); recompensas mantêm a fórmula original,
## porque ids e posições são persistidos no save.
const PROGRAMS := {
	"residential":["family", "bedroom", "artist", "library", "music", "shared_kitchen", "living", "kids"],
	"office":["reception", "drafting", "records", "meeting", "press", "staff"],
	"retail":["shop", "tailor", "stockroom", "studio", "staff"],
	"industrial":["workshop", "packing", "dispatch", "toolroom", "staff"],
	"hospitality":["cafe", "guest", "kitchen", "lounge", "laundry", "living"],
	"civic":["reception", "records", "meeting", "library", "staff"],
}
# Paletas compostas por prédio e andar a partir de listas curtas: centenas de
# combinações sem multiplicar materiais (o cache de MATERIALS é por cor/tipo).
const WOODS := ["805a3c", "694e3f", "91714a", "6f6251", "a47f58", "5a4636", "8d6a4f", "b39468"]
const CLOTHS := ["677b74", "6a788b", "98745f", "8b797e", "7d8a5a", "a0675a", "596a85", "8e8a6c", "6f5f78", "b08f5c"]
const WALLS := ["c4bda7", "bfc2b5", "c7bfaa", "b5b5a8", "c9b8a0", "aeb9b4", "c2b2a8", "bcc0c8"]
const ACCENTS := ["947248", "a57753", "5e7774", "7c8b66", "8a5a5a", "4f6a80", "b08a3e", "6d7a4a"]
const CABINETS := ["7a8879", "8a7a66", "6e7f8a", "a9a48f", "7f6a5a", "8c6f62"]
const LINENS := ["d4cbb8", "c9d0d4", "d8c6b8", "c8ccb4"]
const METALS := ["575a53", "3f4346", "6a6e66", "4c4a45"]
const HOME_FLOORS := ["8b6646", "7a5a3e", "9a7a58", "6e5544", "a08260"]
const WORK_FLOORS := ["7e817b", "8a8478", "6f7470", "8f8a7e", "77706a"]
const NAMES_F := ["Lia", "Helena", "Marta", "Nina", "Isa", "Rosa", "Bia", "Clara", "Dora", "Vera", "Lúcia", "Tânia"]
const NAMES_M := ["Rui", "Caio", "Joel", "Pedro", "André", "Beto", "Tião", "Davi", "Otávio", "Nando", "Lauro", "Ciro"]
const COATS := ["778775", "877567", "5d6f86", "8c5b4f", "6f6a4c", "4f5d55", "9a8a6a", "6b5878", "a3734e", "3f4a5a"]
const PANTS := ["414c4e", "2f3338", "5a4a3c", "3c4a5e", "6b6458"]
# Atividades por tipo de estação. O prédio sorteia (semente) quais delas cada
# estação aceita; a visita sorteia uma dessas (HarborBuildingOccupants).
const WORK_POOLS := {
	"desk":["write", "read", "phone", "sit_write", "sit_read", "coffee"],
	"kitchen":["cook", "cook", "coffee", "clean", "phone", "check"],
	"bench":["repair", "repair", "check", "clean", "coffee", "sit_write"],
	"stock":["check", "check", "write", "phone", "clean", "coffee"],
	"studio":["repair", "sit_write", "read", "coffee", "phone"],
	"home":["sit_read", "sit_phone", "write", "read", "coffee", "phone"],
}
const VISITOR_POOLS := {
	"residential":["sit_phone", "sit_read", "tv", "sleep", "wander", "coffee", "clean", "phone", "stretch"],
	"hospitality":["sit_phone", "coffee", "wander", "read", "sit_read", "stretch"],
	"office":["phone", "wander", "coffee", "read", "sit_phone", "check", "stretch"],
	"civic":["phone", "wander", "coffee", "read", "sit_read", "check"],
	"retail":["check", "wander", "phone", "clean", "coffee"],
	"industrial":["check", "wander", "coffee", "phone", "clean", "stretch"],
}
const BED_PROGRAMS := ["family", "bedroom", "guest", "kids"]
# Pesos de reação a ameaça por temperamento. Cada incidente sorteia de novo.
const REACTION_WEIGHTS := {
	"friendly":{"flee":3, "call":3, "hide":2, "beg":1, "freeze":1, "confront":1},
	"reserved":{"flee":2, "hide":3, "call":2, "freeze":2, "confront":1, "beg":1},
	"nervous":{"flee":3, "hide":2, "freeze":3, "beg":3, "call":1},
	"bold":{"confront":4, "call":2, "flee":1, "hide":1},
}

static func family(definition: Dictionary) -> String:
	var value := str(definition.get("archetype", ""))
	if PROGRAMS.has(value): return value
	var kind := str(definition.get("building_kind", ""))
	if "warehouse" in kind or "workshop" in kind or "industrial" in kind: return "industrial"
	if "shop" in kind or "laundromat" in kind: return "retail"
	if "office" in kind or "customs" in str(definition.id): return "office"
	if "hotel" in kind or "cafe" in kind: return "hospitality"
	return "residential"

## Gerador estável por prédio/andar/finalidade: o mesmo andar monta igual em
## toda visita e no streaming, mas prédios vizinhos não andam em fase.
static func rng(definition: Dictionary, floor_index: int, salt: String) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = hash("%s|%d|%s" % [str(definition.id), floor_index, salt])
	return generator

static func _pick(generator: RandomNumberGenerator, values: Array) -> Variant:
	return values[generator.randi() % values.size()]

static func _shuffled(generator: RandomNumberGenerator, values: Array) -> Array:
	var result := values.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var other := generator.randi() % (index + 1)
		var swap: Variant = result[index]
		result[index] = result[other]
		result[other] = swap
	return result

static func program_for(definition: Dictionary, floor_index: int) -> String:
	var kind := family(definition)
	# Ordem embaralhada por prédio: andares do mesmo prédio não se repetem até
	# esgotar a lista, e prédios vizinhos não seguem a mesma sequência.
	var choices := _shuffled(rng(definition, -1, "programs"), PROGRAMS[kind])
	var program: String = choices[floor_index % choices.size()]
	# Public ground floors keep their recognisable street purpose.
	if floor_index == 0:
		if kind == "office" or kind == "civic": program = "reception"
		elif kind == "retail": program = "laundry" if "laundromat" in str(definition.get("building_kind", "")) else "shop"
		elif kind == "industrial": program = "workshop"
		elif kind == "hospitality": program = "cafe"
		if str(definition.get("source_id", "")) == "Aquarium": program = "aquarium"
		elif str(definition.get("source_id", "")) == "MaritimeMuseum": program = "gallery"
	return program

static func palette_for(definition: Dictionary, floor_index: int, kind: String) -> Dictionary:
	var generator := rng(definition, floor_index, "palette")
	var house := rng(definition, 0, "house")
	# Parede e piso seguem o prédio (com troca ocasional por andar); móveis variam por andar.
	var wall: String = WALLS[(house.randi() + (floor_index if generator.randf() < .35 else 0)) % WALLS.size()]
	return {"wood":_pick(generator, WOODS), "cloth":_pick(generator, CLOTHS), "wall":wall,
		"accent":_pick(generator, ACCENTS), "cabinet":_pick(generator, CABINETS), "linen":_pick(generator, LINENS),
		"metal":_pick(generator, METALS), "rug":_pick(generator, CLOTHS),
		"floor":_pick(house, HOME_FLOORS if kind in ["residential", "hospitality"] else WORK_FLOORS)}

static func _station_kind(program: String, kind: String) -> String:
	if program in ["workshop", "toolroom"]: return "bench"
	if program in ["kitchen", "shared_kitchen", "cafe", "staff"]: return "kitchen"
	if program in ["packing", "stockroom", "dispatch", "shop", "laundry", "aquarium"]: return "stock"
	if program in ["studio", "artist", "tailor", "drafting"]: return "studio"
	if kind == "residential" or program in BED_PROGRAMS or program == "living": return "home"
	return "desk"

static func _choices(generator: RandomNumberGenerator, pool: Array, first: String, count: int) -> Array:
	var result := [first]
	for value in _shuffled(generator, pool):
		if result.size() >= count: break
		if value not in result: result.append(value)
	return result

static func _reactions(generator: RandomNumberGenerator, temperament: String, illicit: bool) -> Dictionary:
	var weights: Dictionary = REACTION_WEIGHTS[temperament].duplicate()
	# Variação individual: o mesmo temperamento não reage em proporção idêntica.
	for style in weights: weights[style] = snappedf(maxf(.2, float(weights[style]) * generator.randf_range(.6, 1.5)), .01)
	if illicit:
		# Quem guarda carga ilícita não chama a polícia; encara ou some.
		weights.erase("call")
		weights["confront"] = float(weights.get("confront", 1.0)) + 2.0
	return weights

static func _person(generator: RandomNumberGenerator, id: String, identity: int, illicit: bool) -> Dictionary:
	var female := generator.randf() < .5
	var personality: String = _pick(generator, ["friendly", "friendly", "reserved", "nervous"])
	var temperament := "bold" if generator.randf() < .2 else personality
	var top: int = _pick(generator, [0, 1, 2, 3, 5] + ([4] if female else []))
	return {"id":id, "identity":identity, "name":_pick(generator, NAMES_F if female else NAMES_M), "personality":personality,
		"temperament":temperament, "reactions":_reactions(generator, temperament, illicit),
		"appearance":{"female":female, "top":top, "coat":_pick(generator, COATS), "pants":_pick(generator, PANTS)}}

static func floor_spec(definition: Dictionary, floor_index: int) -> Dictionary:
	var seed_value := absi(hash(str(definition.id)))
	if floor_index == int(definition.floor_count):
		return {"program":"rooftop", "family":family(definition), "occupants":[], "rewards":[rooftop_reward(definition)]}
	var kind := family(definition)
	var program := program_for(definition, floor_index)
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
	var illicit := kind == "industrial" and seed_value % 4 == 0
	var people := rng(definition, floor_index, "people")
	var layout := rng(definition, floor_index, "layout")
	var layout_index := layout.randi() % 6
	# A estação principal desliza ao longo da parede do fundo; o móvel a
	# acompanha (HarborBuildingDressing usa work_x) sem invadir o corredor central
	# (borda esquerda do balcão mais largo, 1,23 m de meia largura, >= 1,37 m)
	# nem a parede lateral.
	var work_dx := 0.0
	if not compact:
		var lowest := 2.60 - x
		var highest := size.x * .5 - 1.55 - x
		work_dx = clampf(snappedf(layout.randf_range(-.55, .55), .05), minf(lowest, 0.0), maxf(highest, 0.0))
	var station_kind := _station_kind(program, kind)
	var work_pool: Array = WORK_POOLS[station_kind]
	var work_activity: String = _pick(people, work_pool)
	var worker := _person(people, prefix + "_worker", seed_value % 9000 + floor_index * 7, illicit)
	worker.merge({"position":Vector3(x + work_dx, .03, back + .98), "yaw":PI, "activity":work_activity,
		"activities":_choices(people, work_pool, work_activity, 3), "station":station_kind})
	var occupants: Array[Dictionary] = [worker]
	# Um segundo humano ocupa o cômodo da frente separado nos lotes médios e grandes.
	if not compact and size.x >= 10.0 and size.y >= 10.5:
		var pool: Array = VISITOR_POOLS[kind].duplicate()
		if program not in BED_PROGRAMS: pool.erase("sleep")
		var activity: String = _pick(people, pool)
		var vx := x * front_side + snappedf(people.randf_range(-.45, .45), .05)
		vx = signf(vx) * clampf(absf(vx), 1.75, size.x * .5 - .75)
		var visitor := _person(people, prefix + "_visitor", (seed_value + 831) % 9000 + floor_index * 7, illicit)
		var vz := front - 1.23 - snappedf(people.randf_range(0, .12), .02)
		visitor.merge({"position":Vector3(vx, .03, vz), "yaw":_pick(people, [0.0, 0.0, .55, -.55, 1.2, -1.2, PI]),
			"activity":activity, "activities":_choices(people, pool, activity, 3), "station":"room"})
		occupants.append(visitor)
		# Conversa em dupla: um segundo morador de frente para o visitante.
		if people.randf() < .3:
			for direction in ([-1.0, 1.0] if people.randf() < .5 else [1.0, -1.0]):
				var px: float = vx + direction * 1.05
				if absf(px) < 1.75 or absf(px) > size.x * .5 - .75 or signf(px) != signf(vx): continue
				# A dupla não fica no caminho de quem entra pela porta do térreo.
				if floor_index == 0 and absf(px - entrance.x) < 1.4: continue
				var partner := _person(people, prefix + "_partner", (seed_value + 1709) % 9000 + floor_index * 7, illicit)
				partner.merge({"position":Vector3(px, .03, vz), "yaw":-direction * PI * .5,
					"activity":"chat", "activities":["chat"], "station":"room", "partner":visitor.id})
				visitor.yaw = direction * PI * .5
				visitor.activity = "chat"
				visitor.activities = ["chat"]
				visitor.partner = partner.id
				occupants.append(partner)
				break
	# Apartamentos vagos, turnos de trabalho e depósitos ilícitos ocupados convivem por lote.
	var abandoned := kind == "industrial" and seed_value % 5 == 0
	if abandoned and floor_index % 2 == 1: occupants.clear()
	elif floor_index > 0 and (seed_value + floor_index) % 7 == 0: occupants.clear()
	return {"seed":seed_value, "family":kind, "program":program, "palette":palette_for(definition, floor_index, kind),
		"layout":layout_index, "work_dx":work_dx, "decor_seed":hash(prefix + "|decor"),
		"size":size, "x":x, "back":back, "front":front, "front_side":front_side, "entrance":entrance,
		"compact":compact, "source_id":str(definition.get("source_id", "")), "abandoned":abandoned,
		"illicit":illicit, "floor":floor_index, "rewards":rewards, "occupants":occupants}

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
