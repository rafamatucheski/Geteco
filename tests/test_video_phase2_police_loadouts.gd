extends SceneTree
## Real dispatch spawn, model and projectile integration. The dispatch identity
## determines equipment even when wanted stars change before disembarking.
## Headless proves these contracts, not appearance or performance in Main.

const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
var checks := 0
var failures: Array[String] = []
var cases_completed := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	create_timer(45.0).timeout.connect(func(): print("TIMEOUT VIDEO_PHASE2_POLICE"); quit(2))
	var cases := [
		{"level": 1, "variant": "patrol", "current": 6, "tier": 0, "weapon": "pistol"},
		{"level": 2, "variant": "patrol", "current": 3, "tier": 0, "weapon": "pistol"},
		{"level": 3, "variant": "interceptor", "current": 1, "tier": 1, "weapon": "smg"},
		{"level": 4, "variant": "tactical", "current": 6, "tier": 2, "weapon": "m4a1"},
		{"level": 5, "variant": "tactical", "current": 2, "tier": 3, "weapon": "m4a1"},
		{"level": 6, "variant": "tactical", "current": 2, "tier": 4, "weapon": "m4a1"},
		{"level": 6, "variant": "patrol", "current": 6, "tier": 0, "weapon": "pistol"},
	]
	for expected in cases: await check_response(expected)
	await check_stolen_patrol()
	check(cases_completed == cases.size() + 1, "all integration scenarios completed")
	print("VIDEO_PHASE2_POLICE checks=%d cases=%d failures=%s" % [checks, cases_completed, failures])
	quit(0 if failures.is_empty() else 1)

func check_response(expected: Dictionary) -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(0, .03, -8))
	var game: Node3D = bundle.gameplay
	var dispatch: Node3D = bundle.controller
	game.set_physics_process(false)
	dispatch.set_physics_process(false)
	game.stars = int(expected.current)
	game.last_known = bundle.player.global_position
	game.last_known_valid = true
	var car: CharacterBody3D = dispatch._create_vehicle("police", Vector3(20, .03, 0), 0.0)
	car.set_physics_process(false)
	var unit: RefCounted = dispatch._make_unit("police", car, 8.0, 60.0)
	unit.level = expected.level
	unit.variant = expected.variant
	var officer: CharacterBody3D = dispatch.spawn_officer(unit, Vector3(22, .03, 0), 1.0)
	unit.officers.append(officer)
	officer.set_physics_process(false)
	await frames(3)
	var label := "%d-star %s, current=%d" % [expected.level, expected.variant, expected.current]
	check(officer.mode == "disembark", label + " uses actual disembark lifecycle")
	check(officer.tier == expected.tier and officer.visual.tier == expected.tier, label + " preserves team tier")
	check(officer.weapon_id == expected.weapon and officer.visual.weapon_id == expected.weapon, label + " matches actor and visible weapon")
	check(is_instance_valid(officer.visual.weapon) and officer.visual.weapon.is_visible_in_tree(), label + " has visible weapon geometry")
	check(officer.magazine == int(CATALOG.get_weapon(expected.weapon).magazine_size), label + " loads correct magazine")
	# Aim and fire in a clear lane. No fake police_shoot/model/weapon integration.
	officer.global_position = Vector3(0, .03, 0)
	officer.visual.rotation.y = 0.0
	officer.visual.update_pose(1.0, true, false, 0.0, 0.0)
	await frames(2)
	for voice in game._audio_pool:
		voice.stop()
		voice.stream = null
	game._police_rounds.clear()
	var magazine_before: int = officer.magazine
	check(officer._try_fire() and game._police_rounds.size() == 1, label + " starts actual projectile")
	if game._police_rounds.size() == 1:
		var round: Dictionary = game._police_rounds[0]
		check(round.data == CATALOG.get_weapon(expected.weapon) and round.point.is_equal_approx(officer.visual.muzzle_position()), label + " projectile uses equipped weapon and visible muzzle")
		check(is_equal_approx(float(round.damage), 6.0 if int(expected.tier) < 2 else 8.0), label + " preserves response damage")
	check(officer.magazine == magazine_before - 1, label + " consumes one cartridge")
	var sound_matches := false
	for voice in game._audio_pool:
		if voice.stream != null and voice.stream.resource_path.get_file().begins_with(str(expected.weapon) + "_"): sound_matches = true
	check(sound_matches, label + " shot audio matches equipped weapon")
	game._police_rounds.clear()
	officer.burst_pause = 0.0
	officer.cooldown = 0.0
	officer.magazine = 1
	officer._try_fire()
	check(officer.magazine == 0 and is_equal_approx(officer.reload_timer, maxf(AUDIO.MIN_RELOAD, AUDIO.reload_seconds(expected.weapon))), label + " reload follows equipped weapon")
	game._police_rounds.clear()
	bundle.state.safe = true
	game.police_shoot(officer, 8.0, expected.weapon)
	check(game._police_rounds.is_empty() and game.health == 100.0, label + " no projectile in weapon-free state")
	unit.finish("test_cleanup")
	dispatch.units.erase(unit)
	unit = null
	await frames(2)
	KIT.teardown(bundle)
	bundle.clear()
	await frames(2)
	cases_completed += 1

func check_stolen_patrol() -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(0, .03, -8))
	var game: Node3D = bundle.gameplay
	var dispatch: Node3D = bundle.controller
	game.set_physics_process(false)
	dispatch.set_physics_process(false)
	game.stars = 6
	game.last_known = bundle.player.global_position
	game.last_known_valid = true
	var car: CharacterBody3D = dispatch._create_vehicle("police", Vector3(0, .03, 0), 0.0)
	car.set_physics_process(false)
	var unit: RefCounted = dispatch._make_unit("police", car, 8.0, 60.0)
	unit.level = 1
	unit.variant = "patrol"
	await frames(3)
	check(dispatch.vehicle_stolen(car, -1), "stolen patrol admits two real exit points")
	check(unit.finished and game.police.size() == 2, "stolen patrol transfers real crew to pursuit lifecycle")
	for officer in game.police:
		officer.set_physics_process(false)
		check(officer.tier == 0 and officer.weapon_id == "pistol" and officer.visual.weapon_id == "pistol", "stolen regular crew retains pistol despite six stars")
		check(officer.mode == "disembark", "stolen regular crew starts door transition")
	# Complete one door transition with actual CharacterBody movement.
	if game.police.size() == 2:
		var officer: CharacterBody3D = game.police[0]
		for frame in 150:
			await physics_frame
			officer._disembark(1.0 / 60.0)
			if officer.mode == "combat": break
		check(officer.mode == "combat" and officer.is_on_floor(), "regular officer completes disembark on physical ground")
		check(officer.weapon_id == "pistol" and officer.visual.weapon_id == "pistol", "regular pistol survives completed disembark")
	dispatch.units.erase(unit)
	unit = null
	KIT.teardown(bundle)
	bundle.clear()
	await frames(2)
	cases_completed += 1
