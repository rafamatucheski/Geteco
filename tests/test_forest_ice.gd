extends SceneTree
const TREE = preload("res://world/mountain_pass/MountainPine3D.gd")
const MOTION = preload("res://VehicleMotionSafety.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	var world := Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	camera.position=Vector2(0,-25)
	camera.zoom=Vector2.ONE*4
	world.add_child(camera)
	var floor := Polygon2D.new()
	floor.polygon=PackedVector2Array([Vector2(-1000,-500),Vector2(1000,-500),Vector2(1000,500),Vector2(-1000,500)])
	world.add_child(floor)
	preload("res://world/mountain_pass/ForestGroundBlend.gd").polygon(floor,"forest",0)
	var trees := []
	for row in 2:
		for variant in 8:
			var tree = TREE.new()
			tree.variant_seed=variant
			tree.is_snowy=row==1
			tree.position=Vector2(variant*80-280,row*170-110)
			world.add_child(tree)
			trees.append(tree)
	if DisplayServer.get_name()!="headless":
		camera.zoom=Vector2.ONE*1.7
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/forest-ground-0913/tree-varieties.png")
	var tree = trees[8]
	# A real production vehicle drives through the native motion/collision pipeline.
	var factory = load("res://world/shared/emergency/ModernTrafficFactory.gd")
	var car = factory.spawn_parked_vehicle(world,"IceTestCar",tree.position+Vector2(-90,3),0,"sedan_classic",0,Color("465861"))
	car.set_process(false)
	car.set_physics_process(false)
	car.ensure_presentation()
	camera.position=tree.position+Vector2(-25,-30)
	camera.zoom=Vector2.ONE*5
	await physics_frame
	await physics_frame
	var recording := "--motion" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	var video_frame := 0
	for frame in 80:
		await physics_frame
		car.velocity=Vector2(180,0)
		MOTION.move(car)
		if recording:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/forest-ground-0913/contact-frame%03d.png"%video_frame)
			video_frame+=1
		if not get_nodes_in_group("tree_ice_burst").is_empty(): break
	car.velocity=Vector2.ZERO
	check(car.global_position.x<tree.global_position.x-10,"native car collision stops at the trunk")
	var nose: float=car.global_position.x+car.collision.position.x+car.collision.shape.size.x*.5
	check(nose<=tree.global_position.x-31.0,"bonnet stops outside the low branches, not at the thin trunk")
	var bursts := get_nodes_in_group("tree_ice_burst")
	check(bursts.size()==1,"native vehicle contact releases one ice burst")
	if bursts.is_empty(): quit(1); return
	var burst = bursts[0]
	check(burst.pieces.size()==24,"ice release uses a bounded set of fragments")
	tree.receive_vehicle_contact(200,Vector2.RIGHT,car)
	check(get_nodes_in_group("tree_ice_burst").size()==1,"sustained contact respects the tree cooldown")
	trees[0].receive_vehicle_contact(200,Vector2.RIGHT,car)
	check(get_nodes_in_group("tree_ice_burst").size()==1,"a bare tree cannot shed ice")
	if recording:
		burst.set_process(false)
		for frame in 90:
			if frame>60: car.position.x-=.5
			burst._process(1.0/30)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/forest-ground-0913/contact-frame%03d.png"%video_frame)
			video_frame+=1
		burst.set_process(true)
	if DisplayServer.get_name()!="headless":
		await create_timer(.30).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/forest-ground-0913/ice-falling.png")
	while burst.age<2.1: await process_frame
	check(burst.roof_hits>0,"falling fragments land on the actual vehicle footprint")
	check(burst.ground_hits>0,"other fragments land on the ground")
	var roof_piece: Dictionary
	for piece in burst.pieces:
		if piece.roof!=null: roof_piece=piece; break
	if not roof_piece.is_empty():
		var prior: Vector2=burst.to_global(roof_piece.p)
		car.position+=Vector2(-8,0)
		burst._process(0)
		check(burst.to_global(roof_piece.p).distance_to(prior+Vector2(-8,0))<.01,"landed ice follows the car when it moves away")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/forest-ground-0913/ice-landed.png")
	burst._process(6)
	await process_frame
	await process_frame
	check(get_nodes_in_group("tree_ice_burst").is_empty(),"ice melts and releases its processing nodes")
	# Sweep the production chassis from every side; no branch collider is
	# temporarily disabled and no teleport is used during approach.
	var dry_tree = trees[0]
	# The variety sheet has neighbouring trees only 80px apart. Move the
	# target into open ground so the starting chassis fits on all four sides.
	dry_tree.global_position=Vector2(0,550)
	var hull: RectangleShape2D=car.collision.shape
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		car.rotation=direction.angle()
		car.global_position=dry_tree.global_position+Vector2(0,3)-direction*90
		car.reset_physics_interpolation()
		await physics_frame
		await physics_frame
		for i in 45:
			await physics_frame
			car.velocity=direction*180
			MOTION.move(car)
		var local_center: Vector2=car.collision.to_local(dry_tree.get_node("TrunkCol").global_position)
		var closest := local_center.clamp(-hull.size*.5,hull.size*.5)
		check(local_center.distance_to(closest)>=31.9 and car.global_position.distance_to(dry_tree.global_position)<85,"vehicle remains outside low branches approaching %s"%direction)
	car.velocity=Vector2.ZERO
	world.queue_free()
	await process_frame
	print("FOREST_ICE failures=",failures)
	quit(failures)
