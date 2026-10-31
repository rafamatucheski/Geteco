extends "res://tests/test_gameplay.gd"
## Reproduz as referências liberadas e a apresentação de veículo faltando em session-000.
const CEMETERY = preload("res://gameplay/urban_v1/CemeteryOperations.gd")

class Resident extends CharacterBody3D:
	var dead := false
	var frightened := false

class VehicleTarget extends Target:
	var damage_look: Node

class IgnitionLook extends Node:
	var ignitions := 0
	func ignite(_source: Node) -> void: ignitions += 1

func run() -> void:
	await _cemetery_lifecycle()
	await _flame_lifecycle()
	print("SESSION_CEMETERY_FIRE_LIFECYCLE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _cemetery_lifecycle() -> void:
	var cemetery = CEMETERY.new()
	root.add_child(cemetery)
	cemetery.set_process(false)
	var player := CharacterBody3D.new()
	root.add_child(player)
	cemetery.session = {"world": {"driving": {"occupied": false}, "player": player}, "state": {"place_id": "cemetery_keeper"}}
	cemetery.active = true
	var keeper := Resident.new()
	root.add_child(keeper)
	cemetery.keeper = keeper
	check(not cemetery.nearest_action().is_empty(), "Living keeper offers dialogue")
	keeper.dead = true
	check(cemetery.nearest_action().is_empty(), "Dead keeper offers no dialogue")
	keeper.dead = false
	keeper.queue_free()
	check(cemetery.nearest_action().is_empty(), "Keeper queued for removal offers no dialogue")
	await process_frame
	check(cemetery.nearest_action().is_empty(), "Freed keeper offers no dialogue without argument error")
	var guest := Resident.new()
	root.add_child(guest)
	cemetery.mortician = guest
	cemetery.mourners.append(guest)
	cemetery.bodies.append(guest)
	guest.free()
	cemetery._complete_trip()
	check(cemetery.mourners.is_empty() and cemetery.mortician == null, "Freed funeral participants release cleanly")
	cemetery._deactivate()
	check(cemetery.keeper == null and cemetery.bodies.is_empty(), "Deactivation clears stale keeper and bodies")
	cemetery.active = false
	var snapshot: Dictionary = cemetery.snapshot()
	var storyteller := Resident.new()
	root.add_child(storyteller)
	cemetery.storyteller = storyteller
	storyteller.free()
	check(cemetery.restore_snapshot(snapshot), "Restore tolerates previously freed storyteller")
	var departing := Resident.new()
	root.add_child(departing)
	cemetery.keeper = departing
	departing.free()
	cemetery.free()
	player.free()
	await process_frame

func _flame_lifecycle() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	scene.add_child(player)
	player.set_physics_process(false)
	var state := CombatState.new()
	state.equipped_weapon = "flamethrower"
	var gameplay := GAMEPLAY.new()
	gameplay.configure(scene, player, null, state)
	scene.add_child(gameplay)
	gameplay.set_physics_process(false)
	var target := VehicleTarget.new()
	target.set_meta("gameplay_role", "vehicle")
	scene.add_child(target)
	target.position = Vector3(0, 0, -3)
	# Largo o bastante para a dispersão autoral da arma; os raios ainda usam física real.
	target.get_child(0).shape.size = Vector3(5, 3, 1)
	await physics_frame
	await physics_frame
	for kind in ["missing", "freed", "valid"]:
		if kind != "missing":
			target.damage_look = IgnitionLook.new()
			target.add_child(target.damage_look)
			if kind == "freed": target.damage_look.free()
		gameplay.cooldown = 0.0
		gameplay._flame_hit_at.clear()
		var previous_health: float = target.health
		check(gameplay.fire_at(target.position + Vector3.UP), "Flame shot completes with " + kind + " vehicle look")
		check(target.health < previous_health, "Flame still damages vehicle with " + kind + " look")
		check(not gameplay._in_pellet_volley, "Shot clears volley state with " + kind + " look")
		if kind == "valid": check(target.damage_look.ignitions == 1, "Valid vehicle presentation ignites")
	state.safe = true
	var ammunition: Dictionary = state.get_ammo("flamethrower").duplicate()
	gameplay.cooldown = 0.0
	check(not gameplay.fire_at(target.position), "Safe garage still blocks flame")
	check(state.get_ammo("flamethrower") == ammunition, "Safe garage preserves flame ammo")
	scene.free()
	await process_frame
