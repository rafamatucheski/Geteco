extends "res://tests/measure/measure_desert.gd"
## Mesmo Main renderizado e checkpoint isolado, antes/depois da política de população.
var failures: Array[String]=[]
func measure(id: String) -> void:
	if "--functional-only" not in OS.get_cmdline_user_args():
		await super.measure(id)
		return
	await create_timer(8).timeout
	reports.append({"id":id,"people":world.people.size(),"vehicles":world.production.vehicles.size(),"performance":"not measured: functional run"})
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func check(ok: bool, label: String) -> void:
	print("DESERT_POPULATION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or ("--benchmark" not in OS.get_cmdline_user_args() and "--functional-only" not in OS.get_cmdline_user_args()):
		quit(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-population")
	fingerprint=source_fingerprint()
	var at:=Vector3(335,.08,-1100)
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path:
		quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	for setup in [
		{"id":"empty-highway","point":at},
		{"id":"santa-lua","point":Vector3(-528,.08,-842)},
		{"id":"town","point":Vector3(-185,.08,-890)},
		{"id":"truckstop","point":Vector3(303,.08,-768)},
	]:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		await physics_frame
		world.player.teleport(setup.point)
		await create_timer(15).timeout
		await measure(setup.id)
		var actors: Array=[]
		for actor in world.people:
			if is_instance_valid(actor): actors.append({"position":str(actor.global_position),"slot":actor.get_meta("desert_social_slot",-1),"route":str(actor.route)})
		reports[-1].actors=actors
		reports[-1].ambient_cars=world.production._ambient_traffic_count()
		if "--verify-population" in OS.get_cmdline_user_args():
			check(actors.is_empty() if setup.id=="empty-highway" else not actors.is_empty(),"population belongs to inhabited places: "+setup.id)
			var used: Dictionary={}
			for actor in world.people:
				if not is_instance_valid(actor): continue
				var slot: int=actor.get_meta("desert_social_slot",-1)
				# Os clientes autorais existentes das lojas e os frentistas compartilham pessoas.
				# Eles são preservados de propósito, fora do novo registro de vagas.
				if slot<0:
					check(actor.has_meta("desert_routine") or actor.has_meta("roadside_visitor"),"existing purposeful resident is preserved")
					continue
				check(slot>=0 and not used.has(slot),"authored slot is unique")
				used[slot]=true
				check(not world.production._on_carriageway(actor.global_position),"resident stays off traffic lanes")
				check(actor.is_on_floor() and not actor.dead,"resident has physical ground support")
				var query:=PhysicsShapeQueryParameters3D.new()
				var body:=CapsuleShape3D.new()
				body.radius=.29; body.height=1.5
				query.shape=body
				query.collision_mask=1
				query.transform=Transform3D(Basis.IDENTITY,actor.global_position+Vector3.UP*.95)
				check(world.get_world_3d().direct_space_state.intersect_shape(query,8).is_empty(),"resident body clears solid furniture")
			if not world.people.is_empty():
				var actor=world.people[0]
				world.player.teleport(actor.global_position+Vector3(3,.08,3))
				await create_timer(2).timeout
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(setup.id+"-residents.png"))
	var social: Array=world.people.filter(func(actor): return is_instance_valid(actor) and actor.has_meta("desert_social_slot"))
	if "--verify-population" in OS.get_cmdline_user_args() and not social.is_empty():
		var resident=social[0]
		var home: Vector3=resident.route[0]
		# Diagnostic injection through the real gameplay signal; no save mutation.
		world.gameplay.explosion_occurred.emit(resident.global_position+Vector3(4,0,0),20.0,null)
		await create_timer(.5).timeout
		check(resident.controlled_automatically,"danger can interrupt social routine")
		check(resident.person.activity!="talk","conversation yields to danger")
		await create_timer(28).timeout
		check(not resident.controlled_automatically,"danger controller releases resident")
		check(resident.route[0]==home,"recovery retains the inhabited destination")
		world.player.teleport(Vector3(335,.08,-1100))
		world.production.region.set_focus(world.player.global_position)
		await create_timer(3).timeout
		check(world.people.is_empty(),"leaving settlements cleans up residents without highway replenishment")
	var valid:=fingerprint==source_fingerprint(fingerprint)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"valid":valid,"failures":failures,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"scenarios":reports},"\t"))
	print("DESERT_POPULATION_REPORT ",output," stable=",valid)
	quit(0 if valid and failures.is_empty() else 1)
