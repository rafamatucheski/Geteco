extends SceneTree
## Exact emitting body, stable identity, and real sewer-model gender contract.
const BINDING := preload("res://audio/VoiceActorBinding.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const BODIES := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const SEWER := preload("res://world/places/sewers/SewerNetwork.gd")
const RESIDENT := preload("res://world/places/sewers/SewerHomelessModel.gd")
var failures: Array[String] = []

class SocialActor extends Node3D:
	var visual: Node3D
	var identity := 12
	var is_player := false
	var personality := "friendly"
	func social_snapshot() -> Dictionary: return {"personality":personality}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)

func _run() -> void:
	var actor := SocialActor.new()
	actor.name = "PersistentResident"
	actor.set_meta("persistent_id", "building_7_floor_2_resident_1")
	root.add_child(actor)
	var model := CIVILIAN.new()
	model.wardrobe = {"female":true}
	actor.visual = model # Resolver must use actual body data even before addition.
	for personality in ["friendly", "reserved", "nervous"]:
		actor.personality = personality
		var binding := BINDING.resolve(actor, "building_social")
		check(binding.get("character_id") == "civilian_%s_female" % personality, "Social personality/gender binding")
		check(binding.get("actor_id") == "building_7_floor_2_resident_1", "Stable social emitter ID")
	check(BINDING.resolve(actor, "guarda").get("character_id") == "guarda_female", "Female guard cannot receive male role")
	check(BINDING.resolve(actor, "polícia").get("character_id") == "policia_female", "Female police binding")
	BINDING.bind(actor, "cida", "cida", "female", "services")
	check(BINDING.resolve(actor).get("character_id") == "cida", "Explicit named identity")
	check(BINDING.pain(actor).get("character_id") == "cida", "Pain keeps Cida identity")
	model.wardrobe.female = false
	check(BINDING.resolve(actor).is_empty(), "Mismatched named voice must be refused")
	check(BINDING.pain(actor).is_empty(), "Pain cannot borrow a stranger after named mismatch")
	check(BINDING.resolve(actor, "guarda").get("character_id") == "guarda", "Male role uses same actual body")
	actor.visual = null
	check(BINDING.resolve(actor, "guarda").is_empty(), "Unknown body must never assume male")
	actor.is_player = true
	check(BINDING.pain(actor).get("character_id") == "dante", "Dante pain keeps authored protagonist voice")
	model.free()
	actor.free()
	for identity in 64:
		var look := CIVILIAN._appearance_wardrobe(identity, Color.WHITE, Color.BLACK, Color.TRANSPARENT, {"female":true})
		check(look.female and look.beard == 0, "Explicit female wardrobe must precede beard/hair roll")
	# Missing matching imported assets must keep a visible procedural body of
	# the correct sex, rather than borrowing an incompatible imported mesh.
	BODIES.enabled = true
	BODIES._scanned = true
	BODIES._available.assign([{"id":"male_only", "file":"male_only.glb", "female":false, "build":1}])
	var candidate := CIVILIAN.new()
	candidate.wardrobe_overrides = {"female":true}
	check(not BODIES.apply(candidate, 12) and candidate.body_source.is_empty(), "No opposite-sex mesh fallback")
	root.add_child(candidate)
	check(candidate.wardrobe.female and candidate.get_child_count() > 0, "Procedural female fallback builds visible rig")
	candidate.free()
	var definitions := SEWER.original_residents()
	for site in SEWER.SITES:
		var resource = load(SEWER.PLACES_ROOT + str(site.model) + ".gd")
		for definition in resource.RESIDENTS: definitions.append(definition)
	var underground = preload("res://world/desert/underground/DesertUnderground.gd")
	for site in underground.SITES:
		var resource = load(underground.ROOT + str(site.model) + ".gd")
		for definition in resource.RESIDENTS: definitions.append(definition)
	check(definitions.size() == 17, "All 17 sewer residents covered")
	for definition in definitions:
		var record: Array = BINDING.NAMED.get(str(definition.name), [])
		check(not record.is_empty(), "Named sewer binding exists: " + str(definition.name))
		if record.is_empty(): continue
		var appearance: Dictionary = definition.get("appearance", {})
		check(bool(appearance.get("is_female", false)) == (record[2] == "female"), "Authored gender matches sewer cast: " + str(definition.name))
	# Two real models prove the is_female adapter reaches the rendered wardrobe.
	for female in [true, false]:
		var resident := RESIDENT.new()
		resident.is_female = female
		resident.appearance_variant = 27
		root.add_child(resident)
		check(resident.wardrobe.female == female, "Sewer model consumes is_female")
		check(BINDING.model_gender(resident) == ("female" if female else "male"), "Rendered sewer gender query")
		resident.free()
	print("VOICE_ACTOR_BINDING ", "PASS" if failures.is_empty() else "FAIL", " checks=exact_actor,sex,stable_identity,17_sewer,body_fallback")
	quit(0 if failures.is_empty() else 1)
