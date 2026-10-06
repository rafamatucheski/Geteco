extends SceneTree
## Art review through the ordinary gameplay camera, never an FPS measurement.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var output := ""
var photos: Array[Dictionary]=[]
var failures: Array[String]=[]
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("DESERT_DETAIL_CAPTURE timeout"); quit(3))
	run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-detail-main")
	var checkpoint:=FIXTURE.full_snapshot(Vector3(300,.08,-742),true)
	checkpoint.region_id="desert"
	checkpoint.world.pedestrian={"region":"desert","position":[300,.08,-742]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",checkpoint)
	if path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path: quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode=true
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	for setup in [
		{"id":"miragem-pumps","point":Vector3(300,.08,-742)},
		{"id":"miragem-shop","point":Vector3(276,.08,-768)},
		{"id":"bitrens","point":Vector3(250,.08,-731)},
		{"id":"cobre","point":Vector3(-210,.08,-904)},
		{"id":"solana","point":Vector3(-249,.08,-869)},
		{"id":"digo","point":Vector3(-140,.08,-940)},
		{"id":"horizonte","point":Vector3(-320,.08,-910)},
		{"id":"road-power-lines","point":Vector3(350,.08,-728)},
		{"id":"road-junction","point":Vector3(329,.08,-868)},
		{"id":"road-curve","point":Vector3(320,.08,-1521)},
	]:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		await physics_frame
		world.player.teleport(setup.point)
		world.session.weather.time_of_day=.43
		world.session.weather._update()
		for i in 480:
			await physics_frame
			if world.production.region.is_streaming_idle(): break
		await create_timer(2.0).timeout
		var residents: Dictionary=world.session.desert.get_node("DesertLocals").locals
		var resident_points: Dictionary={}
		for id in residents:
			var resident=residents[id]
			if is_instance_valid(resident): resident_points[id]=resident.global_position
		await create_timer(1.0).timeout
		var movement: Dictionary={}
		for id in resident_points:
			var resident=residents.get(id)
			if not is_instance_valid(resident): continue
			movement[id]={"distance":resident.global_position.distance_to(resident_points[id]),"floor":resident.is_on_floor(),"position":str(resident.global_position)}
			if not resident.global_position.is_finite() or resident.global_position.y < -.15 or resident.global_position.y>1.0:
				failures.append("Resident floor/position: "+str(id))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(setup.id+".png"))
		photos.append({"id":setup.id,"point":str(world.player.global_position),"camera_size":world.camera.size,"stream_idle":world.production.region.is_streaming_idle(),"people":world.people.size(),"locals":residents.size(),"resident_motion":movement})
	FileAccess.open(output.path_join("photos.json"),FileAccess.WRITE).store_string(JSON.stringify(photos,"\t"))
	print("DESERT_DETAIL_CAPTURE ",output)
	print("DESERT_DETAIL_RESIDENT_FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)
