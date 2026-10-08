extends SceneTree
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const ROOFS = preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd")
var world
var checks := 0
var failures: Array[String] = []
var folder := ""

func _initialize() -> void:
	create_timer(220).timeout.connect(func(): push_error("CAT_SESSION timeout"); quit(3))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CAT_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(count := 8) -> void:
	for _i in count: await physics_frame

func _at(point: Vector3) -> void:
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.camera.initialized = false
	await frames(50)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func body_clear(cat: CharacterBody3D) -> bool:
	# Admission has deliberate extra clearance; a moving body may touch a wall
	# within that margin. Verify every actual collision shape, including its nose.
	for shape in cat.get_children():
		if not shape is CollisionShape3D: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.collision_mask = 1
		var hits: Array = world.get_world_3d().direct_space_state.intersect_shape(query,4)
		if not hits.is_empty():
			print("CAT_OVERLAP ",cat.cat_id," ",cat.global_position," activity=",cat.activity," hits=",hits)
			return false
	return true

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	folder = FIXTURE.output_dir("cats-session")
	var fixture := FIXTURE.full_snapshot(Vector3(20,.08,16),false)
	# Explore after the garage intro, with no active mission or final-quest
	# aftermath dialogue. Both would legitimately block E and checkpoint saves.
	fixture.campaign = preload("res://systems/campaign/CampaignRuntime.gd").new().snapshot()
	var path := FIXTURE.write_fixture(folder,"save.json",fixture)
	world = load("res://Main.tscn").instantiate()
	if world.get_script() == null:
		world.free()
		push_error("CAT_SESSION Main did not compile; integration not executed")
		quit(2)
		return
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var session = world.session
	var runtime = session.cats
	var home = session.activities.residence
	check(runtime != null,"runtime integrado")
	if runtime == null: quit(1); return
	runtime.refresh()
	check(runtime.cats.is_empty(),"nenhum gato antes da casa")
	session.state.economy.grant_reward("cat_session_funds",100000)
	await _at(PLACES.get_definition("westgate_garden").entry_position+Vector3.UP*.08)
	check(home.buy("westgate_garden"),"compra libera gatos")
	await frames(30)
	for row in runtime.discoveries:
		if row.has("roof"):
			await _at(PLACES.get_definition(row.roof).entry_position+Vector3.UP*.08)
			check(await session.enter_place(row.roof,false),"entra no prédio do rooftop")
			await frames(30)
			session.service_roofs.update(.5)
			check(session.service_roofs.access_point.is_finite(),"escada real disponível")
			if not session.service_roofs.access_point.is_finite(): continue
			world.player.teleport(session.service_roofs.access_point+Vector3.UP*.04)
			await frames(5)
			check(await session.interact() and session.service_roofs.is_active(),"E sobe ao rooftop")
		else:
			await _at(row.point+Vector3(0,.1,1.0))
		runtime.refresh()
		await frames(12)
		check(runtime.cats.has(row.id),row.id+" aparece no local fixo "+row.site)
		if not runtime.cats.has(row.id):
			print("CAT_SITE_BLOCKED ",row.id," ",row.point," floor=",runtime.floor_point(row.point)," clear=",runtime.point_clear(row.point))
			for z in range(-8,9,2):
				for x in range(-8,9,2):
					var possible: Vector3 = runtime.floor_point(row.point+Vector3(x,0,z))
					if possible.is_finite() and runtime.point_clear(possible,.4) and session.position_clear(possible+Vector3(0,.05,1)): print("CAT_SITE_CANDIDATE ",row.id," ",possible)
			continue
		var cat: CharacterBody3D = runtime.cats[row.id]
		var near_point: Vector3 = cat.global_position+Vector3(0,.06,1.0)
		check(session.position_clear(near_point),row.id+" aproximação comporta Dante")
		world.player.teleport(near_point)
		await frames(5)
		check(session.nearest().get("id","") == "cat_adopt",row.id+" prompt por proximidade")
		await capture(row.id)
		check(await session.interact(),row.id+" E adota")
		if row.id == "cat_01": await capture("first-adoption")
		check(home.adopted_cats().has(row.id),row.id+" identidade persistida")
		check(not runtime.perform(row.id),row.id+" coleta repetida bloqueada")
		if row.has("roof"):
			world.player.teleport(session.service_roofs.roof.to_global(session.service_roofs.roof.stair_point())+Vector3.UP*.04)
			await frames(4)
			check(await session.interact() and not session.service_roofs.is_active(),"E desce rooftop")
			check(await session.leave_place(),"sai prédio rooftop")
	check(home.cat_count() == 10,"10/10 adotados")
	for id in ["westgate_garden","quayside_house","canal_north"]:
		await _at(PLACES.get_definition(id).entry_position+Vector3.UP*.08)
		if home.data.active_home != id: check(home.buy(id),"muda para "+id)
		await frames(40)
		check(runtime.residents.size()==home.cat_count(),id+" gatos no exterior")
		check(await session.enter_place(id,false),id+" entra em casa")
		await frames(45)
		world.player.teleport(session.room.interaction_points.save+Vector3.UP*.05)
		check(session.residence_services.perform("residence_services"),id+" escrivaninha funcional")
		session.close_menu()
		if id == "westgate_garden":
			for kind in ["bed","ball","scratcher"]:
				for _item in {"bed":10,"ball":3,"scratcher":2}[kind]:
					check(home.buy_cat_furniture(kind),"compra "+kind)
		await frames(60)
		check(runtime.residents.size()==home.cat_count(),id+" moradores interiores sem duplicação")
		check(runtime.furniture.size()==15,id+" todas as 15 compras presentes")
		for cat in runtime.residents:
			check(body_clear(cat),id+" "+cat.cat_id+" corpo em piso livre")
		await capture(id)
		# Production movement, not just static transforms. Two seconds also
		# exercises wandering/animation while furniture shapes are registered.
		await frames(180)
		for cat in runtime.residents:
			check(cat.global_position.y>session.room.global_position.y-.1,id+" "+cat.cat_id+" permanece apoiado")
		check(await session.leave_place(),id+" sai e recupera controle")
		await frames(30)
	# Write/read actual bytes at an isolated path; never touch personal saves.
	# The port discovery exercised a real trespass alert. Establish the calm
	# recovery fixture explicitly before verifying storage, not police evasion.
	if world.gameplay.stars > 0:
		check(not session.save_game(),"procura preserva bloqueio de save após adoção")
		world.gameplay.clear_wanted()
	world.production.no_save = false
	world.production.store.path = folder.path_join("adopted.json")
	check(await session.enter_place(home.data.active_home,false),"entra na casa antes de salvar")
	await frames(20)
	var saved: bool = session.save_game()
	check(saved,"save real isolado gravado")
	if not saved: print("CAT_SAVE_BLOCKED ",session.save_block_reason()," error=",session.last_save_error)
	var restored = preload("res://runtime/GameState.gd").new()
	var store = preload("res://runtime/SaveStore.gd").new()
	store.path = world.production.store.path
	check(store.load_into(restored).get("ok",false),"save real carregado")
	check(restored.world_state.get("activities",{}).get("home",{}).get("cats",{}).get("adopted",[]).size()==10,"dez gatos restaurados do disco")
	world.production.no_save = true
	print("CAT_SESSION_RESULT checks=",checks," failures=",failures.size()," ",failures," evidence=",folder)
	quit(0 if failures.is_empty() else 1)
