extends SceneTree
class State extends RefCounted:
	var safe := false
	func weapons_allowed() -> bool: return not safe
class Player extends CharacterBody3D:
	var input_locked := false
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	var gameplay := preload("res://gameplay/Gameplay.gd").new()
	var state := State.new()
	var player := Player.new()
	gameplay.state = state
	gameplay.player = player
	gameplay.armor = 80
	gameplay.crime_points = 17
	var deaths := [0]
	gameplay.player_died.connect(func(): deaths[0] += 1)
	gameplay.damage_environment(10)
	check(gameplay.health == 90 and gameplay.armor == 80, "cold bypasses ballistic armor")
	check(gameplay.crime_points == 17, "environment creates no crime")
	gameplay.damage_player(20)
	check(gameplay.health == 83 and gameplay.armor == 67, "ordinary damage retains original absorption")
	state.safe = true
	gameplay.damage_environment(100)
	check(gameplay.health == 83 and gameplay.armor == 67, "garage protection preserved")
	state.safe = false
	for amount in [NAN, INF, -1.0, 0.0]: gameplay.damage_environment(amount)
	check(gameplay.health == 83, "invalid environmental damage ignored")
	gameplay.damage_environment(100)
	check(gameplay.health == 0 and gameplay.armor == 67 and player.input_locked, "environment death uses standard health and control lifecycle")
	check(deaths[0] == 1, "standard rescue/death signal emitted")
	gameplay.damage_environment(100)
	check(deaths[0] == 1 and gameplay.crime_points == 17, "no duplicate death or crime")
	gameplay.free()
	player.free()
	print("ENVIRONMENT_DAMAGE ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
