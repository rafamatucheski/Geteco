extends SceneTree
const OUTPUT := "D:/geteco/artifacts/collision-fix-0911/"

class Street extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-1000,-1000,3000,3000),Color("25313b"))
		for x in range(-300,1500,80): draw_rect(Rect2(x,300,35,3),Color("dab74f"))
		draw_rect(Rect2(-1000,110,3000,65),Color("8c918b"))

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var world := Street.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	root.get_node("NPCMedicalCare").set_process(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(450,250)
	camera.zoom = Vector2.ONE * 2.0
	camera.make_current()
	var factory = preload("res://emergency/ModernTrafficFactory.gd")
	var bike = factory.spawn_parked_vehicle(world,"Bike",Vector2(295,255),0,"bike_cruiser",0,Color("d97925"))
	bike.ensure_presentation()
	bike.set_process(false)
	bike.set_physics_process(false)
	var people: Array[AnimatedPedestrian3D] = []
	for i in 7:
		var actor := AnimatedPedestrian3D.new()
		actor.archetype_override = i
		world.add_child(actor)
		actor.position = Vector2(365+i*28,150)
		actor.ensure_presentation()
		actor.set_physics_process(false)
		people.append(actor)
	for i in 8: await process_frame
	for actor in people: actor._show_custom_bubble("CUIDADO!",Color("d7ab50"))
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"speech-crowd.png")
	var victim := AnimatedPedestrian3D.new()
	world.add_child(victim)
	victim.position = Vector2(360,255)
	victim.ensure_presentation()
	victim.set_physics_process(false)
	for i in 8: await process_frame
	victim.get_run_over(Vector2(280,0))
	for i in 6:
		await physics_frame
		victim._physics_process(1.0/60.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"body-impact.png")
	for i in 85:
		await physics_frame
		victim._physics_process(1.0/60.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"body-ground-blood.png")
	print("COLLISION_FEEDBACK_CAPTURE complete")
	world.queue_free()
	await process_frame
	quit()
