extends SceneTree
const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
const IDS = ["cargo_flatbed_truck", "american_dump_truck", "american_tanker_truck", "boxrunner"]
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1200,800)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var camera := Camera2D.new()
	camera.position = Vector2(300,200)
	camera.zoom = Vector2.ONE*2
	world.add_child(camera)
	for i in IDS.size():
		for row in 2:
			var car = FACTORY.spawn_parked_vehicle(world,IDS[i]+str(row),Vector2(85+i*145,110+row*190),-0.55 if row == 0 else -PI/2,IDS[i],i)
			car.ensure_presentation()
			car.set_headlights(true)
			car._update_3d_orientation(0)
			check(car.body_model != null, IDS[i]+" loads")
			check(car._lamp_mounts.size() == 2, IDS[i]+" paired headlamps")
			check(car.wheels.size() == (4 if i == 3 else 6), IDS[i]+" wheel rig axle count")
			check(car.headlight.range_z_max < car.z_index, IDS[i]+" beam stays below body")
			check(car.collision.shape.size.x > 90, IDS[i]+" truck collision length")
	if DisplayServer.get_name() != "headless":
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/american-trucks.png")
	print("AMERICAN_TRUCKS failures=",failures)
	quit(1 if failures else 0)
