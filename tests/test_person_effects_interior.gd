extends SceneTree
var failures := 0
var room: Node2D
var helper: Node
var output := "D:/geteco/artifacts/person-weapon-effects"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return room.viewport_3d.get_texture().get_image()

func difference(a: Image, b: Image, pixel: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0, int(pixel.y)-50), mini(a.get_height(), int(pixel.y)+50)):
		for x in range(maxi(0, int(pixel.x)-50), mini(a.get_width(), int(pixel.x)+50)):
			if a.get_pixel(x,y) != b.get_pixel(x,y): changed += 1
	return changed

func occlusion(models: Array, label: String, point: Vector3) -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6, 6, .2)
	panel.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	room.viewport_3d.add_child(panel)
	panel.position = point + (room.camera_3d.position - point).normalized() * 2
	panel.look_at(room.camera_3d.global_position)
	var pixel: Vector2 = room.camera_3d.unproject_position(point)
	var visible_image: Image = await capture()
	for model in models: model.hide()
	var hidden_image: Image = await capture()
	check(difference(visible_image, hidden_image, pixel) == 0, label + " is occluded by solid 3D geometry")
	panel.hide()
	for model in models: model.show()
	visible_image = await capture()
	visible_image.save_png(output.path_join(label + "-interior.png"))
	for model in models: model.hide()
	hidden_image = await capture()
	check(difference(visible_image, hidden_image, pixel) > 0, label + " positive control is visible without occluder")
	for model in models: model.show()
	panel.queue_free()

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	if DisplayServer.get_name() == "headless":
		push_error("Interior effect depth requires rendering")
		quit(2)
		return
	root.get_node("SaveManager")._save_dir = output.path_join("interior-test-saves") + "/"
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	room = load("res://world/mountain_pass/MountainCabinInterior.gd").new()
	world.add_child(room)
	var actor = load("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(actor)
	actor.ensure_presentation()
	actor.set_physics_process(false)
	actor.health = 1000
	actor.global_position = room.to_global(room.project_floor(Vector2(0, .4)))
	helper = load("res://systems/interiors/InteriorActorPresentation.gd").new()
	world.add_child(helper)
	helper.configure(actor, room.camera_3d, room.sprite_3d)
	var fire = load("res://guns/combat/PersonBurning.gd").ignite(actor)
	await create_timer(.6).timeout
	check(is_instance_valid(fire.interior_fire) and not fire.flames.visible, "Interior burn uses 3D particles without external overlay")
	check(fire.interior_fire.get_viewport() == room.viewport_3d, "Fire shares room depth buffer")
	fire.set_physics_process(false)
	for emitter in fire.interior_fire.get_children(): emitter.speed_scale = 0
	await occlusion([fire.interior_fire], "fire", helper.anchor.position + Vector3.UP * .9)
	fire.queue_free()
	await process_frame
	var grenade = load("res://guns/GrenadeProjectile.tscn").instantiate()
	world.add_child(grenade)
	grenade.setup(actor.global_position + Vector2(2, 0), Vector2.ZERO, 0, null)
	grenade.damage = 2000
	await physics_frame
	grenade.explode()
	await process_frame
	var queued_remains: Node = actor.get_meta("explosion_remains", null)
	while is_instance_valid(queued_remains) and queued_remains._build_index < queued_remains._build_plans.size(): await process_frame
	check(actor.has_meta("explosion_remains"), "Interior grenade produces fragments")
	if not actor.has_meta("explosion_remains"):
		quit(1)
		return
	var remains: Node = actor.get_meta("explosion_remains")
	var visual: Node = remains.get_child(remains.get_child_count()-1)
	check(visual.models.size() == remains.pieces.size() and visual.models.size() >= 4, "Every variable fragment has original body meshes in the interior")
	var models: Array = visual.models.values()
	await create_timer(2.0).timeout
	for piece in remains.pieces:
		piece.set_physics_process(false)
		piece.height = 0
		piece.velocity = Vector2.ZERO
	visual._process(0)
	visual.set_process(false)
	check(not helper.anchor.visible, "Intact corpse is hidden in shared room renderer")
	for model in models: check(model.get_viewport() == room.viewport_3d, "Fragment shares room depth buffer")
	await occlusion(models, "fragments", models[0].global_position)
	world.queue_free()
	await process_frame
	await process_frame
	for model in models: check(not is_instance_valid(model), "Room teardown releases fragment meshes")
	print("PERSON_INTERIOR_EFFECTS failures=", failures)
	quit(0 if failures == 0 else 1)
