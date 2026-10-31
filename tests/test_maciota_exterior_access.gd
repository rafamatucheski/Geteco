extends SceneTree
## Cápsula inteira na entrada autoral e varrida contra a casca inalterada.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var place := load("res://world/maciota/MaciotaPlace.gd").new() as Node3D
	root.add_child(place)
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = .85
	probe.add_child(collision)
	root.add_child(probe)
	await physics_frame
	await physics_frame
	for point in [place.entry_position, place.exterior_return, place.exterior_return + Vector3(0, 0, 2)]:
		probe.global_position = point + Vector3.UP * .04
		if probe.move_and_collide(Vector3.UP * .001, true) != null:
			failures.append("Blocked exterior access at %s" % point)
	var portal: Node3D = place.facade.get_node("OpenGarageEntrance")
	if not portal.is_visible_in_tree(): failures.append("Portal is hidden by the painted facade")
	for part: Node3D in portal.get_children():
		if not part.is_visible_in_tree(): failures.append("Entrance structural cue hidden: "+str(part.name))
	var header: MeshInstance3D = portal.get_node("PortalHeader")
	if header.mesh.size.x < 6.0: failures.append("Entrance frame must span the real garage opening")
	if portal.find_children("*","Label3D",true,false).size() > 0: failures.append("Entrance cannot depend on decorative text")
	var origin: Vector3 = place.facade.global_position
	probe.global_position = origin+Vector3(-2,.08,8.55)
	if probe.move_and_collide(Vector3(0,0,-1.20),true) != null:
		failures.append("Visible open portal blocks a full pedestrian capsule")
	for x in [-5.45, -2.0, 1.45, 6.1]:
		probe.global_position = origin + Vector3(x, .04, 8.55)
		if probe.move_and_collide(Vector3(0, 0, -4.0), true) == null:
			failures.append("Facade sweep missed solid at x=%.2f" % x)
	var exterior_solids := 0
	for body in place.solid_bodies:
		if str(body.name).begins_with("Facade_"):
			exterior_solids += 1
	if exterior_solids != 4:
		failures.append("Exterior solid count changed: %d" % exterior_solids)
	for failure in failures:
		push_error(failure)
	print("MACIOTA_EXTERIOR_ACCESS ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	probe.free()
	place.free()
	quit(0 if failures.is_empty() else 1)
