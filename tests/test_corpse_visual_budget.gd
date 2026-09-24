extends SceneTree

const BLOOD := preload("res://guns/combat/GroundBlood.gd")
var failures := 0
var actors: Array[CharacterBody2D] = []
var stains: Array[Node2D] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	for index in 6:
		var actor := CharacterBody2D.new()
		actor.name = "CorpseBudgetActor%d" % index
		actor.position = Vector2(index * 30, 40)
		actor.set_meta("is_dead", true)
		world.add_child(actor)
		actors.append(actor)
		stains.append(BLOOD.spawn(actor, true))
		await process_frame
	check(stains[0].modulate.a < 1.0, "The oldest blood begins fading when the sixth corpse enters")
	check(actors[0].modulate.a < 1.0, "The oldest corpse begins fading with its blood")
	for i in 40: await process_frame
	check(not is_instance_valid(actors[0]), "The oldest corpse is removed after fade-out")
	check(not is_instance_valid(stains[0]), "The oldest blood is removed after fade-out")
	var living_count := 0
	for actor in actors:
		if is_instance_valid(actor): living_count += 1
	check(living_count == 5, "The visual budget retains exactly five corpse actors")
	print("CORPSE_VISUAL_BUDGET failures=%d remaining=%d" % [failures, living_count])
	quit(0 if failures == 0 else 1)
