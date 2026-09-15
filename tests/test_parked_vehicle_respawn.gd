extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	root.get_node("PresentationBudget").set_process(false)
	var parent := Node2D.new()
	parent.position = Vector2(2000,2000)
	stage.add_child(parent)
	var original := ModernTrafficFactory.spawn_parked_vehicle(parent,"BayCar",Vector2(60,80),PI*.5,"union_sedan",0,Color("427351"))
	original.set_physics_process(false)
	var slot: Node = parent.get_node("BayCarSpawn")
	slot.set_process(false)
	var origin := original.global_position
	slot.tick(180)
	check(slot.vehicle == original,"occupied original bay never duplicates a car")
	original.global_position += Vector2(1000,0)
	original.is_driven_by_player = true
	slot.tick(119)
	check(slot.vehicle == original,"vacancy waits for its configured respawn time")
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 2
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24,24)
	collision.shape = shape
	blocker.add_child(collision)
	stage.add_child(blocker)
	blocker.global_position = origin
	await physics_frame
	await physics_frame
	slot.tick(2)
	check(slot.vehicle == original,"a person or solid occupying the vacancy delays respawn")
	blocker.queue_free()
	await physics_frame
	await physics_frame
	slot.tick(.5)
	var replacement: Node2D = slot.vehicle
	check(replacement != original and is_instance_valid(original),"replacement preserves the stolen car still in use")
	check(replacement.global_position.distance_to(origin)<.01 and is_equal_approx(replacement.global_rotation,PI*.5),"replacement uses original position and orientation under a translated parent")
	check(parent.get_node("BayCar") == replacement,"the authored spawn name belongs to the replacement")
	slot.tick(400)
	check(slot.vehicle == replacement and slot.stock.size() == 1,"subsequent ticks do not duplicate the replacement or spawn controller")
	print("PARKED_RESPAWN failures=",failures)
	stage.queue_free()
	await process_frame
	quit(1 if failures else 0)
