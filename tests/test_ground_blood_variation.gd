extends SceneTree
const BLOOD := preload("res://guns/combat/GroundBlood.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var outlines: Array[PackedVector2Array] = []
	var stains: Array[Node2D] = []
	for index in 12:
		var stain := BLOOD.new()
		stain.pattern_seed = index + 50
		stain.radius = 17.0 if index < 6 else 6.0
		stain.position = Vector2(90 + (index % 6) * 125, 100 + (index / 6) * 130)
		world.add_child(stain)
		stain.set_process(false)
		stain._process(3.0)
		check(Geometry2D.triangulate_polygon(stain.outline).size() > 0, "pattern %d forms a valid polygon" % index)
		check(not outlines.has(stain.outline), "pattern %d has a distinct contour" % index)
		outlines.append(stain.outline)
		stains.append(stain)
	var first = stains[0]
	var repeat := BLOOD.new()
	repeat.pattern_seed = 50
	repeat.radius = 17.0
	world.add_child(repeat)
	check(first.outline == repeat.outline and first.droplets == repeat.droplets, "fixed seed reproduces the same pattern")
	repeat.queue_free()
	var original: PackedVector2Array = first.outline.duplicate()
	first._process(1.0)
	check(first.outline == original, "pattern stays stable as stain ages")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(960, 540)
		root.content_scale_size = Vector2i(820, 340)
		RenderingServer.set_default_clear_color(Color("92928a"))
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/blood-review")
		root.get_texture().get_image().save_png("D:/geteco/artifacts/blood-review/patterns.png")
	first.age = 0.0
	first._process(12.0)
	check(is_equal_approx(first.modulate.a, 1.0), "stain remains visible through 12 seconds")
	first._process(3.0)
	check(is_equal_approx(first.modulate.a, 0.5), "stain fades gradually at 15 seconds")
	first._process(3.0)
	check(first.is_queued_for_deletion(), "stain is removed at 18 seconds")
	await process_frame
	check(not is_instance_valid(first), "expired stain is actually freed")
	print("GROUND_BLOOD failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
