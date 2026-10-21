extends SceneTree
## Complements fleet contracts with authored door mesh reuse and cabin bounds.
const CATALOG = preload("res://runtime/NewCivilianFleet.gd")
const VEHICLE = preload("res://scripts/Vehicle.gd")
const DOORS = preload("res://gameplay/VehicleDoorPresentation.gd")
const ROLES = preload("res://runtime/VehicleSurfaceRoles.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for id: String in CATALOG.IDS:
		var car := VEHICLE.new()
		car.archetype = id
		stage.add_child(car)
		car.process_mode = Node.PROCESS_MODE_DISABLED
		var cabin: Dictionary = car.visual.get_meta("vehicle_interior_spec", {})
		var d := CATALOG.door_spec(id)
		check(not cabin.is_empty(), id+": explicit cabin metadata")
		check(float(cabin.get("sz",999))>=float(d.zf) and float(cabin.get("sz",999))<=float(d.zr), id+": seat inside front door")
		var leaves := {}
		var bounds := AABB()
		var first := true
		for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == null: continue
			var box := (car.visual.global_transform.affine_inverse()*part.global_transform)*part.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			if not part.has_meta("new_civilian_door_side"): continue
			var side := int(part.get_meta("new_civilian_door_side"))
			leaves[side] = {"part":part, "mesh":part.mesh}
			var outside := 0.0
			var inside := 0.0
			for surface in part.mesh.get_surface_count():
				var role := ROLES.key(part,surface)
				if role not in ["paint", "detail"]: continue
				var arrays := part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for j in range(0, indices.size(), 3):
					var a := vertices[indices[j]]
					var b := vertices[indices[j+1]]
					var c := vertices[indices[j+2]]
					if maxf(a.y,maxf(b.y,c.y))>float(d.belt)+.001: continue
					var n := (b-a).cross(c-a)
					if absf(n.normalized().x)<.8: continue
					if role=="paint": outside += n.length()*.5
					elif n.normalized().x*side>0: inside += n.length()*.5
			check(outside>.15, id+": solid outside lower door "+str(side))
			check(inside>.15, id+": solid inside lower door "+str(side))
		check(bounds.position.y>=-.0001, id+": no visible geometry below ground plane")
		var size: Array = CATALOG.spec(id).bounds_size
		check(bounds.size.x<=float(size[0])+.05 and bounds.size.y<=float(size[1])+.05 and bounds.size.z<=float(size[2])+.05, id+": collision envelope actual="+str(bounds)+" spec="+str(size))
		check(leaves.size()==2, id+": two authored leaves")
		var doors := DOORS.new()
		car.visual.add_child(doors)
		doors.configure(car)
		check(doors.ready_for_boarding, id+": ready without cutting")
		for side in leaves:
			var leaf: MeshInstance3D = leaves[side].part
			check(leaf.mesh==leaves[side].mesh, id+": door reuses authored mesh")
			check(leaf.get_parent()==doors.hinges.get(side), id+": correct hinge")
			var closed := leaf.global_transform
			var hinge: Node3D = doors.hinges[side]
			hinge.rotation.y = float(side)*1.05
			check(not leaf.global_transform.is_equal_approx(closed), id+": leaf moves")
			hinge.rotation.y = 0
			check(leaf.global_transform.is_equal_approx(closed), id+": closing restores pose")
		car.free()
	stage.free()
	print("NEW_CIVILIAN_MODELS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
