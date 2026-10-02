extends SceneTree
const BUS := preload("res://runtime/transit/BiarticulatedBus.gd")
const VEHICLE := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const DRIVER := preload("res://gameplay/dispatch/DispatchDriver.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	KIT.add_wall(scene, Vector3(0,-.5,0), Vector3(200,1,300))
	var bus := BUS.new()
	scene.add_child(bus)
	var truck := VEHICLE.new()
	truck.archetype = "rescue_pumper"
	truck.position = Vector3(3,.05,50)
	scene.add_child(truck)
	truck.ensure_equipment(scene)
	truck.equipment.set_process(false)
	truck.equipment.siren_on = true
	truck.set_physics_process(false)
	var roads := ROUTES.new()
	roads.configure([{"id":"straight", "width":12.0, "points":PackedVector3Array([Vector3(0,0,120),Vector3(0,0,-120)])}])
	var driver := DRIVER.new()
	driver.setup(truck,10.0,2.0)
	driver.enable_overtaking(roads)
	var route := Curve3D.new()
	route.add_point(Vector3(3,0,90))
	route.add_point(Vector3(3,0,-70))
	route.set_meta("traffic_open",true)
	driver.set_route(route)
	# Rearmost section is encountered first; all three hulls remain obstacles.
	for index in 3:
		bus.sections[index].global_position = Vector3(3,.05,8.0 + float(index)*8.0)
	await physics_frame
	await physics_frame
	var complete := true
	for index in [1,2]:
		var section: CharacterBody3D = bus.sections[index]
		var actual: Vector3 = bus.hulls[index].size
		var length = section.get("half_length")
		var width = section.get("half_width")
		var matching := length != null and width != null
		if matching: matching = is_equal_approx(float(length)*2,actual.z) and is_equal_approx(float(width)*2,actual.x)
		check(matching,"section %d exposes its actual collision dimensions" % index)
		complete = complete and matching
	if complete:
		var gap: float = driver.overtake._nearest_gap([bus.sections[2]])
		check(is_equal_approx(gap,26.0-bus.hulls[2].size.z*.5-truck.half_length),"gap uses section length, not head or entire bus")
		var plan: Dictionary = driver.overtake._planner.plan(truck,route,bus.sections,true,driver.ignore)
		check(plan.ok,"plans against articulated sections without invalid property access: " + str(plan.get("reason","")))
		var oncoming := VEHICLE.new()
		oncoming.position = Vector3(-3,.05,10)
		oncoming.rotation.y = PI
		scene.add_child(oncoming)
		oncoming.set_physics_process(false)
		await physics_frame
		await physics_frame
		var occupied: Dictionary = driver.overtake._planner.plan(truck,route,bus.sections,true,driver.ignore)
		check(not occupied.ok,"occupied opposite lane still prevents passing bus")
	driver.disable_overtaking()
	scene.free()
	await physics_frame
	print("TRANSIT_SECTION_OVERTAKING checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
