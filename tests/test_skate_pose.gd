extends SceneTree
## Actual Dante/civilian rigs: ankle contact, knee direction and bounded scale.
## Rendering and frame cost are validated separately in the gameplay capture.
const ACTOR = preload("res://scripts/Actor.gd")
const BOARD = preload("res://activities/skate/SkateBody.gd")
const POSE = preload("res://activities/skate/SkatePose.gd")
const KIT = preload("res://assets/civilians/CivilianMeshKit.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label); print("POSE FAIL ", label)
func run():
	var stage = Node3D.new()
	root.add_child(stage)
	var board = BOARD.new()
	stage.add_child(board)
	board.set_physics_process(false)
	for identity in [-1, 0, 3, 8]:
		var actor = ACTOR.new()
		actor.is_player = identity == -1
		actor.identity = maxi(0, identity)
		stage.add_child(actor)
		actor.set_physics_process(false)
		var model = actor.visual.get_child(0)
		model.set_process(false)
		await process_frame
		for sample in 84:
			board._throttle = 1.0 if sample < 42 else -1.0
			board.rotation.y = .7
			board.visual.rotation = Vector3(.35 if sample % 42 >= 21 else 0.0, 0, -.12)
			board.pushing = sample % 21 < 20
			board.push_phase = float(sample % 21) / 20
			board.airborne = false
			actor.global_position = board.global_position
			POSE.apply(actor, board)
			check((-actor.visual.global_basis.z).dot(-board.visual.global_basis.z) > .999, "rider faces the nose")
			var soles = POSE.feet(board)
			for index in 2:
				var label = "%s sample%s leg%s" % [identity, sample, index]
				var foot: Vector3
				var knee: Vector3
				var hip: Vector3
				var expected: Vector3 = soles[index]
				if actor.is_player:
					var side = "Left" if index == 0 else "Right"
					expected.y += actor._idle_feet[side].y
					foot = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[side + "Foot"]).origin)
					knee = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[side + "Leg"]).origin)
					hip = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[side + "UpLeg"]).origin)
				else:
					expected.y += KIT.ANKLE_HEIGHT * model.scale.y
					foot = model.feet[index].global_position
					knee = model.shins[index].global_position
					hip = model.thighs[index].global_position
				check(foot.distance_to(board.visual.to_global(expected)) < .012, label + " ankle reaches contact")
				check(board.visual.to_local(foot).x > .02 if index == 0 else board.visual.to_local(foot).x < -.02, label + " foot stays on its anatomical side without crossing legs")
				var local_knee = board.visual.to_local(knee)
				check(local_knee.z < maxf(board.visual.to_local(hip).z, board.visual.to_local(foot).z) + .025, label + " knee bends toward forward-facing toes")
				check(knee.distance_to(hip) > .3 and foot.distance_to(knee) > .3, label + " authored leg lengths")
				check((board.visual.to_local(foot).z < .01) if index == 0 else true, label + " front leg never crosses rear")
		for sample in 12:
			board.pushing = false
			board.airborne = true
			board.air_time = sample * .05
			POSE.apply(actor, board)
			var soles = POSE.feet(board)
			for index in 2:
				var expected: Vector3 = soles[index]
				var foot: Vector3
				if actor.is_player:
					var side = "Left" if index == 0 else "Right"
					expected.y += actor._idle_feet[side].y
					foot = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[side + "Foot"]).origin)
				else:
					expected.y += KIT.ANKLE_HEIGHT * model.scale.y
					foot = model.feet[index].global_position
				check(foot.distance_to(board.visual.to_global(expected)) < .012, "air tuck keeps ankle reachable")
			check(actor.visual.basis.get_scale().distance_to(Vector3.ONE) < .001, "air pose keeps unit visual scale")
		POSE.fall(actor, .55, .7)
		check(actor.visual.rotation.x < -.8 and actor.visual.position.y > .1, "fall absorbs impact toward direction of travel")
		POSE.fall(actor, 1.1, .7)
		check(absf(actor.visual.rotation.x) < .001 and actor.visual.position.length() < .001, "recovery returns to upright position within 1.1 seconds")
		POSE.restore(actor)
		check(absf(actor.visual.rotation.x) < .001 and absf(actor.visual.rotation.z) < .001, "dismount removes slope tilt")
		actor.free()
	stage.free()
	print("SKATE POSE ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
