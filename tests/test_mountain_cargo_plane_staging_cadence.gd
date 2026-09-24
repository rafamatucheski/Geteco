extends SceneTree

const CARGO_PLANE := preload("res://world/mountain_pass/MountainCargoPlane.gd")
const MAX_TEST_FRAMES := 48
const SIXTY_FPS_BUDGET_USEC := 16667

var failures: Array[String] = []

class TreasurePlayer extends Node2D:
	var is_dead := false
	var world_pickups_collected: Array[String] = []
	var money := 0
	var notices: Array[String] = []
	func _show_weapon_notice(message: String) -> void:
		notices.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func _count_type(node: Node, type_name: StringName) -> int:
	var count := 1 if node.is_class(type_name) else 0
	for child in node.get_children(): count += _count_type(child, type_name)
	return count

func _run() -> void:
	root.get_node("SaveManager")._save_dir = "user://cargo-staging-validation/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	var host := Node2D.new()
	root.add_child(host)
	current_scene = host

	var plane := CARGO_PLANE.new()
	var add_started := Time.get_ticks_usec()
	host.add_child(plane)
	var initial_add_usec := Time.get_ticks_usec() - add_started
	var pickup := plane.get_node_or_null("CargoSMG")
	var floor_weapon := plane.model.get_node_or_null("CargoSMGModel/FloorWeapon") if plane.model else null
	var treasure := plane.model.get_node_or_null("SmugglerTreasure") if plane.model else null
	_check(not plane.is_presentation_staging_complete(), "non-essential cargo presentation is not built synchronously")
	_check(pickup != null and floor_weapon != null, "functional SMG pickup shell exists immediately")
	_check(treasure != null and plane.treasure_lid != null and plane.gold != null, "treasure, lid and gold state exist immediately")
	_check(plane.get_node_or_null("FuselageWall") != null and plane.get_node_or_null("TreasureCrate") != null, "aircraft collision solids exist before presentation staging")
	_check(pickup.pickup_id == "mountain_cargo_plane_smg_01" and pickup.weapon_id == "smg" and pickup.ammo == 20, "SMG loot identity and ammunition are preserved")
	_check(_count_type(pickup, &"CollisionShape2D") == 1, "SMG pickup keeps its interaction collision")

	var observed_max_steps := 0
	var previous_total_steps := 0
	for frame in MAX_TEST_FRAMES:
		await process_frame
		var metrics := plane.get_presentation_staging_metrics()
		var frame_steps := int(metrics.steps) - previous_total_steps
		previous_total_steps = int(metrics.steps)
		observed_max_steps = maxi(observed_max_steps, frame_steps)
		if bool(metrics.complete): break
	var final_metrics := plane.get_presentation_staging_metrics()
	_check(bool(final_metrics.complete), "cargo presentation staging completes within the finite test window")
	_check(observed_max_steps <= plane.MAX_PRESENTATION_STEPS_PER_FRAME, "staging never exceeds the authored per-frame step limit")
	_check(int(final_metrics.peak_usec) <= SIXTY_FPS_BUDGET_USEC, "isolated staged work remains within one 60 FPS frame")
	_check(_count_type(floor_weapon, &"MeshInstance3D") > 0, "staged SMG remains a real 3D model")
	_check(plane.treasure_lid.get_child_count() == 25 and plane.gold.get_child_count() == 3, "staged chest keeps all lid, strap and gold geometry")

	var meshes_after_completion := _count_type(plane, &"MeshInstance3D")
	var steps_after_completion := int(final_metrics.steps)
	for frame in 5: await process_frame
	var settled_metrics := plane.get_presentation_staging_metrics()
	_check(int(settled_metrics.steps) == steps_after_completion, "completed staging is not executed twice")
	_check(_count_type(plane, &"MeshInstance3D") == meshes_after_completion, "completed staging does not duplicate geometry")

	var player := TreasurePlayer.new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	host.add_child(player)
	player.position = plane.project_floor(Vector2(0.55,-6.7))
	_check(plane.claim_treasure(player), "staged treasure remains claimable")
	_check(player.money == plane.REWARD and player.world_pickups_collected.has(plane.PICKUP_ID), "staged treasure preserves reward and persistence marker")
	_check(plane.treasure_lid.rotation.x < -1.0 and not plane.gold.visible, "claimed staged treasure opens and hides gold")
	plane._set_inside(player, true)
	_check(not plane.model.cutaway_roof.visible, "staging preserves aircraft cutaway")
	plane._set_inside(player, false)
	_check(plane.model.cutaway_roof.visible, "leaving the aircraft restores its roof")

	print("MOUNTAIN_CARGO_PLANE_STAGING ", JSON.stringify({
		"initial_add_usec": initial_add_usec,
		"staging": final_metrics,
		"observed_max_steps_per_frame": observed_max_steps,
		"mesh_instances": meshes_after_completion,
		"failures": failures,
	}))
	host.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
