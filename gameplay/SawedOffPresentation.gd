extends RefCounted
## Compact double barrel presentation. The game keeps its own damage and ammo;
## this module only builds the silhouette and articulates the reload.
const GEO = preload("res://gameplay/WeaponPresentation3D.gd")
const PIVOT := Vector3(0.0, -0.014, -0.030)
const OPEN_ANGLE := -0.68
const EJECT_AT := 0.26
const MUZZLE := Vector3(0.0, 0.02, -0.207)

static func build(root: Node3D) -> Vector3:
	var steel := GEO._mat(Color("596269"), 0.82, 0.32)
	var dark := GEO._mat(Color("262c30"), 0.72, 0.43)
	var recess := GEO._mat(Color("111416"), 0.0, 0.9)
	var wood := GEO._mat(Color("583523"), 0.0, 0.58)
	var barrels := Node3D.new()
	barrels.name = "BreakActionBarrels"
	barrels.position = PIVOT
	root.add_child(barrels)
	for side in [-1.0, 1.0]:
		var suffix := "Left" if side < 0.0 else "Right"
		GEO._cylinder(barrels, "Barrel" + suffix, Vector3(side * 0.018, 0.02, -0.105) - PIVOT, 0.018, 0.19, steel, Vector3(90, 0, 0))
		GEO._cylinder(barrels, "Bore" + suffix, Vector3(side * 0.018, 0.02, -0.2008) - PIVOT, 0.012, 0.0015, recess, Vector3(90, 0, 0))
		GEO._cylinder(barrels, "Breech" + suffix, Vector3(side * 0.018, 0.02, -0.0092) - PIVOT, 0.012, 0.0015, recess, Vector3(90, 0, 0))
		var chamber := Marker3D.new()
		chamber.name = "Chamber" + suffix
		chamber.position = Vector3(side * 0.018, 0.02, -0.009) - PIVOT
		barrels.add_child(chamber)
	GEO._box(barrels, "BarrelRib", Vector3(0, 0.034, -0.105) - PIVOT, Vector3(0.009, 0.008, 0.19), dark)
	GEO._box(barrels, "FrontSight", Vector3(0, 0.042, -0.185) - PIVOT, Vector3(0.008, 0.008, 0.012), dark)
	GEO._box(barrels, "ForeEnd", Vector3(0, -0.006, -0.078) - PIVOT, Vector3(0.045, 0.027, 0.10), wood)
	GEO._box(root, "Receiver", Vector3(0, 0.011, 0.029), Vector3(0.062, 0.055, 0.078), dark)
	GEO._cylinder(root, "HingePin", PIVOT, 0.012, 0.067, steel, Vector3(0, 0, 90))
	GEO._profile(root, "PistolGrip", PackedVector2Array([
		Vector2(0.025, -0.005), Vector2(0.059, -0.008), Vector2(0.077, -0.081),
		Vector2(0.055, -0.104), Vector2(0.023, -0.092), Vector2(0.020, -0.057),
		Vector2(0.014, -0.027)]), 0.038, wood)
	GEO._box(root, "TopLever", Vector3(0, 0.043, 0.035), Vector3(0.011, 0.008, 0.050), steel)
	GEO._trigger_guard(root, Vector3(0, -0.035, -0.005), dark)
	for side in [-1.0, 1.0]:
		GEO._cylinder(root, "GripPin", Vector3(side * 0.0195, -0.054, 0.046), 0.0045, 0.002, steel, Vector3(0, 0, 90))
	return MUZZLE

static func reload_open(progress: float) -> float:
	var t := clampf(progress, 0.0, 1.0)
	return smoothstep(0.08, 0.22, t) * (1.0 - smoothstep(0.72, 0.88, t))

static func update_parts(root: Node3D, opening: float) -> void:
	var barrels := root.get_node_or_null("BreakActionBarrels") as Node3D
	if barrels != null: barrels.rotation.x = OPEN_ANGLE * clampf(opening, 0.0, 1.0)

static func reload_targets(progress: float, grip: Vector3) -> Dictionary:
	var t := clampf(progress, 0.0, 1.0)
	var hand := Vector3(0.06, 0.96, -0.34)
	var basis := Basis.from_euler(Vector3(0.08, 0.16, -0.35))
	var open_basis := Basis(Vector3.RIGHT, OPEN_ANGLE * reload_open(t))
	var breech := PIVOT + open_basis * (Vector3(-0.018, 0.02, -0.009) - PIVOT)
	var service := hand + basis * (breech - grip + Vector3(-0.018, 0.008, 0.016))
	var belt := Vector3(-0.19, 0.67, -0.01)
	var fetch := smoothstep(0.27, 0.40, t) * (1.0 - smoothstep(0.44, 0.62, t))
	var left := service.lerp(belt, fetch)
	var support := hand + basis * Vector3(-0.038, -0.003, 0.0)
	left = left.lerp(support, smoothstep(0.82, 0.96, t))
	return {"hand": hand, "left": left, "basis": basis,
		"weight": smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.88, 1.0, t)),
		"pump": 0.0, "kick": Vector3.ZERO}
