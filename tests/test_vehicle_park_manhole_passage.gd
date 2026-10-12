extends SceneTree
## Real Main collisions, production Vehicle and isolated save. No FPS claim in headless.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PARK := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var world
var car: CharacterBody3D
var failures: Array[String] = []
var results: Array = []
var folder := ""

func _initialize() -> void: run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame

func floor_at(point: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*3,1))

func drive(id: String, start: Vector3, target: Vector3) -> void:
	world.production.region.set_focus(start)
	world.production.region.prepare_collision_at(start)
	world.production.region.prepare_collision_at(target)
	world.player.teleport(start+Vector3(0,.1,8))
	await frames(45)
	var forward := (target-start).normalized()
	var hit := floor_at(start)
	start.y = float(hit.position.y)+.04 if not hit.is_empty() else .1
	car.place(start,atan2(-forward.x,-forward.z))
	car.brake_input = true
	car.throttle_input = 0
	await frames(30)
	car.brake_input = false
	car.throttle_input = 1
	var contacts := {}
	var min_y := INF
	var max_y := -INF
	var initial_health: float = car.health
	var remaining := INF
	for i in 300:
		await physics_frame
		min_y = minf(min_y,car.global_position.y)
		max_y = maxf(max_y,car.global_position.y)
		remaining = (target-car.global_position).dot(forward)
		if remaining < .15: break
		if car.is_on_wall():
			for j in car.get_slide_collision_count():
				var collision := car.get_slide_collision(j)
				var body = collision.get_collider()
				if is_instance_valid(body): contacts[str(body.get_path())] = {"normal":str(collision.get_normal()),"at":str(collision.get_position())}
	car.throttle_input = 0
	car.brake_input = true
	var ok: bool = remaining<.15 and min_y>-.1 and car.health>=initial_health
	var result := {"id":id,"ok":ok,"remaining":remaining,"position":str(car.global_position),"min_y":min_y,"max_y":max_y,"contacts":contacts,"damage":initial_health-car.health}
	results.append(result)
	print("DRIVE_PASSAGE ",JSON.stringify(result))
	if not ok: failures.append(id)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): push_error("Passage test timeout"); quit(3))
	seed(81026)
	folder = FIXTURE.output_dir("vehicle-park-manhole")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"fixture.json",FIXTURE.full_snapshot(PARK.ENTRY,false)))
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("C# route service required"); quit(4); return
	car = VEHICLE.new()
	car.archetype = "sport_coupe"
	car.position = PARK.ENTRY+Vector3.UP*.2
	world.add_child(car)
	car.set_external_driver(true)
	car.brake_input = true
	for x in range(38,58):
		var point := PARK.ORIGIN+Vector3(x,0,16)
		world.production.region.prepare_collision_at(point)
		var hit := floor_at(point)
		if not hit.is_empty(): print("ENTRY_FLOOR ",x," ",hit.position," ",hit.collider.get_path())
	await drive("park_entry",PARK.ORIGIN+Vector3(55,0,16),PARK.ORIGIN+Vector3(32,0,16))
	await drive("park_exit",PARK.ORIGIN+Vector3(32,0,16),PARK.ORIGIN+Vector3(55,0,16))
	var ids := SEWERS.ids() if "--all-manholes" in OS.get_cmdline_user_args() else ["harbor_sewer","sewer_market"]
	for id: String in ids:
		var at: Vector3 = PLACES.get_definition(id).exterior_position
		await drive(id+"_forward",at+Vector3(0,0,5),at-Vector3(0,0,5))
		await drive(id+"_back",at-Vector3(0,0,5),at+Vector3(0,0,5))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"results":results,"failures":failures,"native_csharp":true},"\t"))
	print("DRIVE_PASSAGE_RESULT ",folder," failures=",failures)
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
