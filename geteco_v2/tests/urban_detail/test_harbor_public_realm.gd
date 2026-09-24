extends SceneTree

const PUBLIC_REALM := preload("res://world/urban_detail/HarborPublicRealm3D.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if value: return
	failures.append(label)
	push_error("FAIL: " + label)

func make_zone(id: String, at: Vector3) -> Node3D:
	var zone := PUBLIC_REALM.new()
	zone.zone_id = id
	zone.position = at
	root.add_child(zone)
	return zone

func run() -> void:
	var records := PUBLIC_REALM.records()
	check(records.size() == 5, "All five authored public-realm records are published")
	var ids := records.map(func(row): return row.zone_id)
	for expected in ["union_plaza", "foundry_courtyard", "northbank_promenade_west", "northbank_promenade_east", "museum_compass"]:
		check(expected in ids, "Public-realm record exists: " + expected)

	var union := make_zone("union_plaza", Vector3.ZERO)
	var foundry := make_zone("foundry_courtyard", Vector3(60, 0, 0))
	var promenade_west := make_zone("northbank_promenade_west", Vector3(120, 0, 0))
	var promenade_east := make_zone("northbank_promenade_east", Vector3(200, 0, 0))
	var compass := make_zone("museum_compass", Vector3(280, 0, 0))
	await physics_frame

	check(union.find_child("UnionFountainBasin", true, false) != null, "Union Plaza includes its recognizable fountain basin")
	check(union.find_child("UnionPlazaPaving", true, false) != null, "Union Plaza includes the authored paved court")
	check(foundry.find_child("FoundryGardenBed", true, false) != null, "Foundry courtyard includes its garden pocket")
	check(foundry.find_child("FoundryServiceYard", true, false) != null, "Foundry courtyard includes its service yard")
	check(promenade_west.find_child("PromenadePlanterCurb", true, false) != null, "West promenade includes authored planters")
	check(promenade_east.find_child("PromenadePlanterCurb", true, false) != null, "East promenade includes authored planters")
	check(compass.find_child("MuseumCompassOuter", true, false) != null, "Museum courtyard includes the compass landmark")

	for zone in [union, foundry, promenade_west, promenade_east, compass]:
		check(zone.find_children("*", "SubViewport", true, false).is_empty(), "%s uses no SubViewport" % zone.zone_id)

	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.70
	shape_node.shape = capsule
	shape_node.position.y = 0.85
	probe.add_child(shape_node)
	root.add_child(probe)
	probe.position = Vector3(-6, 0, 0)
	check(probe.move_and_collide(Vector3(4, 0, 0), true) != null, "Union fountain basin physically blocks pedestrian traversal")
	probe.position = Vector3(-10, 0, 8)
	check(probe.move_and_collide(Vector3(8, 0, 0), true) == null, "Union Plaza paving remains freely walkable away from the fountain")

	print("HARBOR_PUBLIC_REALM_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
