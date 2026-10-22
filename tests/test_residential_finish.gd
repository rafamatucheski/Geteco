extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("HOME_FINISH ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	for id in ["westgate_garden","quayside_house","canal_north"]:
		var room = preload("res://world/places/PlaceCatalog.gd").create_place(id)
		root.add_child(room)
		var actor := preload("res://scripts/Actor.gd").new()
		actor.is_player = true
		actor.input_locked = true
		root.add_child(actor)
		actor.set_physics_process(false)
		for i in 3: await physics_frame
		for key in room.interaction_points:
			actor.global_position = room.interaction_points[key]+Vector3.UP*.04
			check(actor.move_and_collide(Vector3.UP*.002,true) == null,id+" clear interaction "+str(key))
		for identity in ["Sofa","Bed","CoffeeTable","Kitchen"]:
			var rect: Rect2 = room.model.solid_rects[identity]
			var center := rect.get_center()
			# Sweep the real capsule towards the full furniture footprint.
			for side in [-1,1]:
				actor.global_position = room.to_global(Vector3(center.x,0,rect.position.y-.7 if side == -1 else rect.end.y+.7))+Vector3.UP*.04
				check(actor.move_and_collide(Vector3(0,0,side*-1.2),true) != null,id+" solid "+identity+" side "+str(side))
		actor.free()
		room.free()
	var tree := preload("res://world/places/ResidentialTreeVisual.gd")
	check(tree.near_home(Vector3(250.0/16,0,150.0/16)),"tree replacement includes home garden")
	check(not tree.near_home(Vector3(400,0,400)),"tree replacement excludes remote streets")
	var mesh: ArrayMesh = tree.mesh()
	check(mesh.get_surface_count() == 2 and mesh.get_aabb().size.y > 3,"branched tree has wood and foliage")
	var chunk := Node3D.new()
	root.add_child(chunk)
	preload("res://world/city_look/SidewalkFill.gd").add_trunk_collision(chunk,{"street_tree":[Transform3D.IDENTITY]})
	check(chunk.get_node("CityStreetTreeTrunks").get_child_count() == 1,"replacement retains trunk collision")
	chunk.free()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
