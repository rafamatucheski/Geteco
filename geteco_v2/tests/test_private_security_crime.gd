extends SceneTree
class State extends RefCounted:
	func weapons_allowed() -> bool: return true
class Target extends Node3D:
	var health := 100.0
	func receive_damage(amount: float, _source: Node): health -= amount
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var combat = preload("res://gameplay/Gameplay.gd").new()
	var player := CharacterBody3D.new()
	root.add_child(player)
	combat.player = player
	combat.state = State.new()
	var guard := Target.new()
	root.add_child(guard)
	guard.set_meta("gameplay_role","private_security")
	guard.set_meta("local_security",true)
	combat._damage(guard,10,player)
	check(guard.health == 90,"Private guard receives actual damage")
	check(combat.crime_points == 0,"Local alarm owns private security crime")
	guard.remove_meta("local_security")
	combat._damage(guard,10,player)
	check(combat.crime_points == 12,"Ordinary assault remains reported")
	guard.set_meta("gameplay_role","police")
	combat._damage(guard,10,player)
	check(combat.crime_points == 30,"Public police assault retains original severity")
	combat.free()
	guard.free()
	player.free()
	print("PRIVATE_SECURITY_CRIME 4 checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
func check(value: bool,label: String) -> void:
	if not value: failures.append(label); push_error(label)
