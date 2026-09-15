extends SceneTree

const IMPACT = preload("res://world/shared/combat/VehiclePersonImpact.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	var output := "D:/geteco/artifacts/dante-blood-0913"
	DirAccess.make_dir_recursive_absolute(output + "/saves")
	root.get_node("SaveManager").set("_save_dir", output + "/saves/")
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var road := Polygon2D.new()
	road.polygon = PackedVector2Array([Vector2(-1000,-1000),Vector2(1000,-1000),Vector2(1000,1000),Vector2(-1000,1000)])
	road.color = Color("394144")
	road.z_index = 2
	world.add_child(road)
	var player = preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2.ONE * 3
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	var car := CharacterBody2D.new()
	world.add_child(car)
	car.position = Vector2(-50,0)
	player.get_run_over(Vector2(30,0))
	check(player.health == 100 and not player.is_recovering, "slow contact causes no injury")
	player._respawn_grace_active = true
	check(not IMPACT.hit(car, player, Vector2(180,0)), "respawn protection emits no injury feedback")
	player._respawn_grace_active = false
	check(IMPACT.hit(car, player, Vector2(180,0)), "real vehicle path injures Dante")
	check(player.health == 55 and not player.is_dead, "survivable impact retains damage")
	check(get_nodes_in_group("vehicle_splashes").is_empty(), "no duplicate broad vehicle splash")
	var bursts := world.find_children("*", "CPUParticles2D", false, false)
	check(bursts.size() == 1, "exactly one compact burst")
	var burst := bursts[0] as CPUParticles2D
	check(burst.scale_amount_max * burst.texture.get_width() <= 5.01, "drops at most five world pixels")
	var origin := burst.global_position
	player.position += Vector2(45,0)
	check(burst.global_position == origin and not burst.local_coords, "splash remains at impact after actor moves")
	var stains := get_nodes_in_group("ground_blood")
	check(stains.size() == 1 and stains[0].radius == 6.0, "injury creates one small current ground stain")
	check(stains[0].z_index > road.z_index and not stains[0].z_as_relative, "stain visible above road")
	check(not IMPACT.hit(car, player, Vector2(180,0)), "repeat contact during recovery adds no effects")
	await create_timer(0.18).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/injury.png")
	await create_timer(1.6).timeout
	check(world.find_children("*", "CPUParticles2D", false, false).is_empty(), "completed particles are freed")
	player.health = 10
	check(IMPACT.hit(car, player, Vector2(180,0)), "fatal vehicle impact accepted")
	stains = get_nodes_in_group("ground_blood")
	check(player.is_dead and stains.size() == 2 and stains[1].radius == 17.0, "death adds exactly one current lethal pool")
	check(world.find_child("3DBloodPuddle", false, false) == null, "legacy pool no longer created")
	check(not IMPACT.hit(car, player, Vector2(180,0)), "dead player does not emit another burst")
	print("DANTE_VEHICLE_BLOOD failures=", failures)
	quit(0 if failures == 0 else 1)
