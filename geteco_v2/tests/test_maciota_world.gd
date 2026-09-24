extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var place = load("res://world/maciota/MaciotaPlace.gd").new()
	root.add_child(place)
	place.set_interior_active(true)
	await physics_frame
	await physics_frame
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = .87
	probe.add_child(collision)
	root.add_child(probe)
	await physics_frame
	for key in ["spawn","exit","maciota","mechanic","workbench","part"]:
		var point: Vector3 = place.interior_spawn if key == "spawn" else (place.exit_position if key == "exit" else place.interaction_points[key])
		probe.global_position = point + Vector3(0,.04,0)
		check(probe.move_and_collide(Vector3(0,.001,0),true) == null,"Blocked approach: "+key)
	probe.collision_mask = 1
	for resident in [place.maciota,place.mechanic]:
		probe.global_position = resident.global_position + Vector3(0,.04,0)
		check(probe.move_and_collide(Vector3(0,.001,0),true) == null,"Resident inside furniture: " + resident.name)
		check(not resident.has_method("take_damage") and not resident.has_method("die"),"Resident exposed to damage")
	# Swept full player body: rear wall, desk and free office doorway.
	for sweep in [
		[Vector3(0,0,-2.5),Vector3(0,0,-5),true,"rear wall"],
		[Vector3(4.4,0,-.55),Vector3(0,0,-2.5),true,"desk footprint"],
		[Vector3(1.2,0,1.5),Vector3(2,0,0),false,"office doorway"]
	]:
		probe.global_position = place.interior_origin + sweep[0] + Vector3(0,.04,0)
		var hit := probe.move_and_collide(sweep[1],true)
		check((hit != null) == sweep[2],"Unexpected swept collision: "+sweep[3])
	check(place.solid_bodies.size() > 20,"Missing furniture solids")
	place.set_part_available(false)
	check(not place.part_visual.visible,"Collected part remains visible")
	place.set_interior_active(false)
	check(place.room.process_mode == Node.PROCESS_MODE_DISABLED and not place.room.visible,"Empty interior active")
	for failure in failures: push_error(failure)
	print("MACIOTA_WORLD ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	probe.free()
	place.free()
	quit(0 if failures.is_empty() else 1)
