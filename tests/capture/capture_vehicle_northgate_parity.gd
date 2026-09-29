extends SceneTree

const Services := preload("res://runtime/Services.gd")
var world
var failures: Array[String] = []
const OUTPUT := "res://evidence/"

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition: return
	failures.append(label)
	push_error(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func wait_transition(limit := 240) -> bool:
	for index in limit:
		await physics_frame
		if not world.driving.is_body_transition_active(): return true
	return false

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")

func run() -> void:
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	for index in 1200:
		await physics_frame
		if world.production != null and world.production.ready_for_play and world.session.ready_for_play: break
	check(world.production != null and world.production.ready_for_play,"production starts")
	check(world.production.no_save,"capture is isolated from the player's save")
	if not failures.is_empty(): quit(1); return
	var car = world.driving.car
	world.camera.heading = -.58
	world.player.teleport(car.driver_door_anchor(-1)+car.global_basis.x*-.42)
	await frames(3)
	await capture("v2-vehicle-entry-00-approach")
	check(world.driving.interact(),"physical entry starts")
	await frames(26)
	await capture("v2-vehicle-entry-25-reach")
	await frames(32)
	await capture("v2-vehicle-entry-55-step")
	await frames(32)
	await capture("v2-vehicle-entry-80-occlusion")
	check(await wait_transition(),"entry finishes")
	await frames(3)
	await capture("v2-vehicle-entry-100-seated")
	check(world.driving.occupied and world.player.visible and world.player.seated and car.controlled,"seated result")

	car.speed = 0
	car.velocity = Vector3.ZERO
	check(world.driving.leave(),"physical exit starts")
	await frames(26)
	await capture("v2-vehicle-exit-25-open")
	await frames(32)
	await capture("v2-vehicle-exit-55-step")
	await frames(32)
	await capture("v2-vehicle-exit-80-land")
	check(await wait_transition(),"exit finishes")
	await capture("v2-vehicle-exit-100-free")

	world.production.region.set_focus(Services.AUTO_ORIGIN)
	car.place(Services.AUTO_ORIGIN+Vector3(0,.12,1.4),0)
	world.player.teleport(car.driver_door_anchor(-1)+Vector3.LEFT*.38)
	await frames(12)
	check(world.driving.interact(),"Northgate approach boards")
	check(await wait_transition(),"Northgate boarding finishes")
	await frames(30)
	await capture("v2-northgate-00-open")
	world.session.state.economy.grant_reward("northgate_visual_capture",250)
	car.receive_damage(60)
	var serviced_before: int = world.session.services.serviced_count
	car.place(Services.AUTO_ORIGIN+Vector3(0,.12,-131.0/16.0),0)
	await frames(12)
	await capture("v2-northgate-20-closing")
	await frames(18)
	await capture("v2-northgate-40-spray")
	for index in 420:
		await physics_frame
		if world.session.services.serviced_count > serviced_before: break
	check(world.session.services.serviced_count==serviced_before+1,"Northgate service completes once")
	await capture("v2-northgate-90-result")
	for index in 90:
		await physics_frame
		if world.session.services._auto_phase=="idle": break
	await capture("v2-northgate-100-open")
	check(world.session.services._auto_phase=="idle" and not car.input_locked,"Northgate releases the car")

	var report := {"failures":failures,"entry_exit":"captured","northgate":"captured"}
	var file := FileAccess.open(OUTPUT+"vehicle-northgate-parity.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("VEHICLE_NORTHGATE_CAPTURE ","PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
