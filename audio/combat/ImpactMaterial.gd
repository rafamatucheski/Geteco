extends RefCounted

const MATERIALS := [&"flesh", &"metal", &"concrete", &"wood", &"glass"]
const PEOPLE := [&"player", &"pedestrian", &"city_pedestrian", &"police_officer",
	&"gang_member", &"paramedic", &"firefighter", &"mortician"]
const METAL := [&"vehicle", &"ambient_traffic", &"emergency_vehicle", &"metal_prop"]

static func resolve(target: Node) -> StringName:
	var current := target
	# Colliders can be children of the authored prop/actor. Read its explicit
	# material before falling back to concrete; don't guess from object names.
	for depth in 5:
		if not is_instance_valid(current): break
		var authored := StringName(current.get_meta("impact_material", ""))
		if authored in MATERIALS: return authored
		for group in METAL:
			if current.is_in_group(group): return &"metal"
		for group in PEOPLE:
			if current.is_in_group(group): return &"flesh"
		current = current.get_parent()
	return &"concrete"
