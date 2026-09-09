extends RefCounted
const GROUPS := {
	"curta":["pistol","magnum","smg"],
	"longa":["shotgun","sawed_off","ak47","m4a1","hunting_rifle","rpg","flamethrower"],
	"corpo":["knife"],
	"granada":["grenade"]
}
static func slot_for(id: String) -> String:
	for slot in GROUPS:
		if id in GROUPS[slot]: return slot
	return ""
static func normalize(slots: Dictionary, inventory: Dictionary) -> Dictionary:
	var result := {}
	for slot in GROUPS:
		var id := String(slots.get(slot,""))
		# Older saves stored grenades as a long gun; give them their own slot.
		if slot == "granada" and not slots.has(slot) and inventory.get("grenade", false): id = "grenade"
		result[slot] = id if id in GROUPS[slot] and inventory.get(id,false) else ""
	return result
