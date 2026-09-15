extends SceneTree
var failures: Array[String] = []
var world: Node2D
var medic: CharacterBody2D
var post: StaticBody2D
var depth: Node
var post_alpha: Image
var post_canvas_inverse := Transform2D.IDENTITY
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func picture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Post depth requires a real renderer")
		quit(2)
		return
	create_timer(35).timeout.connect(func(): quit(2))
	root.size = Vector2i(640,480)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("384552"))
	root.get_node("NPCMedicalCare").set_process(false)
	root.get_node("WantedManager").set_process(false)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE*4
	camera.position = Vector2(0,-15)
	post = preload("res://geodata/roads/traffic/FixedTrafficSignal.gd").new()
	post.z_index = 32
	world.add_child(post)
	post.ensure_presentation()
	medic = preload("res://Paramedic.tscn").instantiate()
	world.add_child(medic)
	medic.set_physics_process(false)
	medic.model_root.rotation.y = 0
	var sequence := preload("res://world/shared/emergency/MedicalRescueSequence.gd").new()
	world.add_child(sequence)
	sequence.set_physics_process(false)
	sequence.crew = [medic]
	depth = preload("res://world/shared/emergency/MedicalOutdoorDepth.gd").new()
	depth.sequence = sequence
	sequence.add_child(depth)
	await create_timer(.3).timeout
	for front in [false,true]:
		medic.position = Vector2(0,14 if front else -20)
		medic.reset_physics_interpolation()
		medic.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
		await physics_frame
		await physics_frame
		check(not medic.test_move(medic.global_transform,Vector2.ZERO,null,.01,true),"Depth pose is physically clear: "+str(front))
		post.show()
		medic.show()
		depth.set_process(true)
		await process_frame
		var combined := await picture()
		depth.set_process(false)
		for entry in depth.layers.values(): entry.overlay.hide()
		post.hide()
		var actor_only := await picture()
		medic.hide()
		var empty := await picture()
		post.show()
		var post_only := await picture()
		post_alpha = post.sprite.texture.get_image()
		post_canvas_inverse = post.sprite.get_global_transform_with_canvas().affine_inverse()
		actor_only.save_png("D:/geteco/artifacts/rescue-0913/depth-actor-"+str(front)+".png")
		post_only.save_png("D:/geteco/artifacts/rescue-0913/depth-post-"+str(front)+".png")
		empty.save_png("D:/geteco/artifacts/rescue-0913/depth-empty-"+str(front)+".png")
		var overlap := 0
		var correct := 0
		for y in combined.get_height():
			for x in combined.get_width():
				var a := actor_only.get_pixel(x,y)
				var p := post_only.get_pixel(x,y)
				var b := empty.get_pixel(x,y)
				if difference(a,b)<.15 or difference(a,p)<.15 or not opaque_post_pixel(x,y): continue
				overlap += 1
				if difference(combined.get_pixel(x,y),a if front else p)<.08: correct += 1
		check(overlap>12,"Positive pixel overlap control: "+str(front)+" pixels="+str(overlap))
		check(correct > overlap*.9,"Correct independent post occlusion: "+str(front)+" correct="+str(correct)+"/"+str(overlap))
		combined.save_png("D:/geteco/artifacts/rescue-0913/depth-"+("front" if front else "behind")+".png")
	medic.hide()
	sequence.crew = []
	var cot := preload("res://world/shared/emergency/MedicalStretcher.gd").new()
	world.add_child(cot)
	sequence.stretcher = cot
	for front in [false,true]:
		cot.position = Vector2(0,14 if front else -14)
		cot.reset_physics_interpolation()
		post.show()
		cot.show()
		depth.set_process(true)
		await physics_frame
		await physics_frame
		check(not cot.test_move(cot.global_transform,Vector2.ZERO,null,.01,true),"Cot depth pose clears the foundation: "+str(front))
		var combined := await picture()
		depth.set_process(false)
		for entry in depth.layers.values(): entry.overlay.hide()
		post.hide()
		var actor_only := await picture()
		cot.hide()
		var empty := await picture()
		post.show()
		var post_only := await picture()
		post_alpha = post.sprite.texture.get_image()
		post_canvas_inverse = post.sprite.get_global_transform_with_canvas().affine_inverse()
		var overlap := 0
		var correct := 0
		var visible_pixels := 0
		for y in combined.get_height():
			for x in combined.get_width():
				var a := actor_only.get_pixel(x,y)
				var b := empty.get_pixel(x,y)
				var p := post_only.get_pixel(x,y)
				if difference(a,b)>.15 and difference(combined.get_pixel(x,y),a)<.08: visible_pixels += 1
				if difference(a,b)<.15 or difference(a,p)<.15 or not opaque_post_pixel(x,y): continue
				overlap += 1
				if difference(combined.get_pixel(x,y),a if front else p)<.08: correct += 1
		if not front: check(overlap>12 and correct>overlap*.9,"Post correctly covers the cot behind it, with positive overlap control %d/%d"%[correct,overlap])
		else: check(visible_pixels>100,"Cot in front remains visible with its wheels on the clear floor")
		combined.save_png("D:/geteco/artifacts/rescue-0913/depth-cot-"+str(front)+".png")
	print("MEDICAL_POST_DEPTH failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
func difference(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func opaque_post_pixel(x: int,y: int) -> bool:
	# Transparent silhouette edges blend the actor with the post, so they
	# cannot be expected to equal the post-only image over an empty background.
	# Require all bilinear taps to be opaque for this exact-color assertion.
	var pixel := post_canvas_inverse*Vector2(x+.5,y+.5)+Vector2(post_alpha.get_size())*.5-Vector2.ONE*.5
	var p := Vector2i(floori(pixel.x),floori(pixel.y))
	if p.x<0 or p.y<0 or p.x+1>=post_alpha.get_width() or p.y+1>=post_alpha.get_height(): return false
	for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		if post_alpha.get_pixelv(p+offset).a < .995: return false
	return true
