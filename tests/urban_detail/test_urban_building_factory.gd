extends SceneTree

## Automated test suite for UrbanBuildingFactory and native 3D urban architecture.
## Verifies that all 61 Harbor buildings instantiate properly, generate native physical collision on layer 1,
## contain zero SubViewports, preserve entrance/courtyard approaches, support swept vehicle hulls,
## enforce proper-name signage, and rotate transit boarding approaches correctly.

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func verify(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error("FAIL: " + label)

func run() -> void:
	print("--- Running UrbanBuildingFactory Automated Suite ---")
	
	var data_path := "res://world/regions/OriginalWorldData.json"
	var json_str := FileAccess.get_file_as_string(data_path)
	verify(not json_str.is_empty(), "OriginalWorldData.json read successfully")
	
	var world_data: Dictionary = JSON.parse_string(json_str)
	var harbor_buildings: Array = world_data.get("harbor_buildings", [])
	verify(harbor_buildings.size() == 61, "Found all 61 harbor buildings in registry")
	
	var scale_factor: float = float(world_data.get("unit_scale", 1.0 / 16.0))
	var factory = preload("res://world/urban_detail/UrbanBuildingFactory.gd")
	var signage = preload("res://world/urban_detail/UrbanSignage.gd")
	
	# 1. Pedestrian Capsule Probe
	var pedestrian_probe := CharacterBody3D.new()
	pedestrian_probe.name = "PedestrianProbe"
	pedestrian_probe.collision_layer = 2
	pedestrian_probe.collision_mask = 1
	var ped_col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	ped_col.shape = capsule
	ped_col.position.y = 0.85
	pedestrian_probe.add_child(ped_col)
	root.add_child(pedestrian_probe)
	
	# 2. Full Vehicle Hull Probe (2.46m width x 1.5m height x 5.21m length)
	var vehicle_probe := CharacterBody3D.new()
	vehicle_probe.name = "VehicleProbe"
	vehicle_probe.collision_layer = 2
	vehicle_probe.collision_mask = 1
	var veh_col := CollisionShape3D.new()
	var veh_box := BoxShape3D.new()
	veh_box.size = Vector3(2.46, 1.5, 5.21)
	veh_col.shape = veh_box
	veh_col.position.y = 0.75
	vehicle_probe.add_child(veh_col)
	root.add_child(vehicle_probe)
	
	var count_null_maciota := 0
	var count_reused_models := 0
	var count_reconstructed := 0
	
	for raw_b in harbor_buildings:
		var entry: Dictionary = raw_b.duplicate()
		var b_id: String = entry.id
		var b_pos := Vector3(entry.position[0] * scale_factor, 0, entry.position[1] * scale_factor)
		var b_size := Vector2(entry.size[0] * scale_factor, entry.size[1] * scale_factor)
		entry["position"] = b_pos
		entry["size"] = b_size
		
		# Test proper name extraction
		var proper_name := signage.extract_proper_name(b_id, str(entry.get("name", "")))
		for forbidden in ["BANCO /", "ROUPAS /", "POSTO /", " / 04", " / 02", " / 03", "NÃO ENTRE"]:
			verify(not forbidden in proper_name, "Proper name cleansed: %s (got '%s')" % [b_id, proper_name])
		
		# Test building construction
		var building = factory.build_building(entry)
		if b_id == "Garage":
			verify(building == null, "Maciota Garage handled by Root Catalog (returns null)")
			count_null_maciota += 1
			continue
		
		verify(building != null, "Building built: %s" % b_id)
		if building == null:
			continue
		
		# Mount building to scene tree and finalize
		root.add_child(building)
		factory.finalize_building(building, entry)
		await physics_frame
		if b_id == "ExchangeTower":
			verify(is_equal_approx(float(building.height), 8.0), "ExchangeTower preserves the V1 128 px skyline override")
		elif b_id == "CivicTower":
			verify(is_equal_approx(float(building.height), 95.0 / 16.0), "CivicTower preserves the V1 95 px skyline override")
		
		# Count categories
		if b_id in ["Clinic", "NorthFrontage2", "CanalHomesWest", "cemetery_keeper"]:
			count_reused_models += 1
		else:
			count_reconstructed += 1
		
		# 1. No SubViewport rule
		var viewports := building.find_children("*", "SubViewport", true, false)
		verify(viewports.is_empty(), "Zero SubViewports: %s" % b_id)
		
		# 2. Native Physical Collision on Layer 1
		var bodies := building.find_children("*", "StaticBody3D", true, false)
		verify(not bodies.is_empty(), "Collision bodies present: %s" % b_id)
		for body in bodies:
			verify(body.collision_layer & 1 != 0, "Body on layer 1: %s (%s)" % [b_id, body.name])
		
		# 3. Clean signage and labels (proper name only)
		for label in building.find_children("*", "Label3D", true, false):
			var text: String = label.text
			for forbidden in ["BANCO /", "ROUPAS /", "POSTO /", " / 04", " / 02", "NÃO ENTRE DE MADRUGADA"]:
				verify(not forbidden in text, "Label proper name on %s: '%s'" % [b_id, text])
		
		# 4. Geometry and Clearance Invariants
		if b_id == "FoundryLofts":
			# Courtyard (southwest) must remain open for player/vehicle passage
			var courtyard_point := b_pos + Vector3(-b_size.x * 0.28, 0.1, b_size.y * 0.25)
			pedestrian_probe.global_position = courtyard_point
			verify(pedestrian_probe.move_and_collide(Vector3.UP * 0.001, true) == null, "FoundryLofts courtyard is open")
		
		elif b_id == "MotorWorkshop":
			# Full vehicle hull (2.46m x 1.5m x 5.21m) driving through the bay from entrance (Z=+5.0) to inside (Z=-1.0)
			vehicle_probe.global_position = b_pos + Vector3(0, 0.75, 5.0)
			var sweep_col = vehicle_probe.move_and_collide(Vector3(0, 0, -6.0), true)
			verify(sweep_col == null, "MotorWorkshop drive-in bay accommodates full vehicle hull sweep")
			
			# Check that rear wall blocks excessive penetration past the bay
			vehicle_probe.global_position = b_pos + Vector3(0, 0.75, -1.0)
			var rear_col = vehicle_probe.move_and_collide(Vector3(0, 0, -4.0), true)
			verify(rear_col != null, "MotorWorkshop rear wall physically stops vehicles at back")
		
		elif building is UrbanShopfrontBuilding:
			# Test the actual authored doorway axis, stopping immediately in front of
			# the recessed door. The rear body is deliberately solid and must not be
			# crossed by this exterior-approach probe.
			var half_d: float = b_size.y * 0.5
			var is_corner: bool = entry.get("kind", "") in ["corner_shop", "corner_diner"] or b_id.begins_with("Corner")
			var door_x: float = -b_size.x * 0.15 if is_corner else 0.0
			# The collider itself is already centred 0.85 m above the body origin.
			pedestrian_probe.global_position = b_pos + Vector3(door_x, 0.0, half_d + 1.0)
			var alcove_col = pedestrian_probe.move_and_collide(Vector3(0, 0, -1.45), true)
			var blocker := "none" if alcove_col == null else str(alcove_col.get_collider().name)
			verify(alcove_col == null, "Shopfront %s entrance alcove allows unblocked pedestrian access (blocker=%s)" % [b_id, blocker])
		
		building.free()
		await physics_frame
	
	verify(count_null_maciota == 1, "Verified 1 Maciota Garage place returning null")
	# CemeteryKeeper is catalog-only and therefore not one of these 61 JSON rows.
	verify(count_reused_models == 3, "Verified 3 reused authored 3D models in the 61-row registry (Hospital, Ammunation, Residence)")
	verify(count_reconstructed == 57, "Verified 57 native reconstructed 3D buildings")
	verify(count_null_maciota + count_reused_models + count_reconstructed == 61, "Verified exact total of 61 Harbor building records")
	
	print("Verified all 61 building records successfully.")
	
	# Test Transit Station Models
	print("Testing UrbanTransitStation3D and rotated boarding approaches...")
	var test_angle := 1.57079632679 # 90 degrees
	var station_wrapper = preload("res://world/urban_detail/UrbanTransitStation3D.gd").new()
	station_wrapper.station_type = UrbanTransitStation3D.StationType.TUBE_STOP
	station_wrapper.orientation_angle = test_angle
	root.add_child(station_wrapper)
	await physics_frame
	verify(station_wrapper.find_children("*", "SubViewport", true, false).is_empty(), "Tube stop has zero SubViewports")
	verify(not station_wrapper.find_children("*", "StaticBody3D", true, false).is_empty(), "Tube stop has native StaticBody3D collision")
	
	# Verify rotated boarding approach matches rotated geometry
	var approach: Vector3 = station_wrapper.get_boarding_approach()
	var expected_pt: Vector2 = Vector2(123.0, 14.0).rotated(test_angle)
	var expected_approach := Vector3(expected_pt.x / UrbanStationModel3D.PPM, 0.20, expected_pt.y / (UrbanStationModel3D.PPM * UrbanStationModel3D.FLOOR_Y))
	verify(approach.distance_to(expected_approach) < 0.05, "Tube stop boarding approach rotated correctly by orientation_angle")
	station_wrapper.free()
	
	var terminal_wrapper = preload("res://world/urban_detail/UrbanTransitStation3D.gd").new()
	terminal_wrapper.station_type = UrbanTransitStation3D.StationType.COACH_TERMINAL
	root.add_child(terminal_wrapper)
	await physics_frame
	verify(terminal_wrapper.find_children("*", "SubViewport", true, false).is_empty(), "Coach terminal has zero SubViewports")
	verify(not terminal_wrapper.find_children("*", "StaticBody3D", true, false).is_empty(), "Coach terminal has native StaticBody3D collision")
	terminal_wrapper.free()
	
	pedestrian_probe.free()
	vehicle_probe.free()
	
	print("--- TEST RESULTS: %s (Failures: %d) ---" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	if not failures.is_empty():
		for f in failures:
			print(" - ", f)
	quit(0 if failures.is_empty() else 1)
