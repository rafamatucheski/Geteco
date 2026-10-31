extends SceneTree
## Cria um checkpoint autoral de início de capítulo; nunca substitui um slot ocupado.
## Rode com --publish para instalar depois da validação; senão grava só no temp.
const STATE = preload("res://runtime/GameState.gd")
const STORE = preload("res://runtime/SaveStore.gd")
const MISSIONS = preload("res://data/campaign/HarborMissions.gd")
const POLICY = preload("res://world/north_gateway/NorthGatewayPolicy.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var state = STATE.new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): fail("intro"); return
	var campaign: Dictionary = state.campaign.snapshot()
	for id in MISSIONS.ORDER:
		campaign.completed.append(id)
		campaign.pending_rewards[id] = int(MISSIONS.MISSIONS[id].reward)
		for flag in MISSIONS.MISSIONS[id].sets_flags: campaign.flags[flag] = true
	if not state.campaign.restore_snapshot(campaign): fail("campaign"); return
	for id in MISSIONS.ORDER:
		if not state.campaign.claim_reward(state.economy,id): fail("reward "+id); return
	state.campaign.complete_aftermath_call()
	var jessica: Dictionary = preload("res://systems/campaign/JessicaProgress.gd").fresh_snapshot()
	jessica.merge({"met":true,"bank_phase":"complete","bank_cycle":0,"haul_mask":7,
		"haul_receipt":"bank_haul:0:7","bank_complete":true,"conversations":["first_meeting","bank_debrief"]},true)
	state.world_state.jessica = jessica
	state.economy.grant_reward("bank_haul:0:7",15000)
	var story = preload("res://systems/campaign/HarborStory.gd")
	story.mark_opening(state.world_state)
	story.mark_maciota(state.world_state)
	story.record_brother_route(state.world_state,true)
	state.set_location("desert")
	state.checkpoint_id = "desert_motel"
	state.world_state.time = .40
	state.world_state.pedestrian = {"region":"desert","position":[-330,.1,-913]}
	state.grant_weapon("pistol")
	state.equip_weapon("fists")
	var snapshot: Dictionary = state.snapshot()
	if not STATE.new().restore_snapshot(snapshot) or not POLICY.campaign_completed(snapshot.campaign):
		fail("checkpoint validation"); return
	var store = STORE.new()
	store.path = OS.get_temp_dir().path_join("geteco-map2-%d-%d/save.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	if store.publish_import_snapshot(snapshot) != OK: fail("isolated publication"); return
	var restored = STATE.new()
	if not store.load_into(restored).get("ok",false): fail("reload"); return
	if JSON.parse_string(JSON.stringify(restored.snapshot())) != JSON.parse_string(JSON.stringify(snapshot)):
		fail("round trip"); return
	if store.publish_import_snapshot(snapshot) != ERR_ALREADY_EXISTS: fail("overwrite protection"); return
	print("MAP2_SAVE validated campaign, rewards, bridge, intro, JSON reload and overwrite protection: ",store.path)
	if "--preview" in OS.get_cmdline_user_args():
		create_timer(180).timeout.connect(func(): fail("scene timeout"))
		var world = load("res://Main.tscn").instantiate()
		world.set_meta("menu_save_path",store.path)
		root.add_child(world)
		current_scene = world
		while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled:
			await physics_frame
		for frame in 120: await physics_frame
		if world.session.state.region_id != "desert" or world.player.global_position.distance_to(Vector3(-330,.1,-913)) > 5:
			fail("scene spawn"); return
		if not world.session.position_clear(world.player.global_position): fail("spawn obstructed"); return
		if not POLICY.campaign_completed(world.session.state.campaign.snapshot()): fail("scene bridge"); return
		if not world.session.save_game() or STORE.read_valid(store.path).is_empty(): fail("scene save"); return
		print("MAP2_SAVE scene ready, spawn clear, campaign restored, gameplay save valid: ",world.player.global_position)
		await process_frame
		root.get_texture().get_image().save_png(store.path.get_base_dir().path_join("preview.png"))
		quit(); return
	if "--publish" in OS.get_cmdline_user_args():
		var launch = root.get_node("V2Launch")
		for row in launch.list_slots():
			if row.id == "progress" or row.exists: continue
			store.path = row.path
			if store.publish_import_snapshot(snapshot) != OK: fail("slot publication"); return
			print("MAP2_SAVE INSTALLED ",row.id," ",ProjectSettings.globalize_path(store.path))
			quit(); return
		fail("no empty slots"); return
	quit()

func fail(message: String) -> void:
	push_error("MAP2_SAVE "+message)
	quit(1)
