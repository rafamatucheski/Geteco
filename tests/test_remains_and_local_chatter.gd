extends SceneTree
var failures := 0
class Bystander extends Node2D:
	var is_dead := false
	var is_incapacitated := false
	var is_scared := false
class QuietSoundscape extends "res://world/harbor/HarborSoundscape.gd":
	func _ready() -> void: set_process(false)
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var sound := QuietSoundscape.new()
	world.add_child(sound)
	check(sound.nearby_conversation_weight(Vector2.ZERO) == 0, "Empty alley has no crowd chatter")
	var people: Array[Node2D] = []
	for i in 4:
		var person := Bystander.new()
		world.add_child(person)
		person.add_to_group("pedestrian")
		person.position = Vector2(45, i * 3)
		people.append(person)
		if i == 0: check(sound.nearby_conversation_weight(Vector2.ZERO) == 0, "One passerby is not a crowd")
	check(sound.nearby_conversation_weight(Vector2.ZERO) > 0.95, "Nearby group supports conversations")
	for person in people: person.is_scared = true
	check(sound.nearby_conversation_weight(Vector2.ZERO) == 0, "Panicked people do not keep casually chatting")
	for person in people: person.is_scared = false
	check(sound.nearby_conversation_weight(Vector2(500, 0)) == 0, "Distant group is silent")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(10, 100)
	wall.position = Vector2(22, 0)
	wall.add_child(shape)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	check(sound.nearby_conversation_weight(Vector2.ZERO) == 0, "Wall blocks conversations on next street")
	var abandoned_actor := Bystander.new()
	world.add_child(abandoned_actor)
	abandoned_actor.is_dead = true
	var abandoned := preload("res://guns/combat/ExplosionRemains.gd").new()
	world.add_child(abandoned)
	abandoned.set_process(false)
	abandoned._source_actor = abandoned_actor
	abandoned.set_meta("medical_pending", true)
	abandoned.modulate.a = 0.3
	abandoned._process(1)
	check(is_equal_approx(abandoned.modulate.a, 0.3), "Lifetime never reverses an earlier corpse-budget fade")
	abandoned._process(94)
	await process_frame
	check(not is_instance_valid(abandoned) and not is_instance_valid(abandoned_actor), "Cleanup also works without a coroner service")
	var actor := Bystander.new()
	world.add_child(actor)
	actor.set_meta("medical_identity", "test_expiring_remains")
	actor.is_dead = true
	var care := preload("res://emergency/CoronerCare.gd").new()
	care.name = "CoronerCare"
	root.add_child(care)
	care.set_process(false)
	care.register_death(actor)
	var remains := preload("res://guns/combat/ExplosionRemains.gd").new()
	world.add_child(remains)
	remains.set_process(false)
	remains._source_actor = actor
	remains.set_meta("coroner_identity", "test_expiring_remains")
	remains.set_meta("medical_pending", true)
	actor.set_meta("explosion_remains", remains)
	care.records()["test_expiring_remains"].fragments = [{"parts": ["head"], "x": 0, "y": 0}]
	remains._process(90)
	check(remains.modulate.a == 1, "Remains stay opaque until lifetime")
	remains._process(2.5)
	check(is_equal_approx(remains.modulate.a, 0.5), "Pending remains fade gradually")
	remains._process(2.5)
	check(remains.is_queued_for_deletion(), "Pending dispatch cannot prevent unloading")
	check(care.records()["test_expiring_remains"].phase == "unrecovered", "Expiry persists across saves")
	check(care.records()["test_expiring_remains"].fragments.is_empty(), "Expired fragments are not restored from save")
	await process_frame
	check(not is_instance_valid(remains), "Remains node freed")
	check(not is_instance_valid(actor), "Hidden source rig is unloaded with its fragments")
	world.queue_free()
	await process_frame
	print("REMAINS_LOCAL_CHATTER failures=", failures)
	quit(1 if failures else 0)
