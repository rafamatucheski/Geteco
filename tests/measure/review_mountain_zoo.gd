extends SceneTree
const ZOO=preload("res://world/mountain_detail/zoo/MountainZoo.gd")
var world
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.production._update_physical_residency(ZOO.CENTER)
	world.production._update_logical_region(ZOO.CENTER)
	world.player.teleport(ZOO.CENTER+Vector3(0,.1,32))
	world.player.controlled_automatically=true
	world.session.state.economy.grant_outfit("dante_ski")
	world.session.state.economy.equip_outfit("dante_ski")
	world.session.apply_outfit()
	world.player.speed=4
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day=.5; world.session.weather.weather_state=0
	world.session.weather._update(); world.session.weather.set_process(false)
	for i in 300: await process_frame
	DirAccess.make_dir_recursive_absolute("res://artifacts/mountain-zoo/tour")
	world.session.state.economy.grant_reward("zoo_review",300)
	var route: Array[Vector3]=[Vector3(-.7,0,22),Vector3(-.7,0,18),Vector3(0,0,0),Vector3(0,0,-17),Vector3(-9,0,-17),Vector3(-17,0,-14.8),Vector3(-20,0,-7),Vector3(-20,0,0),Vector3(0,0,0),Vector3(20,0,0),Vector3(20,0,8),Vector3(16.5,0,14.8),Vector3(8,0,17),Vector3(0,0,17),Vector3(-.7,0,23),Vector3(0,0,32)]
	var snapshots: Array[Dictionary]=[]
	for step in route.size():
		var target:=ZOO.CENTER+route[step]
		var arrived:=false
		for frame in 1200:
			await physics_frame
			var direction: Vector3=target-world.player.global_position; direction.y=0
			if direction.length()<.3: arrived=true; break
			world.player.automatic_direction=direction.normalized()
		world.player.automatic_direction=Vector3.ZERO
		if step==0:
			var before: int=world.session.state.economy.balance
			if not world.session.interact(): failures.append("Ticket interaction unavailable")
			if world.session.state.economy.balance!=before-30: failures.append("Ticket must cost exactly $30")
			for i in 360: await physics_frame
		if not arrived: failures.append("Cannot walk to stop "+str(step))
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/mountain-zoo/tour/stop-%02d.png"%step)
		snapshots.append({"stop":step,"position":str(world.player.global_position),"arrived":arrived,"height":world.player.global_position.y})
		if not arrived: break
	FileAccess.open("res://artifacts/mountain-zoo/tour/results.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"stops":snapshots},"\t"))
	print("ZOO_TOUR ","PASS" if failures.is_empty() else str(failures))
	world.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
