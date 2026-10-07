extends RefCounted
## Discovery is saved separately; existing headquarters power still owns access.
const KEY := "secret_fast_travel"
const IDS := ["harbor","mountain","desert"]
static func data(world: Dictionary) -> Dictionary:
	return world.get(KEY,{"version":1,"discovered":[]}).duplicate(true)
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1 or not value.get("discovered") is Array: return false
	var seen: Array=[]
	for id in value.discovered:
		if not id is String or id not in IDS or id in seen: return false
		seen.append(id)
	return true
static func discover(world: Dictionary,id: String) -> bool:
	var next:=data(world)
	if not valid(next) or id not in IDS or id in next.discovered: return false
	next.discovered.append(id)
	world[KEY]=next
	return true
