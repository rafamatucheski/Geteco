extends SceneTree
## Production weapon geometry, flash/light and the actual outgoing tracer agree.
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const STATE := preload("res://runtime/GameState.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("VIDEO_MUZZLE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	scene.add_child(player)
	player.set_physics_process(false)
	var state := STATE.new()
	var gameplay := GAMEPLAY.new()
	gameplay.configure(scene, player, null, state)
	scene.add_child(gameplay)
	gameplay.set_physics_process(false)
	gameplay.dispatch_owned = true
	await process_frame
	var cases := [
		["pistol", [], ""],
		["pistol", ["suppressor"], "Suppressor"],
		["pistol", ["barrel_long"], "LongBarrel"],
		["pistol", ["barrel_long", "suppressor"], "Suppressor"],
		["pistol", ["barrel_long", "compensator"], "Compensator"],
		["magnum", ["compensator"], "Compensator"],
		["smg", ["barrel_long", "suppressor"], "Suppressor"],
		["ak47", ["barrel_long", "compensator"], "Compensator"],
		["m4a1", ["barrel_long"], "LongBarrel"],
		["m4a1", ["compensator"], "Compensator"],
		["m4a1", ["suppressor"], "Suppressor"],
		["hunting_rifle", ["barrel_long", "suppressor"], "Suppressor"],
		["shotgun", ["choke_full"], "ChokeTube"],
		["sawed_off", ["choke_full"], "ChokeTube"],
		["shotgun", ["duckbill"], "Duckbill"],
		["flamethrower", ["flame_focus"], "FocusNozzle"],
		["flamethrower", ["flame_wide"], "FanNozzle"],
		["pistol", [], ""], # Removing attachments restores the original muzzle.
	]
	var original := Vector3.ZERO
	for spec in cases:
		var id: String = spec[0]
		state.grant_weapon(id)
		state.equip_weapon(id)
		var parts := {}
		for part in spec[1]: parts[gameplay.CUSTOM.PARTS[part].slot] = part
		gameplay.customization = {id: {"owned_parts":spec[1], "parts":parts}}
		gameplay.visual_id = "@rebuild"
		gameplay._update_weapon_pose(1.0 / 60.0)
		gameplay._update_visual()
		var label := id + " " + str(spec[1])
		var expected: Vector3 = gameplay._muzzle_flash.position
		if spec[2] != "":
			var part := gameplay.gun.get_node_or_null(spec[2]) as MeshInstance3D
			check(part != null, label + " has real attachment geometry")
			if part == null: continue
			var bounds: AABB = part.transform * part.get_aabb()
			expected.z = bounds.position.z
			check(absf(gameplay._muzzle_flash.position.z - expected.z) < .006, label + " flash starts at physical mouth")
			if id == "m4a1":
				# The authored barrel ends at -.390; the original effect anchor is
				# -.400. The assembly must occupy that interval, not float ahead.
				check(_connected_m4_barrel(gameplay.gun, gameplay._muzzle_flash), label + " attachment meets physical barrel")
		else:
			if original == Vector3.ZERO: original = expected
			check(expected.is_equal_approx(original), label + " base muzzle restored")
		check(gameplay._muzzle_light.position.is_equal_approx(gameplay._muzzle_flash.position), label + " light follows flash")
		if id == "flamethrower":
			check(gameplay._muzzle_world_position().distance_to(gameplay.gun.to_global(expected)) < .006, label + " flame origin follows physical nozzle")
			continue
		var tracer_index: int = gameplay.effects._next_tracer
		gameplay.cooldown = 0.0
		gameplay.reload_timer = 0.0
		check(gameplay.fire_at(Vector3(0, 1, -10)), label + " fires through real combat")
		var actual: Dictionary = gameplay.effects._tracer_state[tracer_index]
		check(actual.has("from") and actual.from.distance_to(gameplay.gun.to_global(expected)) < .006, label + " tracer leaves physical mouth")
		await process_frame
	scene.queue_free()
	for i in 4: await process_frame
	print("VIDEO_MUZZLE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _connected_m4_barrel(gun: Node3D, flash: MeshInstance3D) -> bool:
	for z in [-.391, -.395, -.399]:
		var covered := false
		for child in gun.get_children():
			if not child is MeshInstance3D or child == flash: continue
			var bounds: AABB = child.transform * child.get_aabb()
			if bounds.has_point(Vector3(0, .02, z)): covered = true; break
		if not covered: return false
	return true
