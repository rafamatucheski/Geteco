extends SceneTree
## Physical fixture: real helicopter, ropes, PoliceAgents, K9 and Godot bodies.
## No FPS/depth claim: rendered production scenarios are a separate gate.
const DIRECTOR = preload("res://gameplay/police_response/air_k9/PoliceAirK9Director.gd")
const HELICOPTER = preload("res://gameplay/police_response/air_k9/PoliceHelicopter.gd")
const DOG = preload("res://gameplay/police_response/air_k9/PoliceK9.gd")
var failures: Array[String] = []

class State extends RefCounted:
	var place_id := ""
	var region_id := "harbor"
	var world_state := {"time": 0.9}
	func weapons_allowed() -> bool: return place_id not in ["maciota", "harbor_garage"]

class Controller extends Node3D:
	var state := State.new()
	var stars := 3
	var health := 100.0
	var player: CharacterBody3D
	var police: Array[CharacterBody3D] = []
	var last_known := Vector3(12, 0, 0)
	var last_known_valid := true
	var contacts := 0
	var force := false
	var surrender := false
	var restraint := 0.0
	var world: Node3D
	func pursuit_target() -> Node3D: return player
	func police_force_authorized() -> bool: return force
	func police_surrendering() -> bool: return surrender
	func police_can_see(_officer: CharacterBody3D) -> bool: return false
	func find_path(_start: Vector3, finish: Vector3) -> PackedVector3Array: return PackedVector3Array([finish])
	func report_contact(point: Vector3) -> void: contacts += 1; last_known = point
	func damage_player(amount: float) -> void: health = maxf(0.0, health - amount)
	func police_k9_restraint(seconds: float) -> void: restraint = seconds
	func police_arrest_warning() -> void: pass
	func drop_ammo(_point: Vector3, _weapon: String) -> void: pass

class Handler extends CharacterBody3D:
	var dead := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("AIR_K9 PASS " if value else "AIR_K9 FAIL ") + label)
	if not value: failures.append(label); push_error(label)

func box(parent: Node3D, label: String, point: Vector3, size: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	result.name = label
	result.position = point
	result.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	result.add_child(collider)
	parent.add_child(result)
	return result

func body_shape(body: CharacterBody3D) -> void:
	body.collision_layer = 2
	body.collision_mask = 7
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = 0.86
	body.add_child(collider)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, "Land", Vector3(0, -0.2, 0), Vector3(150, 0.4, 150)).set_meta("police_landing_ground", true)
	var gameplay := Controller.new()
	world.add_child(gameplay)
	gameplay.player = CharacterBody3D.new()
	body_shape(gameplay.player)
	gameplay.player.position = Vector3(12, 0.05, 0)
	world.add_child(gameplay.player)
	var director := DIRECTOR.new()
	director.configure(gameplay)
	gameplay.add_child(director)
	director.set_physics_process(false)
	await frames(2)
	var dispatched := Handler.new()
	world.add_child(dispatched)
	dispatched.add_to_group("v2_police_officers")
	check(director.officer_count() == 1, "dispatch officer outside Gameplay.police still consumes an aerial slot")
	gameplay.police.append(dispatched)
	check(director.officer_count() == 1, "officer shared by group and array is counted once")
	dispatched.set_meta("police_rappelling", true)
	check(director.officer_count() == 0, "suspended personnel are covered by reservations without double count")
	gameplay.police.clear()
	dispatched.queue_free()
	await frames(2)
	var busy_squad: Array[CharacterBody3D] = []
	for index in 5:
		var occupied_slot := Handler.new()
		world.add_child(occupied_slot)
		occupied_slot.add_to_group("v2_police_officers")
		busy_squad.append(occupied_slot)
	check(director.officer_limit() == 8 and not director.launch_helicopter({"center": Vector3.ZERO, "points": []}), "three-star aerial squad shares the eight-officer ground budget")
	for officer in busy_squad: officer.queue_free()
	await frames(2)
	var points: Array[Vector3] = []
	for offset in DIRECTOR.DROP_OFFSETS: points.append(offset + Vector3.UP * 0.04)
	check(director.landing_column_clear(points[0]), "clear ground admits the complete officer capsule and column")
	var roof := box(world, "BuildingRoof", Vector3(0, 4.0, 0), Vector3(8, 0.3, 8))
	await frames(2)
	check(not director.is_landing_ground(director.ground_hit(Vector3(0, 4.2, 0))), "roof cannot become a rappel landing surface")
	check(not director.landing_column_clear(points[0]), "roof blocks downward swept capsule")
	roof.queue_free()
	await frames(2)
	var heli := HELICOPTER.new()
	heli.director = director
	heli.landing_zone = {"center": Vector3(0, 0.04, 0), "points": points}
	heli.position = Vector3(0, 13.04, 0)
	heli.mode = "hover"
	director.helicopter = heli
	gameplay.set_meta("police_air_reserved_slots", 4)
	director.add_child(heli)
	heli.set_physics_process(false)
	await frames(2)
	check(heli.rope_mesh.multimesh.instance_count == 40 and not heli.spotlight.shadow_enabled, "four articulated ropes and shadowless spotlight have bounded cost")
	heli._sense()
	check(heli.sees_player and gameplay.contacts > 0, "aircraft reports actual unobstructed contact")
	var wall := box(world, "SightWall", Vector3(5, 10, 0), Vector3(0.7, 20, 30))
	await frames(2)
	var before := gameplay.contacts
	heli._sense()
	check(not heli.sees_player and gameplay.contacts == before, "helicopter does not report through a building")
	wall.queue_free()
	await frames(2)
	var airborne_seen := false
	var rope_moved := false
	var glove_contacts_seen := false
	var landing_pose_seen := false
	var rotor_start: float = heli.rotor.rotation.y
	var initial_rope := Transform3D.IDENTITY
	for index in 960:
		heli._physics_process(1.0 / 60.0)
		if heli.mode == "rappel" and not heli.rappellers.is_empty():
			var officer: CharacterBody3D = heli.rappellers[0].officer
			airborne_seen = airborne_seen or (officer.global_position.y > 2.0 and not officer.is_physics_processing())
			# Headless's dummy renderer returns identity for GPU instance readback.
			# Inspect the same CPU transform submitted to MultiMesh instead.
			var current: Transform3D = heli.rope_transforms[0]
			if initial_rope == Transform3D.IDENTITY: initial_rope = current
			else: rope_moved = rope_moved or not current.is_equal_approx(initial_rope)
			for entry in heli.rappellers:
				if entry.phase == "land": landing_pose_seen = true
				if not entry.contacts.get("attached", false): continue
				var controls: PackedVector3Array = heli.rope_control_points[int(entry.index)]
				if controls.size() == 11:
					glove_contacts_seen = glove_contacts_seen or (controls[2].distance_to(entry.contacts.upper_hand) < 0.005 and controls[3].distance_to(entry.contacts.harness) < 0.005 and controls[4].distance_to(entry.contacts.lower_hand) < 0.005)
		await physics_frame
		# Freeze delivered real officers only in the fixture to inspect landings.
		for officer in gameplay.police: officer.set_physics_process(false)
		if heli.mode == "depart": break
	check(airborne_seen, "officers descend physically with ground AI suspended")
	check(rope_moved, "segmented rope geometry changes while officers descend")
	check(glove_contacts_seen, "rappel rope passes through actual upper glove, harness descender and braking glove")
	check(landing_pose_seen, "officers absorb landing before releasing rope and resuming combat")
	check(not is_equal_approx(rotor_start, heli.rotor.rotation.y), "main rotor keeps rotating throughout the full insertion")
	check(gameplay.police.size() == 4 and heli.deployed_count == 4, "exactly four real PoliceAgents land")
	check(heli.mode == "depart" and int(gameplay.get_meta("police_air_reserved_slots", -1)) == 0, "transport departs and releases all reserved ground slots")
	for officer in gameplay.police:
		check(officer.global_position.y < 0.16 and officer.collision_mask == 7 and not officer.get_meta("police_rappelling", false), "landed officer retains collision and combat lifecycle")
	var departure_start := heli.global_position
	for index in 120:
		heli._physics_process(1.0 / 60.0)
		await physics_frame
	check(is_instance_valid(heli) and heli.global_position.y > departure_start.y + 2.5 and heli._door_open < 0.1, "departure visibly climbs and closes cabin doors before flying away")
	for index in 180:
		heli._physics_process(1.0 / 60.0)
		await physics_frame
	check(Vector2(heli.global_position.x - departure_start.x, heli.global_position.z - departure_start.z).length() > 10.0 and absf(heli.rotation.y) > 0.1, "helicopter turns along its physical exit path without an early despawn")
	heli._finish()
	await frames(2)
	check(director.helicopter == null and is_equal_approx(director.helicopter_timer, 60.0), "return cooldown starts after aircraft departure")
	for officer in gameplay.police: officer.queue_free()
	gameplay.police.clear()
	await frames(2)
	# Evasion during insertion must not erase people in midair or deploy the
	# remaining squad after the response has been called off.
	var recalled := HELICOPTER.new()
	recalled.director = director
	recalled.landing_zone = {"center": Vector3(0, 0.04, 0), "points": points}
	recalled.position = Vector3(0, 13.04, 0)
	recalled.mode = "hover"
	director.helicopter = recalled
	gameplay.set_meta("police_air_reserved_slots", 4)
	director.add_child(recalled)
	recalled.set_physics_process(false)
	recalled._physics_process(1.85)
	recalled._physics_process(1.0 / 60.0)
	gameplay.stars = 2
	director._active = true
	director._physics_process(0.25)
	check(is_instance_valid(recalled) and not recalled.is_queued_for_deletion() and recalled.mode == "rappel" and recalled.rappellers.size() == 1, "falling below three stars preserves the aircraft and officer already attached")
	gameplay.stars = 0
	director._physics_process(0.25)
	for index in 720:
		recalled._physics_process(1.0 / 60.0)
		await physics_frame
		if recalled.mode == "depart": break
	check(recalled.mode == "depart" and recalled.deployed_count == 1 and gameplay.police.size() == 1, "evasion completes the existing descent, cancels later drops and departs physically")
	if not gameplay.police.is_empty():
		check(gameplay.police[0].get_meta("police_retiring", false) and not gameplay.police[0].is_physics_processing(), "officer landing after escape remains peaceful until offscreen retirement")
	recalled._finish()
	for officer in gameplay.police: officer.queue_free()
	gameplay.police.clear()
	gameplay.stars = 3
	await frames(2)
	var handler := Handler.new()
	body_shape(handler)
	handler.position = Vector3(-3, 0.04, 0)
	world.add_child(handler)
	var dog := DOG.new()
	dog.director = director
	dog.handler = handler
	dog.position = Vector3(0, 0.04, 0)
	director.add_child(dog)
	director.dogs.append(dog)
	dog.set_physics_process(false)
	gameplay.player.position = Vector3(1.0, 0.04, 0)
	await frames(2)
	check(not dog.can_bite(gameplay.player), "stars alone do not authorize K9 force")
	gameplay.force = true
	check(dog.can_bite(gameplay.player), "near visible target with live handler permits restraint")
	gameplay.surrender = true
	check(not dog.can_bite(gameplay.player), "surrender cancels K9 attack immediately")
	gameplay.surrender = false
	gameplay.state.place_id = "maciota"
	check(not dog.can_bite(gameplay.player), "Maciota safe area forbids K9 attacks")
	gameplay.state.place_id = ""
	handler.dead = true
	check(not dog.can_bite(gameplay.player), "K9 cannot attack without its handler")
	handler.dead = false
	wall = box(world, "BiteWall", Vector3(0.5, 1.0, 0), Vector3(0.1, 2.0, 8.0))
	await frames(2)
	check(not dog.can_bite(gameplay.player), "bite cannot cross a thin wall")
	gameplay.player.position = Vector3(4, 0.04, 0)
	gameplay.last_known = gameplay.player.position
	for index in 100:
		dog._physics_process(1.0 / 60.0)
		await physics_frame
	check(dog.global_position.x < 0.2, "real moving K9 full-body collider remains blocked by wall")
	wall.queue_free()
	await frames(2)
	dog.position = Vector3(0, 0.04, 0)
	gameplay.player.position = Vector3(1.0, 0.04, 0)
	gameplay.health = 3.0
	dog._cooldown = 0.0
	await frames(2)
	dog._physics_process(1.0 / 60.0)
	check(gameplay.health >= 1.0 and gameplay.restraint > 0.0, "K9 restrains wounded player without killing")
	gameplay.stars = 2
	director._physics_process(0.25)
	check(dog.withdrawing and not dog.can_bite(gameplay.player), "K9 disengages when response level falls without disappearing on camera")
	gameplay.stars = 0
	director._physics_process(0.25)
	director.clear_response()
	await frames(2)
	check(director.dogs.is_empty() and not is_instance_valid(dog), "response cleanup removes K9 and callbacks safely")
	world.queue_free()
	await process_frame
	print("AIR_K9 failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
