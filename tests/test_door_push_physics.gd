extends SceneTree
## Narrow physical fixture for the real hinged facade and Dante skeleton.
class DrivingStub extends Node:
	var occupied := false
	func is_body_transition_active() -> bool: return false
class SessionStub extends Node:
	var world: Dictionary
	var state := {"place_id":"", "region_id":"harbor"}
	var ready_for_play := true
	var modal := false
	var activities = null
	var robberies = null
	func is_transition_blocked() -> bool: return false

var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	print("DOOR_PUSH_PHYSICS ", "PASS " if ok else "FAIL ", label)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player = preload("res://scripts/Actor.gd").new()
	player.is_player = true
	player.controlled_automatically = true
	stage.add_child(player)
	var camera := Camera3D.new()
	stage.add_child(camera)
	player.camera = camera
	var driving := DrivingStub.new()
	stage.add_child(driving)
	var session := SessionStub.new()
	session.world = {"player":player, "camera":camera, "driving":driving, "gameplay":{"health":100.0}}
	stage.add_child(session)
	var access = preload("res://runtime/WeaponShopEntrance.gd").new()
	access.session = session
	stage.add_child(access)
	var definition := preload("res://world/places/PlaceCatalog.gd").get_definition("cemetery_keeper").duplicate()
	definition.exterior_position = Vector3.ZERO
	access._definitions["cemetery_keeper"] = definition
	var art = preload("res://assets/regions/source/world/harbor/cemetery/CemeteryHouseExterior3D.gd").new()
	stage.add_child(art)
	var facade = preload("res://world/places/WalkupFacadeDoor.gd").install(art, definition)
	var door: Vector3 = access._door_position("cemetery_keeper", definition)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30,.2,30)
	floor_shape.shape = floor_box
	floor_body.position.y = -.1
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	player.teleport(door + Vector3(0,.08,2))
	access._push_remaining = .65
	access._facade_id = "unloaded_previous_door"
	for tick in 30:
		access._update_facade("cemetery_keeper", true, 1.0/60.0)
		await physics_frame
	check(facade.open_amount < .01, "nearby idle player keeps real leaf closed, including after facade unload")
	player.teleport(door + Vector3(0,.08,.42))
	for tick in 20:
		access._update_facade("cemetery_keeper", true, 1.0/60.0)
		await physics_frame
	check(facade.open_amount < .01, "idle contact keeps real leaf closed")
	check(player.test_move(Transform3D(Basis.IDENTITY,player.global_position),Vector3.FORWARD), "closed leaf blocks actual capsule")
	player.combat_weapon_id = "fists"
	player.automatic_direction = Vector3.FORWARD
	var partial := false
	var reached := false
	for tick in 24:
		access._update_facade("cemetery_keeper", true, 1.0/60.0)
		await physics_frame
		partial = partial or (facade.open_amount > .1 and facade.open_amount < .9)
		var hand: int = player.skeleton.find_bone("LeftHand")
		var point: Vector3 = player.skeleton.to_global(player.skeleton.get_bone_global_pose(hand).origin)
		reached = reached or (point-player.global_position).dot(Vector3.FORWARD) > .2
	check(partial and facade.open_amount > .99, "pushing animates the hinged leaf to open")
	check(reached, "Dante's left hand reaches forward with fists equipped")
	check(not player.test_move(Transform3D(Basis.IDENTITY,door+Vector3(0,.08,.42)),Vector3.FORWARD), "opened leaf admits swept full capsule")
	player.automatic_direction = Vector3.ZERO
	player.teleport(door+Vector3(0,.08,.35))
	for tick in 60:
		access._update_facade("cemetery_keeper", true, 1.0/60.0)
		await physics_frame
	check(facade.open_amount > .99, "leaf stays open while capsule occupies threshold")
	player.teleport(door+Vector3(0,.08,2))
	for tick in 60:
		access._update_facade("cemetery_keeper", true, 1.0/60.0)
		await physics_frame
	check(facade.open_amount < .01, "leaf closes after moving away")
	session.modal = true
	player.teleport(door+Vector3(0,.08,.42))
	player.automatic_direction = Vector3.FORWARD
	access._update_facade("cemetery_keeper",true,.1)
	check(facade.open_amount < .01, "modal blocks pushing")
	check(not access._push_requested(Vector3(0,2,.4),Vector3.FORWARD,.5,Vector3.FORWARD), "other storey cannot open door")
	print("DOOR_PUSH_PHYSICS checks=",checks," failures=",failures)
	stage.queue_free()
	await process_frame
	quit(1 if failures else 0)
