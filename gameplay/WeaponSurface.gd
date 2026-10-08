extends RefCounted
## Shared contact identity for a bullet and an empty case at the actual hit.
const GROUND := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
const SOFT := ["dirt", "sand", "grass", "snow"]
const MATERIALS := ["flesh", "metal", "concrete", "wood", "glass", "dirt", "sand", "grass", "snow"]
const ACTORS := ["player", "civilian", "cobra", "police", "private_security", "ambient_worker", "wildlife", "vicente_crew", "desert_digo_mechanic", "desert_contact", "fort_soldier", "digo_instructor", "jessica", "emergency", "urban_routine"]

static func resolve(collider: Object, point := Vector3.INF, normal := Vector3.ZERO) -> String:
	var cursor := collider as Node
	var floor_kind := ""
	var labels := ""
	for depth in 8:
		if not is_instance_valid(cursor): break
		var authored := str(cursor.get_meta("impact_material", ""))
		if authored in MATERIALS: return authored
		var role := str(cursor.get_meta("gameplay_role", ""))
		labels += " " + str(cursor.name).to_lower()
		# Vehicles also have gameplay_role: testing any role first made cars bleed.
		if role == "vehicle" or ("half_length" in cursor and "speed" in cursor): return "metal"
		if role == "police" and "rotor" in cursor: return "metal"
		if role in ACTORS or (cursor is CharacterBody3D and "dead" in cursor): return "flesh"
		if floor_kind.is_empty(): floor_kind = str(cursor.get_meta("vehicle_surface", ""))
		cursor = cursor.get_parent()
	if floor_kind in SOFT: return floor_kind
	if floor_kind == "hard": return "concrete"
	# Geography describes the ground, never a wall above that ground.
	var terrain := "mountainterrain" in labels or "cemeterysolids" in labels or "originalcemetery" in labels or "originalportsurface" in labels or "earthroad" in labels or "dirtroad" in labels
	if terrain and point.is_finite() and normal.y > 0.55:
		var kind := GROUND._surface_kind(collider, point)
		if kind in SOFT: return kind
	return "concrete"

static func casing_family(material: String) -> String:
	if material in ["metal", "wood", "snow"]: return material
	return "soft" if material in SOFT else "hard"

static func restitution(material: String) -> float:
	if material in SOFT: return 0.04
	return 0.24 if material == "wood" else 0.34
