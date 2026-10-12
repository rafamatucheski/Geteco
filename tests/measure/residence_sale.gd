extends SceneTree
## Real rendered exteriors, isolated wallet and no user saves.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const OUT := "res://output/residence-sale-20261010"
var world
var label := "before"
var failures: Array[String] = []
var results := {}
var homes: Array[String] = ["westgate_garden","quayside_house","canal_north"]

func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	print("SALE_CHECK ", "PASS " if ok else "FAIL ", description)
	if not ok: failures.append(description)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--homes="): homes.assign(arg.trim_prefix("--homes=").split(","))
	create_timer(240).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUT)
	seed(1002026)
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	while world.session == null or not world.session.ready_for_play: await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .38
	world.session.weather.weather_timer = 99999
	world.session.weather.weather_state = 0
	world.session.weather._update()
	for id in homes:
		var definition: Dictionary = PLACES.get_definition(id)
		world.production.region.set_focus(definition.entry_position)
		world.player.teleport(definition.entry_position+Vector3(0,.08,2))
		world.camera.heading = 0
		world.camera.target_size = 24
		world.camera.initialized = false
		await create_timer(5).timeout
		await photo(id)
		await sample(id)
		if label.begins_with("after"): await verify(id,definition)
	results.environment = {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"resolution":"1280x720","population":world.production.requested_population}
	FileAccess.open(OUT+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("SALE_RESULT ", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+label+"-"+id+".png")

func sample(id: String) -> void:
	var rows: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		rows.append((now-previous)/1000.0)
		previous = now
	var sorted := rows.duplicate()
	sorted.sort()
	var slow := 0
	var very_slow := 0
	for value in rows:
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	results[id] = {"samples_ms":rows,"frames":rows.size(),"seconds":(previous-start)/1000000.0,"fps":rows.size()*1000000.0/(previous-start),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over_33":slow,"over_66":very_slow}
	print("SALE_SAMPLE ",label," ",id," fps=",results[id].fps," p95=",results[id].p95)

func verify(id: String, definition: Dictionary) -> void:
	var markers := get_nodes_in_group("residence_sale_marker")
	var marker: Node3D
	for node in markers:
		if node.property_id == id: marker = node
	check(is_instance_valid(marker),id+" has sale marker")
	if not is_instance_valid(marker): return
	check(marker.visible,id+" available marker visible")
	var before: Vector3 = marker.glyph.rotation
	await create_timer(.4).timeout
	check(not marker.glyph.rotation.is_equal_approx(before),id+" symbol rotates")
	var home = world.session.activities.residence
	world.player.teleport(definition.entry_position+Vector3.UP*.08)
	world.session.state.economy.grant_reward("sale_test:"+id,100000)
	check(home.buy(id),id+" actual purchase at entrance")
	await create_timer(.4).timeout
	check(not marker.visible,id+" purchased marker hidden")
	var saved: Dictionary = home.snapshot()
	home.data.active_home = ""
	await create_timer(.4).timeout
	check(marker.visible,id+" released house for sale again")
	check(home.restore_snapshot(saved),id+" ownership restores")
	await create_timer(.4).timeout
	check(not marker.visible,id+" restored ownership hides marker")
	var parking: Node3D = marker.get_parent().get_node("ResidentialGarage")
	world.player.teleport(parking.to_global(Vector3(6.5,.08,0)))
	await create_timer(.5).timeout
	check(parking.get_node("GarageCanopy").visible,id+" canopy persists with player inside")
	await photo(id+"-garage-occupied")
	home.data.active_home = ""
