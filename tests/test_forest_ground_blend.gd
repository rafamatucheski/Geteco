extends SceneTree
var failures := 0
const SOIL = preload("res://world/mountain_pass/ForestGroundBlend.gd")
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures+=1
func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	root.size = Vector2i(512,512)
	root.content_scale_size = root.size
	var world := Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	world.add_child(camera)
	var forest := Polygon2D.new()
	forest.polygon = PackedVector2Array([Vector2(-256,-256),Vector2(256,-256),Vector2(256,256),Vector2(-256,256)])
	world.add_child(forest)
	SOIL.polygon(forest,"forest",0)
	var road := Line2D.new()
	road.width = 50
	road.points = PackedVector2Array([Vector2(-220,0),Vector2(180,0)])
	world.add_child(road)
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").apply(road,"earth")
	SOIL.path(road,16)
	var clearing := Polygon2D.new()
	clearing.polygon = PackedVector2Array([Vector2(-80,-70),Vector2(100,-70),Vector2(100,70),Vector2(-80,70)])
	world.add_child(clearing)
	SOIL.polygon(clearing,"earth",28)
	var walker := CharacterBody2D.new()
	walker.collision_mask=1
	var shape := CollisionShape2D.new()
	shape.shape=CircleShape2D.new()
	shape.shape.radius=7
	walker.add_child(shape)
	world.add_child(walker)
	await physics_frame
	await physics_frame
	check(not walker.test_move(Transform2D(0,Vector2(-200,0)),Vector2(350,0)),"road, clearing and their blended margins remain walkable")
	var fringe: ArrayMesh = clearing.get_node("SoilTransition").mesh
	var bounds := fringe.get_aabb()
	check(bounds.position.x < -95 and bounds.end.x >115 and bounds.position.y < -85 and bounds.end.y>85,"transition extends outside all four sides, without an inward border")
	if DisplayServer.get_name()!="headless":
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var joined := root.get_texture().get_image()
		joined.save_png("D:/geteco/artifacts/forest-ground-0913/junction.png")
		clearing.hide()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var road_only := root.get_texture().get_image()
		var difference := 0.0
		for x in range(145,345):
			var a := joined.get_pixel(x,256)
			var b := road_only.get_pixel(x,256)
			difference=maxf(difference,Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length())
		check(difference<.015,"road-to-clearing overlap preserves the same visible soil (max RGB difference %.5f)"%difference)
	else:
		print("SKIP rendered seam comparison requires a rendering device")
	await _check_chalet(world)
	world.queue_free()
	await process_frame
	print("FOREST_GROUND failures=",failures)
	quit(failures)

func _check_chalet(world: Node2D) -> void:
	var elevated := Node2D.new()
	elevated.z_index=2
	world.add_child(elevated)
	var cabin := preload("res://world/mountain_pass/MountainProp.gd").new()
	cabin.model_script=preload("res://world/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
	elevated.add_child(cabin)
	var actor := CharacterBody2D.new()
	var collider := CollisionShape2D.new()
	collider.shape=CircleShape2D.new()
	collider.shape.radius=7
	actor.add_child(collider)
	actor.add_to_group("player")
	world.add_child(actor)
	actor.position.y=100
	cabin._process(0)
	var yard := Polygon2D.new()
	yard.z_index=-1
	yard.polygon=PackedVector2Array([Vector2(-100,-100),Vector2(100,-100),Vector2(100,100),Vector2(-100,100)])
	cabin.add_child(yard)
	SOIL.polygon(yard)
	check(yard.z_index<cabin.sprite.z_index and not yard.z_as_relative,"elevated chalet container cannot lift the soil above its facade")
	await physics_frame
	await physics_frame
	check(actor.test_move(Transform2D(0,Vector2(0,100)),Vector2(0,-120)),"chalet footprint stops an approaching actor")
	if DisplayServer.get_name()=="headless": return
	cabin._render_when_visible()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var with_yard := root.get_texture().get_image()
	with_yard.save_png("D:/geteco/artifacts/forest-ground-0913/chalet-depth.png")
	yard.hide()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var without_yard := root.get_texture().get_image()
	var texture := cabin.viewport.get_texture().get_image()
	var pixels := 0
	var covered := 0
	for y in range(195,290):
		for x in range(200,312):
			var local := (Vector2(x+.5,y+.5)-Vector2(256,256)-cabin.sprite.position)/cabin.DISPLAY_SCALE+Vector2(128,128)
			if local.x<2 or local.y<2 or local.x>253 or local.y>253: continue
			var opaque := true
			# Check the whole filtering footprint, including holes between planks.
			for dy in range(-2,3):
				for dx in range(-2,3):
					if texture.get_pixelv(Vector2i(local+Vector2(dx,dy))).a<.999: opaque=false
			if not opaque: continue
			pixels+=1
			var a := with_yard.get_pixel(x,y)
			var b := without_yard.get_pixel(x,y)
			if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.02: covered+=1
	check(pixels>200 and covered==0,"opaque chalet roof and facade stay visible over soil (%d pixels, %d covered)"%[pixels,covered])
