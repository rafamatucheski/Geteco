extends SceneTree

var failures: Array[String] = []
var world: Node2D
var camera: Camera2D
var capture_only := false
var tag := "after"
const OUT := "res://docs/measurements/hospital-cranes-0920/"

class DepthActor extends CharacterBody2D:
	var sprite_3d_display: Sprite2D

func magenta_pixels() -> int:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var count := 0
	for y in range(260,460):
		for x in range(540,740):
			var c := image.get_pixel(x,y)
			if c.r > .9 and c.b > .9 and c.g < .1: count += 1
	return count

func check_crane_depth(waterfront: Node2D) -> void:
	if DisplayServer.get_name() == "headless": return
	var actor := DepthActor.new()
	actor.collision_layer = 4
	actor.collision_mask = 0
	actor.z_index = 10
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 6
	actor.add_child(shape)
	var image := Image.create(20,44,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,0,1))
	actor.sprite_3d_display = Sprite2D.new()
	actor.sprite_3d_display.texture = ImageTexture.create_from_image(image)
	actor.sprite_3d_display.position.y = -22
	actor.add_child(actor.sprite_3d_display)
	world.add_child(actor)
	for i in waterfront.CRANE_Y.size():
		actor.position = Vector2(3515,waterfront.CRANE_Y[i]-45)
		for frame in 4: await physics_frame
		await shot("crane-depth%d" % i,actor.position+Vector2(0,-22),3.0)
		var zone: Area2D
		for child in waterfront.get_node("NorthstarCrane%d" % i).get_children():
			if child is Area2D: zone = child
		check(zone != null and zone.overlay.visible, "Crane " + str(i) + " occludes actor beneath raised jib")
		var covered := await magenta_pixels()
		zone.set_process(false)
		zone.overlay.hide()
		await process_frame
		var bare := await magenta_pixels()
		check(bare > 0 and covered < bare, "Crane " + str(i) + " actual pixels cover actor with positive visibility control")
		zone.set_process(true)
		actor.position.y = waterfront.CRANE_Y[i]+90
		for frame in 4: await physics_frame
		await shot("crane-front%d" % i,actor.position+Vector2(0,-22),3.0)
		var front_visible := await magenta_pixels()
		zone.set_process(false)
		zone.overlay.hide()
		await process_frame
		var front_bare := await magenta_pixels()
		check(front_bare > 0 and front_visible == front_bare, "Actor in front of crane remains visible independently of crew behind it")
		zone.set_process(true)
	actor.queue_free()

func check_cranes_above_water(waterfront: Node2D) -> void:
	if DisplayServer.get_name() == "headless": return
	var water: Array[CanvasItem] = []
	for child in waterfront.get_children():
		if child is CanvasItem and child.is_in_group("animated_water_visual"):
			water.append(child)
	check(water.size() == 5, "All five animated channel surfaces are inspected")
	for i in waterfront.CRANE_Y.size():
		var y: float = waterfront.CRANE_Y[i]
		var base := Vector2(3165,y)
		var tip := Vector2(3715-i*26,y-110)
		var across := (tip-base).normalized().orthogonal()*11.0
		var points: Array[Vector2] = [base+Vector2(-17,-20),base+Vector2(-17,20)]
		for along in [.12,.35,.62,.90]:
			points.append(base.lerp(tip,along)+across)
			points.append(base.lerp(tip,along)-across)
		await shot("northstar-full%d" % i,Vector2(3430,y-45),1.8)
		await RenderingServer.frame_post_draw
		var wet := root.get_texture().get_image()
		for surface in water: surface.hide()
		for frame in 2: await process_frame
		await RenderingServer.frame_post_draw
		var dry := root.get_texture().get_image()
		var correct := true
		for point in points:
			var pixel := Vector2i(root.canvas_transform * point)
			var a := wet.get_pixelv(pixel)
			var b := dry.get_pixelv(pixel)
			var difference := Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()
			correct = correct and difference < .015 and a.r > a.b*1.2
			print("NORTHSTAR_WATER_LAYER crane=",i," point=",point," rgb=",a," water_difference=",difference)
		check(correct, "Northstar crane " + str(i) + " pedestal and both jib rails remain above animated water along their full span")
		for surface in water: surface.show()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func shot(label: String, point: Vector2, zoom: float) -> void:
	if DisplayServer.get_name() == "headless": return
	camera.position = point
	camera.zoom = Vector2.ONE * zoom
	camera.reset_physics_interpolation()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + tag + "-" + label + ".png")

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	capture_only = "--before" in OS.get_cmdline_user_args()
	if capture_only: tag = "before"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	camera = Camera2D.new()
	world.add_child(camera)
	var hospital = preload("res://world/harbor/hospital/HarborHospital.gd").new()
	hospital.footprint = Vector2(260,230)
	hospital.building_kind = "hospital"
	world.add_child(hospital)
	await shot("facade", Vector2(20,-20), 2.1)
	var room = preload("res://world/harbor/interiors/HarborHospitalInterior3D.gd").new()
	room.position = Vector2(2000,0)
	world.add_child(room)
	room.set_npc_rendering_active(true)
	await shot("interior", room.position, 1.45)
	var waterfront = preload("res://world/harbor/HarborWaterfront.gd").new()
	world.add_child(waterfront)
	await shot("northstar-crane", Vector2(3410,940), 1.8)
	if not capture_only:
		check(room.spawn_point.position.y > 0 and room.exit_door.position.y > room.spawn_point.position.y, "South exterior access leads to the south interior doorway")
		check(is_zero_approx(room.exit_door.rotation), "Exit faces the same south frontage")
		hospital.public_entrance._set_door_open(true)
		await create_timer(hospital.public_entrance.open_duration + .08).timeout
		check(hospital.public_door_amount > .99, "Public glass doors fully open with the entrance tween")
		await shot("facade-open", Vector2(0,85), 3.0)
		hospital.public_entrance._set_door_open(false)
		await create_timer(hospital.public_entrance.close_duration + .08).timeout
		check(hospital.public_door_amount < .01 and not hospital.is_processing(), "Public doors close and stop redrawing")
		var actor := CharacterBody2D.new()
		actor.collision_layer = 4
		actor.collision_mask = 1
		var collision := CollisionShape2D.new()
		collision.shape = CircleShape2D.new()
		collision.shape.radius = 10
		actor.add_child(collision)
		world.add_child(actor)
		await physics_frame
		for y in waterfront.CRANE_Y:
			actor.position = Vector2(3165,y+80)
			check(actor.move_and_collide(Vector2(0,-100)) != null, "Northstar crane pedestal blocks a swept actor at " + str(y))
		actor.position = room.spawn_point.global_position
		check(not actor.test_move(actor.global_transform,Vector2.ZERO), "Hospital south spawn fits the complete body")
		check(actor.move_and_collide(room.to_global(room.project_floor(Vector2(0,0))) - actor.position) == null, "Hospital south entrance opens onto a clear central aisle")
		var tree = preload("res://geodata/nature/ProceduralStreetTree.gd").new()
		tree.position = Vector2(1000,0)
		world.add_child(tree)
		await physics_frame
		for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			actor.position = tree.position + Vector2(0,5) + direction*60
			check(actor.move_and_collide(-direction*80) != null, "Tree trunk blocks swept movement from " + str(direction))
		await check_crane_depth(waterfront)
		await check_cranes_above_water(waterfront)
	print("HOSPITAL_CRANE_ACCESS failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
