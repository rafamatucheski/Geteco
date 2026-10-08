extends SceneTree
## Carregamento frio no espaço liberado pelo baú, com os dois recibos existentes.
var failures: Array[String]=[]
var world
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var state=preload("res://runtime/GameState.gd").new()
	var intro: Dictionary=state.intro.snapshot()
	intro.phase="complete"; intro.location_id="harbor_street"; intro.inventory={}
	intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	check(state.intro.restore_snapshot(intro),"introdução isolada válida")
	state.set_location("mountain")
	var at:=preload("res://world/places/PlaceCatalog.gd")._at(Vector2(5450,-1150),"mountain")+Vector3(.55,.25,-7.35)
	for reward in [{"id":"mountain_cargo_plane_treasure_01","kind":"cash","amount":1800},{"id":"mountain_cargo_plane_smg_01","kind":"weapon","item":"smg","amount":1,"ammo":20}]:
		check(state.economy.grant_world_reward(reward).ok,"recompensa autorada registrada")
		state.world_state.rewards.append(reward.id)
	state.world_state.pedestrian={"region":"mountain","position":[at.x,at.y,at.z]}
	var folder: String="res://evidence/cargo-plane-restore-%d"%OS.get_process_id()
	var store=preload("res://runtime/SaveStore.gd").new()
	store.path=folder.path_join("checkpoint.json")
	check(store.save(state)==OK,"checkpoint coletado isolado válido")
	if not failures.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",store.path)
	root.add_child(world); current_scene=world
	var began:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<120000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session!=null and world.session.ready_for_play and world.production.loaded_save,"Main carregou checkpoint coletado")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	for i in 8: await physics_frame
	check(Vector2(world.player.global_position.x-at.x,world.player.global_position.z-at.z).length()<.15,"save restaura Dante no antigo espaço do baú sem fallback")
	check(world.player.is_on_floor() and absf(world.player.global_position.y-.21)<.12,"carga fria apoia Dante no deck, sem nascer sobre baú")
	var found_plane:=false
	for source in get_nodes_in_group("native_world_rewards"):
		if source.get_script().resource_path!="res://world/places/CargoPlaneNative.gd": continue
		found_plane=true
		check(source._treasure_solid.collision_layer==0,"baú coletado não bloqueia admissão inicial")
		for point in source.reward_points: check(not point.visual.visible,"item coletado permanece oculto na carga fria")
	check(found_plane,"avião real disponível no checkpoint restaurado")
	check(world.session.state.economy.balance==1800 and world.session.state.owns_weapon("smg"),"carga fria preserva recompensas sem duplicar")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("restored.png"))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"expected":str(at),"actual":str(world.player.global_position)},"\t"))
	print("CARGO_PLANE_RESTORE ","PASS" if failures.is_empty() else "FAIL"," ",folder," ",failures)
	world.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
