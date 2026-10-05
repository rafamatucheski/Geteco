extends SceneTree
const FLEET := preload("res://runtime/FleetCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)
func run() -> void:
	for id in ["digo_gol_1993","digo_amarok_2014"]:
		var car := VEHICLE.new()
		car.archetype = id
		root.add_child(car)
		car.set_physics_process(false)
		var fixed := {}
		for part in car.visual.find_children("*","MeshInstance3D",true,false):
			if part.get_meta("door_cut_exempt",false): fixed[part] = part.mesh
		check(not fixed.is_empty(),id+" has an authored fixed cabin structure")
		car.finish_doors()
		for part in fixed:
			check(part.mesh == fixed[part] and part.visible,id+" roof/pillars/floor survive door cutting unchanged")
		for side in [-1,1]:
			car.door_presentation.set_open(side,true,0)
			check(not car.door_presentation.hinges[side].get_children().is_empty(),id+" has a real opening door on either side")
			car.door_presentation.set_open(side,false,0)
			check(is_zero_approx(car.door_presentation.hinges[side].rotation.y),id+" closes door flush")
		INTERIOR.attach(car)
		var cabin := car.visual.get_node("Interior") as MeshInstance3D
		var box := cabin.transform * cabin.mesh.get_aabb()
		var half := .805 if id == "digo_gol_1993" else .94
		var roof := 1.43 if id == "digo_gol_1993" else 1.86
		check(box.position.x >= -half and box.end.x <= half,id+" interior stays inside actual body width, excluding mirrors")
		check(box.end.y <= roof,id+" interior stays below the physical roof")
		var upper_rear := -INF
		for surface in cabin.mesh.get_surface_count():
			for vertex in cabin.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = cabin.transform * vertex
				if point.y > roof - .10: upper_rear = maxf(upper_rear, point.z)
		check(upper_rear <= (.90 if id == "digo_gol_1993" else .98),id+" upper cabin trim ends inside the physical roof")
		print("DIGO_CABIN_BOUNDS ",id," ",box)
		for part in fixed:
			check(part.mesh == fixed[part],id+" boarding does not deform structural geometry")
		INTERIOR.close_view(car)
		INTERIOR.attach(car)
		check(car.visual.find_children("Interior","MeshInstance3D",true,false).size()==1,id+" reentry reuses one cabin")
		var other := FLEET.create(id)
		check(not other.has_node("Interior"),id+" shared model cache has no instance interior")
		other.free()
		car.free()
	print("DIGO_CABINS_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
