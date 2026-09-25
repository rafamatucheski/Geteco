extends SceneTree
## Focused checks for the room support and counter interaction seen in 24/09 video.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const ROBBERY_ACTOR := preload("res://runtime/RobberyActor.gd")
var failures: Array[String] = []
var stage: Node3D

class HeistStub extends RefCounted:
	var data := {"bank_shots": false}
	var session: Dictionary
	func inside(place: String) -> bool: return place == "harbor_bank"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	print(("VIDEO_INTERIOR PASS " if ok else "VIDEO_INTERIOR FAIL ") + label + " " + detail)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	for id in ["harbor_ammunation", "harbor_bank", "mountain_gunshop"]:
		var room = PLACES.create_place(id)
		stage.add_child(room)
		var player = ACTOR.new()
		player.is_player = true
		player.input_locked = true
		stage.add_child(player)
		player.teleport(room.spawn_position + Vector3.UP * .04)
		await frames(90)
		var feet: Dictionary = {}
		for bone in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "Hips"]:
			var index: int = player.skeleton.find_bone(bone)
			if index >= 0:
				feet[bone] = player.skeleton.to_global(player.skeleton.get_bone_global_pose(index).origin).y
		check(player.is_on_floor() and absf(player.position.y) < .08, id + " physical floor support", "y=%f feet=%s" % [player.position.y, feet])
		for bone in ["LeftFoot", "RightFoot"]:
			check(feet.has(bone) and float(feet[bone]) > -.05, id + " " + bone + " above floor", str(feet))
		if id in ["harbor_ammunation", "mountain_gunshop"]:
			var service: Vector3 = room.to_local(room.interaction_points.service)
			var counter_x := 1.7 if id == "mountain_gunshop" else 0.0
			check(service.distance_to(Vector3(counter_x,0,-.9)) < .1 and room.is_floor_clear(service), id + " service beside counter on clear floor", str(service))
			check(service.distance_to(Vector3(counter_x,0,-1.25)) < 1.5, id + " counter approach has service")
			check(service.distance_to(room.definition.spawn + Vector3(0,0,-1)) > 1.5, id + " old middle-room target has no service")
		if id == "harbor_bank": await _check_guards(player)
		player.queue_free()
		room.queue_free()
		await frames(2)
	stage.queue_free()
	await process_frame
	print("VIDEO_INTERIOR failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_guards(player: Node3D) -> void:
	var heist := HeistStub.new()
	heist.session = {"world": {"player": player, "gameplay": {"health": 100.0}}, "state": {"equipped_weapon": "pistol"}}
	for shotgun in [false, true]:
		var guard = ROBBERY_ACTOR.new()
		guard.guard = true
		guard.shotgun = shotgun
		guard.heist = heist
		stage.add_child(guard)
		guard.set_physics_process(false)
		await frames(2)
		for target in [Vector3(-4,0,3), Vector3(4,0,3), Vector3(0,0,-3)]:
			player.teleport(target)
			for _i in 40: guard._physics_process(1.0 / 60.0)
			var expected: Vector3 = (target - guard.global_position).normalized()
			var barrel: Vector3 = -guard.weapon.global_basis.z.normalized()
			var facing: Vector3 = guard.visual.body.global_basis.z.normalized()
			var label := ("shotgun" if shotgun else "pistol") + " target " + str(target)
			check(barrel.dot(expected) > .99, label + " barrel points toward player", str(barrel))
			check(facing.dot(expected) > .99, label + " body faces same target")
			check(guard.visual.body.hand_targets[0] is Vector3 and guard.visual.body.hand_targets[1] is Vector3, label + " both hands grip aimed weapon")
			check((guard.visual.muzzle_position() - guard.global_position).dot(expected) > .1, label + " muzzle is in front")
		guard.queue_free()
		await frames(2)
