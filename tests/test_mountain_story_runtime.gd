extends SceneTree
## Main real, avião/caverna nativos e movimento de ator. O posicionamento inicial na região e
## a entrada na sala são preparação da fixture, não prova da rota inteira do lago à caverna.
## Rode depois do patch de integração compartilhado com .NET e diretórios de dados de usuário isolados.
## Isto confere funcionalidade/física; não faz afirmação visual nem de FPS.
const STORY := preload("res://activities/mountain_story/MountainStory.gd")
const PROGRESS := preload("res://systems/campaign/MountainStoryProgress.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
var world
var story
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("MOUNTAIN_STORY_RUNTIME ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func walk(target: Vector3) -> bool:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < 12000:
		var delta: Vector3 = target-world.player.global_position
		delta.y = 0
		if delta.length() < .14:
			world.player.automatic_direction = Vector3.ZERO
			await frames(3)
			return world.player.is_on_floor()
		world.player.automatic_direction = delta.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	print("MOUNTAIN_STORY_WALK_BLOCKED position=",world.player.global_position," target=",target)
	return false

func finish_dialogue() -> void:
	for index in 12:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
		await process_frame
	await frames(3)

func discover(event: String) -> bool:
	var before: Dictionary = story.snapshot()
	check(story.nearest_action().get("target","") == event,"physical approach offers "+event)
	if not story.perform(event):
		check(false,"start dialogue "+event)
		return false
	check(story.busy() and not story.save_block_reason().is_empty(),"unfinished reading blocks checkpoint save")
	check(story.snapshot() == before,"opening the conversation alone does not claim "+event)
	await finish_dialogue()
	check(story.snapshot().events.has(event),"finishing dialogue records "+event)
	check(not story.perform(event),"completed evidence cannot be claimed twice: "+event)
	return story.snapshot().events.has(event)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save --skip-arrival and isolated user-data directories.")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for index in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"real .NET Main session ready")
	if not failures.is_empty(): await finish(); return
	check(world.production.no_save,"fixture cannot overwrite personal saves")
	var session = world.session
	for candidate in world.find_children("MountainStory","",true,false):
		if candidate.get_script() == STORY: story = candidate; break
	check(is_instance_valid(story),"production aggregate installed the actual mountain story controller")
	if not failures.is_empty(): await finish(); return
	# Fixture: só a introdução concluída; o coordenador da montanha exige isso para iniciar.
	var intro: Dictionary = session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(session.state.intro.restore_snapshot(intro),"fixture completes only the introduction")
	check(story.restore_snapshot(PROGRESS.fresh_snapshot()),"isolated fixture starts with fresh mountain discoveries")
	check(world.production.travel("mountain"),"real mountain region transition requested")
	for index in 900:
		await physics_frame
		if not world.production.travel_busy: break
	check(session.state.region_id == "mountain" and not world.production.travel_busy,"mountain transition completes")
	if not failures.is_empty(): await finish(); return
	var plane := DEFINITIONS.at(Vector2(5450,-1150),"mountain")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.0
	world.production.region.set_focus(plane)
	world.player.set_physics_process(false)
	world.player.teleport(plane+Vector3(0,.3,9.0))
	await frames(90)
	world.player.set_physics_process(true)
	await frames(45)
	check(is_instance_valid(story._plane) and is_instance_valid(story._plane_props),"evidence attaches to the streamed production plane")
	if not failures.is_empty(): await finish(); return
	var props_id: int = story._plane_props.get_instance_id()
	await frames(65)
	check(story._plane_props.get_instance_id() == props_id,"polling does not recreate or duplicate evidence")
	check(await walk(plane+Vector3(.1,0,3.5)),"real actor walks up the original ramp to the cargo")
	if not failures.is_empty(): await finish(); return
	var previous_health: float = world.gameplay.health
	world.gameplay.health = 0
	check(story.nearest_action().is_empty() and not story.perform("cargo_identified"),"dead player cannot investigate")
	world.gameplay.health = previous_health
	session.state.region_id = "harbor"
	check(story.nearest_action().is_empty(),"same coordinates in another region cannot investigate")
	session.state.region_id = "mountain"
	world.driving.occupied = true
	check(story.nearest_action().is_empty(),"seated player cannot investigate the cargo")
	world.driving.occupied = false
	# Obstrução de física real no limite da interação, não um raio simulado.
	var obstruction := StaticBody3D.new()
	obstruction.collision_layer = 1
	obstruction.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,2,.06)
	collider.shape = box
	obstruction.add_child(collider)
	world.add_child(obstruction)
	obstruction.global_position = plane+Vector3(0,1.0,3.07)
	await frames(3)
	check(story.nearest_action().is_empty(),"a physical wall blocks reading despite short distance")
	obstruction.queue_free()
	await frames(3)
	check(story.perform("cargo_identified"),"first reading starts")
	var abandoned: Callable = session.dialogue_done
	story.cancel_attempt()
	session.dialogue_done = Callable()
	session.close_menu()
	abandoned.call()
	check(story.snapshot().events.is_empty() and not story.busy(),"cancel invalidates stale dialogue completion without erasing prior discoveries")
	check(story.perform("cargo_identified"),"reading can be restarted after interruption")
	session.close_menu()
	await frames(35)
	check(not story.busy() and story.snapshot().events.is_empty(),"Escape-style dialogue dismissal releases attempt without claiming discovery")
	if not await discover("cargo_identified"): await finish(); return
	check(await walk(plane+Vector3(.5,0,-4.35)),"real actor traverses the free cargo aisle to the manifest")
	if not failures.is_empty(): await finish(); return
	var rewards_before: Array = session.state.world_state.rewards.duplicate()
	var wallet_before: Dictionary = session.state.economy.snapshot()
	if not await discover("cargo_manifest"): await finish(); return
	check(session.state.world_state.rewards == rewards_before and session.state.economy.snapshot() == wallet_before,"manifest does not duplicate plane cash or SMG")
	check(await walk(plane+Vector3(.45,0,9.0)),"real actor leaves the plane via its existing aisle and ramp")
	if not failures.is_empty(): await finish(); return
	check(await session.enter_place(PROGRESS.CAVE,false),"production room transition admits player to Caverna da Queda")
	await frames(40)
	check(session.state.place_id == PROGRESS.CAVE and is_instance_valid(story._cave_props),"cave evidence attaches to current native room")
	if not failures.is_empty(): await finish(); return
	var room = session.room
	world.player.controlled_automatically = true
	check(await walk(room.to_global(Vector3(-1.0,0,3.15))),"walk from cave spawn into its open center")
	check(await walk(room.to_global(Vector3(-2.45,0,2.75))),"approach expedition map without crossing supply solids")
	if not failures.is_empty(): await finish(); return
	if not await discover("cave_shelter"): await finish(); return
	check(await walk(room.to_global(Vector3(-.85,0,1.75))),"leave map on the clear side of lantern")
	check(await walk(room.to_global(Vector3(-.85,0,-1.75))),"walk deeper through cave's physical central corridor")
	if not failures.is_empty(): await finish(); return
	var collected_before: Array = session.state.economy.snapshot().collectibles.duplicate()
	if not await discover("vicente_note"): await finish(); return
	check(story.snapshot().completed == ["cobra_cargo","vicente_trail"],"both mountain side quests complete")
	check(session.state.economy.snapshot().collectibles == collected_before,"Vicente's clue is separate from all three skiing expedition collectibles")
	var completed: Dictionary = story.snapshot()
	check(story.restore_snapshot(JSON.parse_string(JSON.stringify(completed))),"controller restores completed discovery and conversation receipts")
	check(story.objective().is_empty() and story.nearest_action().is_empty(),"restored completion neither prompts nor repeats a reward")
	check(await session.leave_place(),"existing cave return restores exterior")
	await frames(40)
	check(not is_instance_valid(story._cave_props),"interior departure frees quest-owned props")
	check(await session.enter_place(PROGRESS.CAVE,false),"cave reentry uses the existing admission path")
	await frames(40)
	check(is_instance_valid(story._cave_props) and story.snapshot() == completed,"reentry streams one evidence set and preserves completion")
	await session.leave_place()
	check(world.production.travel("harbor"),"return to Harbor")
	for index in 900:
		await physics_frame
		if not world.production.travel_busy: break
	await frames(40)
	check(not is_instance_valid(story._plane_props) and not is_instance_valid(story._cave_props),"region departure releases all story presentation")
	check(story.objective().is_empty() and story.snapshot() == completed,"Harbor objectives and completed mountain discoveries remain independent")
	await finish()

func finish() -> void:
	print("MOUNTAIN_STORY_RUNTIME_RESULT checks=%d failures=%d" % [checks,failures.size()])
	if is_instance_valid(world):
		if is_instance_valid(story): story.cancel_attempt()
		world.queue_free()
		await frames(3)
	quit(0 if failures.is_empty() else 1)
