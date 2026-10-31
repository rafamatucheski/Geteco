extends SceneTree
## O teto autoral do cupê encontra o vidro lateral em x=±.60, y=1.25,
## entre a coluna A (z=-.30) e a borda traseira do teto (z=.64).
## O acabamento lateral superior interno precisa caber abaixo desse envelope depois do embarque.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func run() -> void:
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	root.add_child(car)
	car.set_physics_process(false)
	car.finish_doors()
	INTERIOR.attach(car)
	var cabin := car.visual.get_node("Interior") as MeshInstance3D
	var trim_points := 0
	var inside_width := true
	var below_roof := true
	var inside_length := true
	var front_points := 0
	var dial_points := 0
	var behind_windshield := true
	for surface in cabin.mesh.get_surface_count():
		var arrays := cabin.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in vertices.size():
			var point: Vector3 = cabin.transform * vertices[i]
			if colors[i].is_equal_approx(INTERIOR.C_DIAL): dial_points += 1
			if point.y > .64 and point.z < -.50:
				front_points += 1
				# Borda inferior do para-brisa: y=.82, z=-.88. A borda superior em
				# z=-.30 chega pelo menos a y=1.25 no vidro curvo.
				var glass_height := .82 + (point.z + .88) * (.43 / .58)
				behind_windshield = behind_windshield and point.y <= glass_height - .01
			if point.y < 1.18 or absf(point.x) < .50 or not colors[i].is_equal_approx(INTERIOR.C_TRIM): continue
			trim_points += 1
			inside_width = inside_width and absf(point.x) <= .60
			below_roof = below_roof and point.y <= 1.25
			inside_length = inside_length and point.z >= -.35 and point.z <= .64
	check(trim_points > 0, "upper side trim remains present inside the cabin")
	check(inside_width, "upper side trim stays inside the narrowing roof sides")
	check(below_roof, "upper side trim stays below the physical roof edge")
	check(inside_length, "upper side trim ends inside the physical roof length")
	check(front_points > 0, "front cabin details remain present")
	check(dial_points > 0, "instrument dials remain in the dashboard")
	check(behind_windshield, "dashboard and front cabin details remain below the actual windshield with clearance")
	var cached_mesh := cabin.mesh
	INTERIOR.close_view(car)
	INTERIOR.attach(car)
	check(car.visual.find_children("Interior", "MeshInstance3D", true, false).size() == 1, "reentry keeps one interior")
	check(car.visual.get_node("Interior").mesh == cached_mesh, "reentry reuses the fitted cabin mesh")
	var other := FLEET.create("sport_coupe")
	check(not other.has_node("Interior"), "boarding leaves the shared traffic model unchanged")
	other.free()
	car.free()
	print("COUPE_CABIN_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
