extends RefCounted
## Optional save extension: cosmetic secrets never advance a mission.
const KEY := "amusement_park_cosmetics"
const ENTRIES := {
	"lume_jacket":{"label":"Jaqueta Lume", "slot":"outfit", "outfit":"dante_lume", "location":"park"},
	"midnight_coat":{"label":"Casaco Meia-noite", "slot":"outfit", "outfit":"dante_midnight", "location":"park"},
	"star_glasses":{"label":"Óculos Estrela", "slot":"glasses", "location":"park"},
	"amber_glasses":{"label":"Óculos Âmbar", "slot":"glasses", "location":"park"},
	"ghost_mask":{"label":"Máscara Fantasma", "slot":"mask", "location":"haunted"},
	"fox_mask":{"label":"Máscara Raposa", "slot":"mask", "location":"haunted"},
}

static func fresh() -> Dictionary:
	return {"version":1, "found":[], "glasses":"", "mask":""}

static func data(world: Dictionary) -> Dictionary:
	var saved: Variant = world.get(KEY, fresh())
	return saved.duplicate(true) if saved is Dictionary else {}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4 or value.get("version") != 1: return false
	if not value.get("found") is Array or value.found.size() > ENTRIES.size(): return false
	var seen := {}
	for id in value.found:
		if not id is String or not ENTRIES.has(id) or seen.has(id): return false
		seen[id] = true
	for slot in ["glasses", "mask"]:
		var selected: Variant = value.get(slot)
		if not selected is String: return false
		if selected != "" and (not seen.has(selected) or ENTRIES[selected].slot != slot): return false
	return true

static func validate_world(world: Dictionary, wallet: Dictionary) -> bool:
	var saved := data(world)
	if not valid(saved): return false
	var outfits: Variant = wallet.get("outfits", [])
	if not outfits is Array: return false
	for id in saved.found:
		if ENTRIES[id].slot == "outfit" and not outfits.has(ENTRIES[id].outfit): return false
	return true

static func collect(world: Dictionary, economy, id: String) -> bool:
	if not ENTRIES.has(id) or not validate_world(world, economy.snapshot()): return false
	var saved := data(world)
	if saved.found.has(id): return false
	var entry: Dictionary = ENTRIES[id]
	# Wallet ownership precedes its marker; retries reconcile without duplication.
	if entry.slot == "outfit" and not economy.owns_outfit(entry.outfit):
		if not economy.grant_outfit(entry.outfit): return false
	saved.found.append(id)
	world[KEY] = saved
	return true

static func equip(world: Dictionary, economy, id: String) -> bool:
	if not ENTRIES.has(id) or not validate_world(world, economy.snapshot()): return false
	var saved := data(world)
	if not saved.found.has(id): return false
	var entry: Dictionary = ENTRIES[id]
	if entry.slot == "outfit": return economy.equip_outfit(entry.outfit)
	saved[entry.slot] = id
	world[KEY] = saved
	return true

static func remove(world: Dictionary, slot: String) -> bool:
	if slot not in ["glasses", "mask"]: return false
	var saved := data(world)
	if not valid(saved): return false
	saved[slot] = ""
	world[KEY] = saved
	return true
