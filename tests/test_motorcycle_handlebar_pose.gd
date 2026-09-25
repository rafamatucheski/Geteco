extends SceneTree
## Small real-rig check; no Main, traffic population, personal save or benchmark.
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DRIVING := preload("res://scripts/Driving.gd")
class Fixture extends Node3D:
	var player
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("BIKE_HANDS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func grips_from_model(bike) -> Dictionary:
	var grips := {}
	for part in bike.visual.find_children("*", "MeshInstance3D", true, false):
		if part.get_meta("wheel_spins", true) != false: continue
		var material: Material = part.material_override if part.material_override else part.mesh.surface_get_material(0)
		if not material is StandardMaterial3D or material.albedo_color.to_html(false) != "161b20": continue
		var at: Vector3 = bike.to_local(part.to_global(part.mesh.get_aabb().get_center()))
		if at.y > .85 and absf(at.x) > .25: grips["Left" if at.x < 0 else "Right"] = part
	return grips
func run() -> void:
	var fixture := Fixture.new()
	root.add_child(fixture)
	fixture.player = ACTOR.new()
	fixture.player.is_player = true
	fixture.add_child(fixture.player)
	fixture.player.set_physics_process(false)
	var driving := DRIVING.new()
	driving.world = fixture
	for id in ["bike_urban", "bike_sport", "bike_cruiser"]:
		var bike = VEHICLE.new()
		bike.archetype = id
		fixture.add_child(bike)
		bike.set_physics_process(false)
		driving.car = bike
		var grips := grips_from_model(bike)
		check(grips.size() == 2, id + " has two authored handlebar grips")
		fixture.player.pose_vehicle(1.0)
		var plain_hip_position: Vector3 = fixture.player.skeleton.get_bone_pose_position(fixture.player.hips)
		var plain_hip_rotation: Quaternion = fixture.player.skeleton.get_bone_pose_rotation(fixture.player.hips)
		for steering in [-.48, 0.0, .48]:
			bike.rotation.y = .71
			for pivot in bike.steer_pivots.values(): pivot.rotation.y = steering
			driving._update_mounted_player()
			for side in ["Left", "Right"]:
				var part: MeshInstance3D = grips[side]
				var target := part.to_global(part.mesh.get_aabb().get_center())
				var gap: float = fixture.player.combat_palm_position(side).distance_to(target)
				if gap > .035:
					var shoulder: int = fixture.player._combat_bones[side + "Arm"]
					print("BIKE_HANDS_REACH shoulder=", bike.to_local(fixture.player.skeleton.to_global(fixture.player.skeleton.get_bone_global_pose(shoulder).origin)))
				print("BIKE_HANDS_SAMPLE ", id, " steer=", steering, " side=", side, " grip=", bike.to_local(target), " palm=", bike.to_local(fixture.player.combat_palm_position(side)), " gap=", gap)
				if "--baseline" not in OS.get_cmdline_user_args(): check(gap < .035, id + " " + side + " palm holds steered grip")
		fixture.player.pose_vehicle(1.0)
		check(fixture.player.skeleton.get_bone_pose_position(fixture.player.hips).is_equal_approx(plain_hip_position) and fixture.player.skeleton.get_bone_pose_rotation(fixture.player.hips).is_equal_approx(plain_hip_rotation), id + " normal boarding pose restores pelvis position and lean")
		for _i in 8: fixture.player.pose_vehicle(0.0)
		check(fixture.player._combat_skin.get_blend_shape_value(0) < .01 and fixture.player._combat_skin.get_blend_shape_value(1) < .01, id + " dismount pose releases both grips")
		check(fixture.player.visual.position.is_zero_approx(), id + " mounted pose leaves no visual offset for dismount")
		bike.free()
	driving.free()
	fixture.free()
	await process_frame
	print("BIKE_HANDS_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
