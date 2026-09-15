extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
class Observer extends CharacterBody2D:
	var is_dead := false
	var is_recovering := false
	var is_control_disabled := false
	var is_in_dialogue := false

func run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := Observer.new()
	world.add_child(player)
	player.add_to_group("player")
	var skier := preload("res://world/mountain_pass/MountainSkier.gd").new()
	skier.configure(PackedVector2Array([Vector2.ZERO,Vector2(60,0),Vector2(200,0)]),175,Color("4c7890"),0,true)
	world.add_child(skier)
	skier.set_physics_process(false)
	skier.position = Vector2(55,0)
	skier.velocity = Vector2(175,0)
	skier._physics_process(.016)
	check(skier.fallen_time==0 and skier.target_index==2,"Passing a checkpoint never forces an unprompted fall")
	skier.model.speed_factor = .8
	skier.model._process(.1)
	for i in 2:
		var foot: Vector3 = skier.model.pose_root.transform*skier.model.limbs[i*2].transform*skier.model.knees[i].transform*Vector3(0,-.429,.04)
		check(absf(foot.y-.065)<.002 and absf(foot.z)<.002,"Skier soles remain on their bindings while knees flex")
		check(skier.model.elbows[i].get_node("SkiPole").get_parent()==skier.model.elbows[i],"Pole grip follows the articulated hand")
	skier.target_index = 3
	skier.position = Vector2(120,0)
	skier._physics_process(.1)
	for i in 35: skier._physics_process(.1)
	check(skier.position.distance_to(Vector2(120,0))<.01 and skier.presentation_sprite.modulate.a==1.0,"Visible skier waits at the base without fading or teleporting")
	var barrier := StaticBody2D.new()
	barrier.collision_layer = 1
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(5,100)
	barrier.add_child(shape)
	barrier.position = Vector2(100,0)
	world.add_child(barrier)
	skier.wait_time = 0
	skier.target_index = 2
	skier.position = Vector2(85,0)
	skier.velocity = Vector2(220,0)
	for i in 8:
		await physics_frame
		skier._physics_process(.016)
	check(skier.fallen_time>0,"Real impact uses incoming speed even after collision removes velocity")
	for i in 125:
		await physics_frame
		skier._physics_process(.016)
	check(skier.fallen_time<=0 and not skier.model.fallen,"Recoverable impact returns to skiing")
	skier.queue_free()
	barrier.queue_free()
	await process_frame
	var first := preload("res://world/mountain_pass/WinterResident.gd").new()
	var second := preload("res://world/mountain_pass/WinterResident.gd").new()
	first.is_stationary = true
	second.is_stationary = true
	world.add_child(first)
	world.add_child(second)
	first.set_physics_process(false)
	second.set_physics_process(false)
	first.position = Vector2(25,0)
	second.position = Vector2(40,0)
	await physics_frame
	check(first._can_interact(player) and not second._can_interact(player),"Only nearest visible resident offers conversation")
	first._interact_talk(player)
	second._interact_talk(player)
	check(first.dialogue_index==1 and second.dialogue_index==0,"One input cannot open multiple conversations")
	await process_frame
	player.hide()
	check(not first._can_interact(player),"Hidden driver cannot talk from inside the car")
	player.show()
	player.is_control_disabled = true
	check(not first._can_interact(player),"Conversation respects cutscene and transport controls")
	player.is_control_disabled = false
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var blocker := CollisionShape2D.new()
	blocker.shape = RectangleShape2D.new()
	blocker.shape.size = Vector2(3,100)
	wall.add_child(blocker)
	world.add_child(wall)
	wall.position.x = 12
	await physics_frame
	await physics_frame
	check(not first._can_interact(player),"Solid wall blocks conversation through furniture or buildings")
	world.queue_free()
	await process_frame
	print("PEOPLE_MOTION failures=",failures)
	quit(1 if failures else 0)
