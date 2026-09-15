extends SceneTree
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := Node2D.new()
	player.add_to_group("player")
	world.add_child(player)
	var actor = preload("res://world/mountain_pass/WinterResident.gd").new()
	world.add_child(actor)
	var partner = preload("res://world/mountain_pass/WinterResident.gd").new()
	partner.position = Vector2(50,0)
	world.add_child(partner)
	actor.set_physics_process(false)
	partner.set_physics_process(false)
	await physics_frame
	actor.routine_cycle = 2
	actor._choose_activity()
	check(actor.activity == "talk" and partner.conversation_partner == actor,"conversation pairs real nearby residents")
	actor._physics_process(.1)
	check(actor.speech.text.is_empty() and not actor.speech_panel.visible,"ambient conversations have no text")
	actor.model.activity = "drink"
	actor.model.walking = false
	actor.model._process(.2)
	check(actor.model.mug.visible and not actor.model.axe.visible,"hot drink uses visible mug")
	if "--visual" in OS.get_cmdline_user_args():
		actor.model._process(1.0)
		actor.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		actor.viewport.get_texture().get_image().save_png("D:/geteco/mountain-routine-drink.png")
	actor.hear_gunfire(Vector2(100,0),Vector2(120,0))
	actor._physics_process(.1)
	check(actor.model.activity == "idle" and not actor.model.mug.visible,"danger interrupts gestures and hides drink")
	var logger = preload("res://world/mountain_pass/WinterResident.gd").new()
	logger.role = "logger"
	logger.position = Vector2(180,0)
	world.add_child(logger)
	logger.set_physics_process(false)
	await process_frame
	logger._choose_activity()
	logger._physics_process(.1)
	check(logger.activity == "work" and logger.model.axe.visible,"logger works at home station with axe")
	check(world.get_node_or_null("FirewoodWorkstation") != null,"physical wood block remains in world")
	logger.activity = "walk"
	logger.destination = logger.home
	logger.activity_left = 10.0
	logger._physics_process(.1)
	check(logger.activity == "work","return to wood block resumes working")
	if "--visual" in OS.get_cmdline_user_args():
		logger.model._process(1.0)
		logger.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		logger.viewport.get_texture().get_image().save_png("D:/geteco/mountain-routine-work.png")
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
