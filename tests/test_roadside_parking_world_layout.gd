extends "res://tests/test_roadside_parking_layout.gd"
## Complements regional geometry checks with every parking slot in Main,
## including transit stations and the separately owned bridge/tunnel shell.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var capture_enabled := false
var capture_rows: Array[Dictionary] = []

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save")
		quit(2)
		return
	create_timer(180).timeout.connect(func(): push_error("Main parking layout timeout"); quit(3))
	capture_enabled = "--parking-capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if capture_enabled: root.size = Vector2i(1280,720)
	var folder := "res://evidence/roadside-parking-world-layout-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var count := 0
	for region_id in ["harbor","mountain"]:
		var state := STATE.new()
		var intro: Dictionary = state.intro.snapshot()
		intro.phase = "complete"
		intro.location_id = "harbor_street"
		intro.inventory = {}
		intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
		_check(state.intro.restore_snapshot(intro),region_id+": isolated intro")
		state.set_location(region_id,"")
		state.world_state.time = .45
		var spawn := Vector3(145,.12,151) if region_id=="harbor" else Vector3(650,.12,-287)
		state.world_state.pedestrian = {"region":region_id,"position":[spawn.x,spawn.y,spawn.z]}
		var store := STORE.new()
		store.path = folder.path_join(region_id+".json")
		_check(store.save(state)==OK,region_id+": isolated save fixture")
		var world = load("res://Main.tscn").instantiate()
		world.set_meta("skip_arrival",true)
		world.set_meta("menu_save_path",store.path)
		root.add_child(world)
		for index in 2400:
			await physics_frame
			if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
		var ready: bool = world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled
		_check(ready,region_id+": Main startup settled")
		if not ready:
			world.queue_free()
			await physics_frame
			continue
		world.player.controlled_automatically = true
		world.player.automatic_direction = Vector3.ZERO
		world.session.set_process_input(false)
		world.driving.set_process_unhandled_input(false)
		world.camera.set_process_unhandled_input(false)
		var director = world.get_node_or_null("RoadsideParking")
		if director!=null:
			director.set_physics_process(false)
			director.reset()
		var region = world.production.regions[region_id]
		var sites := LAYOUT.sites(region)
		_check(sites.size()>=2,region_id+": at least two safe pull-offs")
		for site: Dictionary in sites:
			world.player.teleport(site.explore_position+site.forward*12.0+Vector3.UP*.2)
			region.set_focus(site.position)
			for dx in [-20.0,0.0,20.0]:
				for dz in [-20.0,0.0,20.0]:
					region._ensure_chunk(region._cell(site.position+Vector3(dx,0,dz)))
			var transit = world.get_node_or_null("UrbanTransitPresentation")
			if transit!=null: transit.refresh()
			await physics_frame
			await physics_frame
			for slot: Dictionary in site.slots:
				count += 1
				var label: String = site.id+"/"+str(slot.id)
				var car := BoxShape3D.new()
				car.size = Vector3(2.1,1.4,4.7)
				_check(_sweep_clear(car,.7,slot.lane_position,slot.position,slot.yaw),label+": Main lane to bay")
				_check(_sweep_clear(car,.7,slot.position,slot.lane_position,slot.yaw),label+": Main bay to lane")
				_check(_sweep_clear(car,.7,slot.position,slot.departure,slot.yaw),label+": Main departure")
				var person := CapsuleShape3D.new()
				person.radius = .3
				person.height = 1.7
				var door: Vector3 = slot.position+site.outward*1.35
				_check(_sweep_clear(person,.85,door,slot.explore_position,0),label+": Main dismount/exploration")
				_check(_sweep_clear(person,.85,slot.explore_position,door,0),label+": Main return")
				for point: Vector3 in [slot.position,door,slot.explore_position]:
					var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point+Vector3.DOWN,1)
					var hit := root.world_3d.direct_space_state.intersect_ray(ray)
					_check(not hit.is_empty(),label+": Main ground support")
					if not hit.is_empty(): _check(absf(hit.position.y-LAYOUT.SURFACE_Y)<.08,label+": no buried or raised surface")
				print("PARKING_WORLD_SLOT ",label," at ",slot.position," checked")
			if capture_enabled: await _capture_site(world,site,folder)
		world.queue_free()
		for index in 3: await physics_frame
	for failure in failures: push_error(failure)
	var report := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"slots":count,"failures":failures,"captures":capture_rows,
		"rendered_capture":capture_enabled,"performance_certified":false},"\t"))
	print("ROADSIDE_PARKING_WORLD_LAYOUT ","PASS" if failures.is_empty() else "FAIL"," slots=",count," failures=",failures.size()," output=",folder)
	quit(0 if failures.is_empty() else 1)

func _capture_site(world: Node3D,site: Dictionary,folder: String) -> void:
	var camera: Camera3D = world.camera
	var previous := {"target":camera.target,"locked":camera.locked,"size":camera.size,"target_size":camera.target_size,
		"focus":camera.focus,"initialized":camera.initialized,"transform":camera.global_transform,"offset":camera.offset,
		"heading":camera.heading,"processing":camera.is_processing()}
	var target := Node3D.new()
	world.add_child(target)
	target.global_position = site.position
	# Productive exterior camera and pitch; only hold its framing for the two
	# completed submissions so a prior site's GPU frame cannot be captured.
	camera.target = target
	camera.locked = true
	camera.set_process(false)
	camera.size = 24.0
	camera.target_size = 24.0
	camera.focus = site.position
	camera.offset = preload("res://scripts/CameraRig.gd").EXTERIOR_OFFSET
	camera.heading = 0.0
	camera.initialized = true
	camera.global_position = camera.focus+camera.offset
	camera.look_at(camera.focus)
	for submission in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	var path := folder.path_join(str(site.id)+".png")
	_check(root.get_texture().get_image().save_png(path)==OK,"capture all-site "+str(site.id))
	var row := {"site":site.id,"slots":site.slots.size(),"position":str(site.position),"file":path,
		"camera_size":camera.size,"t_ms":Time.get_ticks_msec(),"viewport":[root.size.x,root.size.y]}
	capture_rows.append(row)
	print("PARKING_WORLD_CAPTURE ",JSON.stringify(row))
	camera.target = previous.target
	camera.locked = previous.locked
	camera.size = previous.size
	camera.target_size = previous.target_size
	camera.focus = previous.focus
	camera.initialized = previous.initialized
	camera.offset = previous.offset
	camera.heading = previous.heading
	camera.global_transform = previous.transform
	camera.set_process(previous.processing)
	target.free()
