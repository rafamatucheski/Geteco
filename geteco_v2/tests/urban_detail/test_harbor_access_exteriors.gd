extends SceneTree

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const PORT_BOSS_EXTERIOR := preload("res://world/urban_detail/PortBossGarageExterior3D.gd")
const HARBOR_MANHOLE_EXTERIOR := preload("res://world/urban_detail/HarborManholeExterior3D.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value:
		return
	failures.append(label)
	push_error("FAIL: " + label)

func run() -> void:
	var port: Dictionary = CATALOG.get_definition("port_boss_garage")
	var sewer: Dictionary = CATALOG.get_definition("harbor_sewer")
	check(port.entry_position.is_equal_approx(port.exterior_position + Vector3(-4, 0, 0)), "Port boss approach uses the productive west side")
	check(port.return_position.is_equal_approx(port.exterior_position), "Port boss return restores the exact productive exterior point")
	check(sewer.entry_position.is_equal_approx(sewer.exterior_position), "Sewer access is the manhole itself")

	# Isolate local geometry so the swept capsule only reports the authored portal.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var port_local := port.duplicate(true)
	port_local.position = Vector3.ZERO
	var facade: Node3D = FACTORY.populate_chunk(fixture, port_local)
	await physics_frame
	check(facade.get_script() == PORT_BOSS_EXTERIOR, "Port boss exterior selects its authored native portal")
	check(not facade.find_children("*", "StaticBody3D", true, false).is_empty(), "Port boss portal owns native structural collision")

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
	probe.position = Vector3(-4, 0, 0)
	check(probe.move_and_collide(Vector3(5, 0, 0), true) == null, "Full pedestrian capsule crosses the port garage threshold")
	probe.position = Vector3(-3, 0, 2.65)
	check(probe.move_and_collide(Vector3(-3, 0, 0), true) != null, "Port garage front flank blocks traversal beside the gate")

	var sewer_local := sewer.duplicate(true)
	sewer_local.position = Vector3(30, 0, 0)
	var manhole: Node3D = FACTORY.populate_chunk(fixture, sewer_local)
	await physics_frame
	check(manhole.get_script() == HARBOR_MANHOLE_EXTERIOR, "Sewer access selects the authored manhole prop")
	check(is_zero_approx(manhole.open_amount), "Sewer hatch starts closed until the entry animation opens it")
	var closed_lid := manhole.find_child("ClosedCoverCollision", true, false) as StaticBody3D
	check(closed_lid != null and closed_lid.collision_layer == 1, "Closed manhole cover supports pedestrians until it opens")
	check(not manhole.find_children("*", "MeshInstance3D", true, false).is_empty(), "Manhole remains visually represented at the access")

	print("HARBOR_ACCESS_EXTERIORS_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", 11, failures.size()])
	quit(0 if failures.is_empty() else 1)
