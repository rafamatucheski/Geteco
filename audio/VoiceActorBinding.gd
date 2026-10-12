extends RefCounted
## Identity belongs to the emitting body. Resolve only on speech events; never
## infer gender from a name, pitch, scene order or a fresh random roll.
const NAMED := {
	"Raul": ["raul", "raul_sewer", "male"], "Cida": ["cida", "cida", "female"],
	"Beto": ["beto", "beto", "male"], "Seu Abel": ["seu abel", "seu_abel", "male"],
	"Dona Marlene": ["dona marlene", "dona_marlene", "female"], "Zeca": ["zeca", "zeca", "male"],
	"O Maluco": ["o maluco", "o_maluco", "male"], "Padre Nicanor": ["padre nicanor", "padre_nicanor", "male"],
	"Tita": ["tita", "tita", "female"], "Tonho": ["tonho", "tonho", "male"],
	"Dona Nena": ["dona nena", "dona_nena", "female"], "Dona Zefa": ["dona zefa", "dona_zefa", "female"],
	"Beto Cascavel": ["beto cascavel", "beto_cascavel", "male"], "Ermitão Jacó": ["ermitão jacó", "ermitao_jaco", "male"],
	"Seu Tião": ["seu tião", "seu_tiao", "male"], "Hóspede Sete": ["hóspede sete", "hospede_sete", "male"],
	"Velho Ozias": ["velho ozias", "velho_ozias", "male"],
}
const ROLES := {
	"guarda": [["guarda", "guarda"], ["guarda feminina", "guarda_female"]],
	"funcionário": [["funcionário", "funcionario"], ["funcionária", "funcionario_female"]],
	"operador": [["operador", "operador"], ["operadora", "operador_female"]],
	"operário": [["operário", "operario"], ["operária", "operario_female"]],
	"polícia": [["polícia", "policia"], ["polícia feminina", "policia_female"]],
}

static func bind(actor: Node, character_id: String, persona: String, gender: String, section := "") -> void:
	if not is_instance_valid(actor) or gender not in ["male", "female"]: return
	actor.set_meta("voice_binding", {"character_id":character_id, "persona":persona, "gender":gender, "section":section})

static func bind_sewer(actor: Node, character_name: String) -> void:
	if not NAMED.has(character_name): return
	var row: Array = NAMED[character_name]
	bind(actor, row[1], row[0], row[2], "services")

static func model_gender(model: Node) -> String:
	if not is_instance_valid(model): return ""
	var body: Variant = model.get("body")
	if body is Node and body != model:
		var rendered := model_gender(body)
		if not rendered.is_empty(): return rendered
	# wardrobe is the final, rendered appearance, overrides precede model ready.
	for key in ["wardrobe", "wardrobe_overrides"]:
		var value: Variant = model.get(key)
		if value is Dictionary and value.has("female"):
			return "female" if bool(value.female) else "male"
	for key in ["appearance_female", "is_female", "female"]:
		var value: Variant = model.get(key)
		if value is bool: return "female" if value else "male"
	return ""

static func gender_of(actor: Node) -> String:
	if not is_instance_valid(actor): return ""
	# The controlled story protagonist is the authored Dante body, not a roll.
	if actor.get("is_player") == true: return "male"
	for key in ["resident_model", "model", "visual"]:
		var visual: Variant = actor.get(key)
		if not visual is Node: continue
		var found := model_gender(visual)
		if not found.is_empty(): return found
		# Actor.Visual is a holder, not a body. Inspect direct model children only.
		for child in visual.get_children():
			found = model_gender(child)
			if not found.is_empty(): return found
	return model_gender(actor)

static func actor_id(actor: Node) -> String:
	for key in ["voice_actor_id", "interior_npc_id", "persistent_id", "mining_worker"]:
		if actor.has_meta(key): return str(actor.get_meta(key))
	var identity: Variant = actor.get("identity")
	return "%s:%s:%s" % [str(actor.get_meta("region_id", "")), str(actor.get_meta("gameplay_role", "civilian")), str(identity)] if identity != null else str(actor.name)

static func resolve(actor: Node, role := "", section := "", _fallback_persona := "") -> Dictionary:
	if not is_instance_valid(actor): return {}
	var gender := gender_of(actor)
	if gender.is_empty(): return {} # No male default when the body is unknown.
	var result: Dictionary = actor.get_meta("voice_binding", {}).duplicate(true)
	if role in ["building_social", "building_warning"]:
		if not actor.has_method("social_snapshot"): return {}
		var personality := str(actor.social_snapshot().get("personality", ""))
		if personality not in ["friendly", "reserved", "nervous"]: return {}
		result = {"persona":"civilian %s %s" % [personality, gender], "character_id":"civilian_%s_%s" % [personality, gender]}
		if section.is_empty(): section = "%s:%s" % [role, personality]
	elif role in ["civilian_reaction", "village_home_intrusion"]:
		var prefix := "civilian reaction" if role == "civilian_reaction" else "village resident"
		result = {"persona":prefix + " " + gender, "character_id":prefix.replace(" ", "_") + "_" + gender}
	elif ROLES.has(role):
		var entry: Array = ROLES[role][1 if gender == "female" else 0]
		result = {"persona":entry[0], "character_id":entry[1]}
	elif role == "fuel_cashier" and gender == "male":
		result = {"persona":"fuel cashier", "character_id":"fuel_cashier"}
	elif result.is_empty() or (result.has("gender") and result.gender != gender):
		# A caller-supplied label cannot silently claim a body of another gender.
		return {}
	if result.is_empty(): return {}
	result["gender"] = gender
	result["actor_id"] = actor_id(actor)
	if not section.is_empty(): result["section"] = section
	elif not result.has("section"): result["section"] = role
	# Subsequent pain uses the same person, including procedural personalities.
	actor.set_meta("voice_binding", result.duplicate(true))
	return result

static func pain(actor: Node) -> Dictionary:
	if not is_instance_valid(actor): return {}
	if actor.get("is_player") == true:
		bind(actor, "dante", "dante", "male", "combat_pain")
	var binding := resolve(actor, "", "combat_pain")
	if not binding.is_empty(): return binding
	# A failed named binding is a mismatch, not permission to borrow a stranger.
	if actor.has_meta("voice_binding"): return {}
	if actor.has_method("social_snapshot"): return resolve(actor, "building_social", "combat_pain")
	if actor.get_meta("truckers_village_resident", false): return resolve(actor, "village_home_intrusion", "combat_pain")
	if actor.get_meta("gameplay_role", "") == "police": return resolve(actor, "polícia", "combat_pain")
	return resolve(actor, "civilian_reaction", "combat_pain")
