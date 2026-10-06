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
	var disk_copy: Variant = JSON.parse_string(JSON.stringify(adapter.snapshot()))
	check(restored.restore_state(disk_copy), "JSON numeric version and caption survive disk serialization")
	adapter.free()
	restored.free()
	var dialogue := preload("res://runtime/ArrivalDialogue.gd")
	check(dialogue.HOME_CALL.size() == 5 and dialogue.MEETING.size() == 5 and dialogue.TOUR.size() == 4, "new home call, terminal meeting and journey have bilingual lines")
	check(dialogue.MEETING[0][1] == "Dante, temos muito que conversar.", "Maciota recognizes Dante at the street exit")
	for source in [dialogue.HOME_CALL, dialogue.MEETING, dialogue.TOUR]:
		for line in source:
			check(line.size() == 3 and not str(line[1]).is_empty() and not str(line[2]).is_empty(), "arrival dialogue has PT and EN subtitles")
	var legacy := {"version":1,"phase":"phone","flags":{"harbor_arrival_seen":true,"harbor_police_briefed":true},"caption":-1,"opening_completed":true}
	var migrated := ARRIVAL.new()
	check(migrated.restore_state(legacy) and migrated.phase == "terminal_meeting", "legacy police checkpoint migrates to the new street encounter")
	check(ARRIVAL.validate_snapshot(migrated.snapshot()), "migrated checkpoint follows current save contract")
	migrated.free()
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
	var route := graph.route_between(Vector3(3000,0,2200)/16.0, Vector3(2580,0,1250)/16.0, Vector3.RIGHT)
	check(route != null and route.get_baked_length() > 50, "real Harbor directed road journey")
	if route:
		check(route.get_meta("traffic_open", false), "tour stops at destination without wrapping")
	var authored_adapter := ARRIVAL.new()
	authored_adapter.session = {"controller":{"region":region},"world":{"maciota_place":{"tour_parking":Vector3(157.5,0,104.4),"exterior_origin":Vector3(168.5,0,101.5)}}}
	var authored: Curve3D = authored_adapter._build_route()
	check(authored != null, "current terminal-to-court route builds from the real directed Harbor graph")
	if authored != null:
		var access_start: Vector3 = authored.get_meta("court_access_start")
		var quay_offset := authored.get_closest_offset(access_start)
		var quay_heading := (access_start-authored.sample_baked(quay_offset-.5,true)).normalized()
		check(quay_heading.dot(Vector3.FORWARD)>.98,"workshop access begins in the northbound Quay lane without a city-loop U-turn")
		var occupied_frontage_avoided := true
		for meter in range(0,ceili(authored.get_baked_length()),2):
			var point := authored.sample_baked(float(meter),true)
			if point.z>=113 and point.z<=127 and point.x>=125 and point.x<=150: occupied_frontage_avoided = false
		check(occupied_frontage_avoided,"city circuit avoids the occupied parking frontage on Warehouse Way")
		for index in range(1,authored.point_count-1):
			var incoming := authored.get_point_position(index)-authored.get_point_position(index-1)
			var outgoing := authored.get_point_position(index+1)-authored.get_point_position(index)
			if incoming.length()>.1 and outgoing.length()>.1:
				check(incoming.normalized().dot(outgoing.normalized()) > -.5, "tour does not reverse an edge to reach the workshop driveway")
	authored_adapter.free()
	scene.free()
	await process_frame
	print("ARRIVAL ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
