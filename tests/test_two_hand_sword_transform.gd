extends SceneTree
## Regressão: a empunhadura autoral de quatro casas decimais precisa continuar uma rotação válida
## durante toda a transição de uma mão para duas mãos.
const ACTOR = preload("res://scripts/Actor.gd")
const GAMEPLAY = preload("res://gameplay/Gameplay.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("SWORD_TRANSFORM ", "PASS " if ok else "FAIL ", label)

func is_rotation(basis: Basis) -> bool:
	return basis.is_finite() and absf(basis.determinant() - 1.0) < 0.00001 \
		and basis.transposed().is_equal_approx(basis.inverse())

func run() -> void:
	var actor := ACTOR.new()
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	skeleton.add_bone("RightHand")
	skeleton.add_bone("LeftHand")
	actor.skeleton = skeleton
	actor._combat_bones = {"RightHand": 0, "LeftHand": 1}
	skeleton.transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.2), Vector3(3, 2, 1))
	var grip: Transform3D = GAMEPLAY.HAND_KATANA_GUARD
	grip.origin = Vector3(0.02, 0.01, -0.03)
	for distance in [0.0, 0.005, 0.15, 0.25, 0.30, 0.40]:
		skeleton.set_bone_pose_position(1, Vector3(0, 0, distance / 1.2))
		skeleton.force_update_all_bone_transforms()
		var result: Transform3D = actor._two_hand_sword_transform(grip)
		check(is_rotation(result.basis), "proper rotation at hand distance %.3f" % distance)
		check(result.origin.is_equal_approx(skeleton.global_position + Basis(Vector3.UP, 0.7) * grip.origin), "grip stays on right hand at %.3f" % distance)
		if distance == 0.15:
			check((-result.basis.z).dot(skeleton.global_basis * Vector3.FORWARD / 1.2) > 0.99999, "two hands align blade with handle")
		elif distance >= 0.30 or distance <= 0.005:
			check(result.basis.is_equal_approx(Basis(Vector3.UP, 0.7) * grip.basis.orthonormalized()), "released/coincident support preserves authored orientation")
		else:
			var start := (Basis(Vector3.UP, 0.7) * grip.basis).orthonormalized()
			var target := Basis.looking_at(skeleton.global_basis * Vector3.FORWARD, start.y)
			var from_start := start.get_rotation_quaternion().angle_to(result.basis.get_rotation_quaternion())
			var to_target := target.get_rotation_quaternion().angle_to(result.basis.get_rotation_quaternion())
			check(absf(from_start - to_target) < 0.0001, "half support blends halfway without identity fallback")
	actor._combat_bones.erase("LeftHand")
	check(is_rotation(actor._two_hand_sword_transform(grip).basis), "missing support hand keeps a valid rotation")
	actor.free()
	skeleton.queue_free()
	await process_frame
	print("SWORD_TRANSFORM checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
