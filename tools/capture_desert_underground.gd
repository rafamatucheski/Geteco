extends SceneTree
## Capturas das entradas subterrâneas do deserto: a estrutura externa (fechada e aberta) e a sala.
## Rodar: -- --no-save only=<id>
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const UNDER := preload("res://world/desert/underground/DesertUnderground.gd")
func _initialize() -> void: _run.call_deferred()
func shot(name: String) -> void:
	await process_frame; await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/desert-underground/%s.png" % name))
func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="): only = a.trim_prefix("only=")
	var id := only if only != "" else UNDER.ids()[0]
	var definition := PLACES.get_definition(id)
	var entry: Vector3 = definition.entry_position
	var snapshot := FIXTURE.full_snapshot(entry + Vector3(0, 0.08, 3.0), true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region": "desert", "position": [entry.x, 0.08, entry.z + 3.0]}
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("desert-underground-cap-" + id), "save.json", snapshot)
	var world = load("res://Main.tscn").instantiate(); world.set_meta("menu_save_path", path); root.add_child(world); current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true; world.player.automatic_direction = Vector3.ZERO
	var session = world.session
	world.production.region.set_focus(entry); world.production.region.prepare_collision_at(entry)
	for i in 30: await physics_frame
	world.player.teleport(entry + Vector3(-1.4, 0.08, 1.6))
	for i in 90: await physics_frame
	await shot(id + "_rua")
	var hatch = session._find_sewer_hatch(id)
	if is_instance_valid(hatch): hatch.set_open_amount(1.0)
	for i in 20: await physics_frame
	await shot(id + "_aberta")
	if is_instance_valid(hatch): hatch.set_open_amount(0.0)
	await session.enter_place(id, false, id)
	for i in 90: await physics_frame
	await shot(id + "_sala")
	quit()
