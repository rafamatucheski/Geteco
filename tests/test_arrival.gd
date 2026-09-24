extends SceneTree
const ARRIVAL := preload("res://runtime/Arrival.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func run() -> void:
	var adapter := ARRIVAL.new()
	check(ARRIVAL.validate_snapshot(adapter.snapshot()), "new checkpoint valid")
	var corrupted := adapter.snapshot()
	corrupted.phase = "city_tour"
	check(not ARRIVAL.validate_snapshot(corrupted), "cannot invent completed arrival")
	corrupted = adapter.snapshot()
	corrupted.flags.harbor_city_tour_complete = true
	check(not ARRIVAL.validate_snapshot(corrupted), "cannot skip milestones")
	for id in ARRIVAL.FLAGS: adapter.flags[id] = true
	adapter.phase = "complete"
	check(ARRIVAL.validate_snapshot(adapter.snapshot()), "completed checkpoint valid")
	var restored := ARRIVAL.new()
	check(restored.restore_state(adapter.snapshot()), "checkpoint roundtrip")
	adapter.free()
	restored.free()
	var dialogue := preload("res://runtime/ArrivalDialogue.gd")
	check(dialogue.POLICE.size() == 5 and dialogue.PHONE.size() == 4 and dialogue.MEETING.size() == 3 and dialogue.TOUR.size() == 4, "all16 original lines preserved")
	var scene := Node3D.new()
	root.add_child(scene)
	var maciota := preload("res://runtime/ArrivalActor.gd").new()
	scene.add_child(maciota)
	check(not maciota.has_method("receive_damage") and not maciota.has_method("die"), "Maciota no damage or death entrypoint")
	check(maciota.visual != null, "original Maciota3D")
	var car := preload("res://runtime/ArrivalCar.gd").new()
	scene.add_child(car)
	car.set_physics_process(false)
	check(car.model.doors.size() == 4 and car.model.wheels.size() == 4 and car.model.occupants.size() == 2, "original M8 doors wheels occupants")
	check(car.half_width > 1 and car.half_length > 2.3, "M8 complete hull derived from original bounds")
	check(not car.is_in_group("drivable"), "tour car cannot be stolen through free driving")
	check(car.find_children("*", "SubViewport", true, false).is_empty(), "no hybrid viewport")
	var region := preload("res://world/regions/NativeRegion.gd").build_region("harbor")
	scene.add_child(region)
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(region.roads)
	var route := graph.route_between(Vector3(-1180,0,1225)/16.0, Vector3(715,0,1800)/16.0)
	check(route != null and route.get_baked_length() > 50, "real Harbor directed road journey")
	if route:
		check(route.get_meta("traffic_open", false), "tour stops at destination without wrapping")
	scene.free()
	await process_frame
	print("ARRIVAL ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
