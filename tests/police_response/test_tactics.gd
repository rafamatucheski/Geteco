extends SceneTree
## Focused physical contracts. Run headless for policy/collision, then with
## --capture for native interior depth evidence; neither certifies frame time.
const OFFICER := preload("res://gameplay/PoliceAgent.gd")
const TACTICS := preload("res://gameplay/police_response/tactics/PoliceTactics.gd")
const PURSUIT := preload("res://gameplay/police_response/tactics/PoliceInteriorPursuit.gd")
const INTERIOR_NAV := preload("res://gameplay/police_response/tactics/PoliceInteriorNavigation.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")

class State extends RefCounted:
	var place_id := ""
	var region_id := "harbor"
	func weapons_allowed() -> bool: return place_id not in ["maciota", "harbor_garage"]

class Session extends Node:
	var room: Node3D
	var return_point := Vector3(60, 0, 0)
	func is_transition_blocked() -> bool: return false

class World extends Node3D:
	var session: Node
	var dispatch: Node3D

class Controller extends Node3D:
	var state := State.new()
	var world: Node3D
	var player: CharacterBody3D
	var police: Array = []
	var stars := 6
	var health := 100.0
	var last_known_valid := true
	var last_known := Vector3.ZERO
	var contact_age := 0.0
	var force := false
	var surrender := false
	var shots := 0
	var arrests := 0
	func police_force_authorized() -> bool: return force and not surrender and state.weapons_allowed()
	func police_surrendering() -> bool: return surrender
	func police_can_arrest() -> bool: return stars > 0 and (surrender or not force)
	func pursuit_target() -> Node3D: return player
	func police_can_see(officer: CharacterBody3D) -> bool:
		if str(officer.get_meta("police_place_id", "")) != state.place_id or not state.weapons_allowed(): return false
		var ray := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3.UP * 1.4, player.global_position + Vector3.UP, 7, [officer.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		return hit.is_empty() or hit.collider == player
	func police_shoot(_officer: CharacterBody3D, _amount: float, _weapon: String) -> void: shots += 1
	func report_contact(point: Vector3) -> void:
		last_known = point
		contact_age = 0
		set_meta("police_contact_place_id", state.place_id)
	func find_path(_from: Vector3, _to: Vector3) -> PackedVector3Array: return PackedVector3Array()
	func arrest_player() -> bool:
		arrests += 1
		return true
	func police_arrest_warning() -> void: pass
	func police_reload(_officer: Node3D, _weapon: String) -> void: pass
	func drop_ammo(_point: Vector3, _weapon: String) -> void: pass

var failures: Array[String] = []
var checks := 0
var world: World
var controller: Controller

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("TACTICS PASS " if ok else "TACTICS FAIL ") + label)
	if not ok: failures.append(label)

func box(parent: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = point
	return body

func make_officer(tier: int, point: Vector3) -> CharacterBody3D:
	var officer := OFFICER.new()
	officer.controller = controller
	officer.tier = tier
	world.add_child(officer)
	officer.global_position = point
	officer.set_physics_process(false)
	return officer

func run() -> void:
	world = World.new()
	root.add_child(world)
	world.session = Session.new()
	world.add_child(world.session)
	controller = Controller.new()
	controller.world = world
	world.add_child(controller)
	controller.player = CharacterBody3D.new()
	controller.player.collision_layer = 2
	controller.player.collision_mask = 1
	var player_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	player_shape.shape = capsule
	player_shape.position.y = .86
	controller.player.add_child(player_shape)
	world.add_child(controller.player)
	controller.player.position = Vector3(0, .05, -10)
	box(world, Vector3(0, -.2, 0), Vector3(160, .4, 100))
	await physics_frame
	await physics_frame
	var unique := {}
	for tier in 5: unique[TACTICS.doctrine(tier)] = true
	check(unique.size() == 5, "five distinct response doctrines")
	var officers: Array[CharacterBody3D] = []
	for tier in 5:
		var officer := make_officer(tier, Vector3(tier * 3, .05, 0))
		officers.append(officer)
		check(not officer._try_fire(), "tier %d does not fire merely because of six stars" % tier)
	controller.force = true
	controller.surrender = true
	var arresting: CharacterBody3D = officers[4]
	arresting.response_aggression = 12.0
	for i in 6: arresting._update_arrest(true, 1.5, arresting._force_authorized(), 1.0)
	check(controller.arrests > 0 and controller.shots == 0, "surrender at six stars overrides recent aggression and permits arrest")
	controller.surrender = false
	controller.force = true
	var tactics := TACTICS.new()
	var detective: CharacterBody3D = officers[1]
	detective.position = Vector3(0, .05, 10)
	detective.set_meta("police_tactic_slot", 0)
	var left: Dictionary = tactics.plan(detective, Vector3.ZERO, true, 0.0)
	detective.set_meta("police_tactic_slot", 1)
	var right: Dictionary = tactics.plan(detective, Vector3.ZERO, true, 0.0)
	check(signf(left.goal.x) != signf(right.goal.x), "detectives flank on opposite sides")
	var swat: CharacterBody3D = officers[2]
	swat.position = Vector3(0, .05, 12)
	swat.sees_player = true
	swat.set_meta("police_tactic_slot", 0)
	var advance: Dictionary = tactics.plan(swat, Vector3.ZERO, true, 0.0)
	swat.set_meta("police_tactic_slot", 1)
	var cover: Dictionary = tactics.plan(swat, Vector3.ZERO, true, 0.0)
	check(not advance.hold and cover.hold, "SWAT alternates moving and covering pairs")
	var army: Dictionary = tactics.plan(officers[4], Vector3.ZERO, true, 0.0)
	check(float(army.speed) < float(advance.speed), "Army advances at a controlled walking pace")
	var fbi: CharacterBody3D = officers[3]
	fbi.position = Vector3(0, .05, 3)
	fbi.set_meta("police_tactic_slot", 0)
	var containment: Dictionary = tactics.plan(fbi, Vector3.ZERO, true, 0.0)
	check(containment.goal.distance_to(Vector3.ZERO) > 10.0, "FBI retreats from close contact toward a containment perimeter")
	var cover_wall := box(world, Vector3(-1, 1, 6), Vector3(.8, 2, .5))
	await physics_frame
	await physics_frame
	swat.reload_timer = 2.0
	var reloading: Dictionary = tactics.plan(swat, Vector3.ZERO, true, 0.0)
	check(reloading.doctrine == "reload_in_cover" and tactics.point_clear(swat, reloading.goal), "SWAT reload uses real occluding geometry and a clear capsule destination")
	cover_wall.queue_free()
	swat.reload_timer = 0.0
	await physics_frame
	var barrier := box(world, Vector3(0, 1.0, 4), Vector3(40, 2, .8))
	await physics_frame
	await physics_frame
	var patrol: CharacterBody3D = officers[0]
	patrol.position = Vector3(0, .05, 6)
	controller.player.position = Vector3(0, .05, 0)
	check(not controller.police_can_see(patrol), "solid wall blocks officer line of sight")
	check(not tactics.segment_clear(patrol, patrol.global_position, controller.player.global_position), "full-capsule route rejects passage through wall")
	check(not tactics.point_clear(patrol, Vector3(0, .05, 4)), "tactical goal cannot occupy a solid")
	for i in 45:
		patrol._move(Vector3(0, 0, -12), 1.0 / 60.0)
		await physics_frame
	check(patrol.position.z > 4.65, "real PoliceAgent movement remains outside solid after repeated swept motion")
	barrier.queue_free()
	await physics_frame
	await physics_frame
	check(controller.police_can_see(patrol), "LOS returns after barrier is removed (positive control)")
	for officer in officers: officer.queue_free()
	await physics_frame
	await _test_interior()
	print("TACTICS checks=%d failures=%s" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_interior() -> void:
	var room := PLACES.create_place("harbor_ammunation")
	world.add_child(room)
	room.position = Vector3(0, 0, -2400)
	await physics_frame
	await physics_frame
	var manager := PURSUIT.new()
	controller.add_child(manager)
	manager.configure(controller)
	manager.set_physics_process(false)
	controller.player.position = world.session.return_point
	controller.report_contact(controller.player.position)
	manager._physics_process(.1)
	world.session.room = room
	controller.state.place_id = "harbor_ammunation"
	controller.player.position = room.spawn_position + Vector3(0, .05, -2)
	manager._physics_process(.1)
	check(manager.knows_current_interior(), "observed doorway crossing licenses interior pursuit")
	var visitor := make_officer(2, world.session.return_point + Vector3.UP * .05)
	check(not controller.police_can_see(visitor), "exterior officer cannot see through technical interior boundary")
	var obstruction := box(world, room.exit_position + Vector3(0, 1, -.9), Vector3(5, 2, 5))
	await physics_frame
	await physics_frame
	check(not manager.admit(visitor), "occupied interior entrance rejects full officer capsule")
	obstruction.queue_free()
	await physics_frame
	await physics_frame
	check(manager.admit(visitor), "existing officer enters at a clear point beside real room doorway")
	check(visitor.get_meta("police_place_id", "") == "harbor_ammunation" and controller.police.has(visitor), "interior context and finite officer ownership are preserved")
	check(room.is_floor_clear(room.to_local(visitor.global_position), .34) and visitor.collision_mask == 7, "admission keeps native furniture collision and floor support")
	var navigator := INTERIOR_NAV.new()
	navigator.configure(room)
	var route := navigator.path(visitor.global_position, room.spawn_position + Vector3(0, 0, -2))
	var clear_route := not route.is_empty()
	for point in route: clear_route = clear_route and room.is_floor_clear(room.to_local(point), .34)
	check(clear_route, "interior route uses actual room furniture footprints")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = room.camera_size
		camera.position = room.camera_target + Vector3(0, 18, 15)
		camera.look_at(room.camera_target)
		camera.current = true
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, -25, 0)
		world.add_child(sun)
		var folder := OS.get_temp_dir().path_join("geteco-police-interior-response")
		DirAccess.make_dir_recursive_absolute(folder)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join("native-shop-visitor.png")) == OK, "render native shop and visiting officer")
	controller.state.place_id = ""
	world.session.room = null
	manager._physics_process(.1)
	check(visitor.is_queued_for_deletion() and not controller.police.has(visitor), "room exit releases visitor without duplicating exterior crew")
	await physics_frame
	controller.state.place_id = "harbor_ammunation"
	world.session.room = room
	manager._last_seen_age = 30.0
	manager._physics_process(.1)
	check(not manager.knows_current_interior(), "unobserved later entry does not reveal hidden player")
	manager.report_interior("harbor_ammunation")
	check(manager.knows_current_interior(), "actual interior report permits a search")
	controller.state.place_id = "maciota"
	manager._physics_process(.1)
	manager.report_interior("maciota")
	check(not manager.knows_current_interior(), "Maciota cannot become a police assault context")
	room.queue_free()
	manager.queue_free()
