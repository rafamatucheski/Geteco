extends SceneTree
## Real Main, isolated save; direct room admission tests presentation, not door traversal.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var folder := ""
var failures: Array[String] = []
var checks := 0
var before := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("INTERIOR_SEA ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("INTERIOR_SEA timeout"); quit(2))
	before = "--before" in OS.get_cmdline_user_args()
	folder = FIXTURE.output_dir("interior-sea-before" if before else "interior-sea-after")
	var snapshot := FIXTURE.full_snapshot(Vector3(0,.08,12), true)
	snapshot.place_id = "maciota"
	snapshot.checkpoint_id = "maciota"
	snapshot.campaign.aftermath = {"call_complete":true}
	var save_path := FIXTURE.write_fixture(folder, "save.json", snapshot)
	check(not save_path.is_empty(), "isolated interior save accepted")
	if save_path.is_empty(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	var session = world.session
	while session.is_transition_blocked(): await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var sea: Node3D = world.production.world_sea
	check(is_instance_valid(sea), "global sea exists")
	check(session.state.place_id == "maciota", "startup restores garage interior")
	check(sea.visible == before, "restored interior sea visibility")
	await photo("01-restored-garage")
	check(await session.leave_place(), "leave restored garage")
	check(sea.visible, "exit restores sea immediately")
	await photo("02-exterior")
	# Fixture ownership only; buying houses is outside this rendering regression.
	session.activities.residence.data.active_home = "westgate_garden"
	for id in ["westgate_garden", "harbor_hospital", "maciota"]:
		while session.is_transition_blocked() or world.player.input_locked: await physics_frame
		var entered: bool = await session.enter_place(id, false)
		check(entered, "admission " + id)
		if not entered: continue
		check(sea.visible == before, "isolated room sea visibility on admission " + id)
		check(session.position_clear(world.player.global_position + Vector3.UP * .04), "clear interior spawn " + id)
		await photo("03-" + id)
		await create_timer(.6).timeout
		check(sea.visible == before, "periodic atmosphere preserves visibility " + id)
		check(await session.leave_place(), "departure " + id)
		check(sea.visible, "sea restored on departure " + id)
	var result := {"checks":checks,"failures":failures,"baseline":before,"scope":"Main: saved garage startup, house/hospital/garage direct admission and departure. No door-route or performance certification."}
	FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("INTERIOR_SEA_RESULTS ", folder, " ", JSON.stringify(result))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
