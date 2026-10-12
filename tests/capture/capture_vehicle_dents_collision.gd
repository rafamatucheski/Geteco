extends SceneTree
## Real Main + compiled C#; real motion into a temporary test barrier.
const FIXTURE:=preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE:=preload("res://runtime/GameState.gd")
const STORE:=preload("res://runtime/SaveStore.gd")
var output: String
var world
var failures: Array[String]=[]
func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("DENTS_COLLISION timeout"); quit(3))
	run.call_deferred()
func check(value: bool,label: String) -> void:
	if not value: failures.append(label); push_error(label)
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("vehicle-dents-collision")
	var reload_path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reload="): reload_path=arg.trim_prefix("--reload=")
	var path:=reload_path if not reload_path.is_empty() else FIXTURE.write_fixture(output,"initial.json",FIXTURE.full_snapshot(Vector3(37.625,.12,18.875),true))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 7000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if not failures.is_empty(): quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# router")
	check(world.production.store.path==path and not world.production.save_invalid,"isolated valid checkpoint")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	if world.session.modal: world.session.close_menu()
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	var car: CharacterBody3D=world.driving.car
	world.camera.set_process(false)
	world.camera.size=7
	world.camera.global_position=car.global_position+Vector3(5,5,-6)
	world.camera.look_at(car.global_position+Vector3.UP*.6)
	world.camera.current=true
	await create_timer(3).timeout
	if not reload_path.is_empty():
		check(not car.body_dents.dents.is_empty(),"production reload restores amassados")
		await shot("production-restored")
		car.repair()
		await create_timer(.5).timeout
		check(car.body_dents.dents.is_empty(),"repair after reload clears dents")
		await shot("production-repaired")
	else:
		var start:=car.global_position
		var yaw: float=world.production.road_yaw(start)
		car.place(start,yaw)
		var wall:=StaticBody3D.new()
		wall.collision_layer=1
		wall.collision_mask=4
		var collision:=CollisionShape3D.new()
		var box:=BoxShape3D.new()
		box.size=Vector3(5,2,.35)
		collision.shape=box
		wall.add_child(collision)
		var mesh:=MeshInstance3D.new()
		var visible_box:=BoxMesh.new()
		visible_box.size=box.size
		mesh.mesh=visible_box
		wall.add_child(mesh)
		world.add_child(wall)
		wall.global_position=start-car.global_basis.z*6+Vector3.UP
		wall.rotation.y=yaw
		await shot("before-collision")
		car.set_external_driver(true)
		car.speed=12
		car.horizontal_velocity=-car.global_basis.z*12
		var frames: Array=[]
		var health: float=car.health
		for i in 150:
			await physics_frame
			if car.health<health:
				for step in 12:
					await process_frame
					frames.append({"frame":Engine.get_process_frames(),"visual_rotation":str(car.visual.rotation),"recoil_active":car.body_dents.is_processing()})
				break
		check(car.health<health and not car.body_dents.dents.is_empty(),"real driving impact deforms body")
		car.set_external_driver(false)
		car.set_physics_process(false)
		car.speed=0
		car.horizontal_velocity=Vector3.ZERO
		world.camera.global_position=car.global_position+Vector3(5,5,-6)
		world.camera.look_at(car.global_position+Vector3.UP*.6)
		await create_timer(.5).timeout
		wall.queue_free()
		await process_frame
		await shot("after-collision")
		var record:=preload("res://runtime/FleetState.gd").capture(car,"harbor")
		record.was_driven=false
		var snapshot: Dictionary=world.session.state.snapshot()
		snapshot.world.vehicles=[record]
		var state:=STATE.new()
		check(state.restore_snapshot(snapshot),"full GameState accepts dented vehicle")
		var store:=STORE.new()
		store.path=output.path_join("dented-save.json")
		check(store.save(state)==OK,"real SaveStore writes isolated checkpoint")
		print("DENTS_RELOAD_PATH ",store.path)
		car.repair()
		await shot("repaired")
		var file:=FileAccess.open(output.path_join("recoil.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(frames,"\t")); file.close()
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"reload":reload_path,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info()},"\t")); file.close()
	print("DENTS_COLLISION ",output," failures=",failures)
	quit(0 if failures.is_empty() else 1)
