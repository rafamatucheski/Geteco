extends SceneTree
## Capturas dos bueiros novos: a tampa na calçada e a sala. Rodar: -- --no-save --skip-arrival [only=id]
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
func _initialize() -> void: _run.call_deferred()
func shot(name: String) -> void:
	await process_frame; await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/sewer-network/%s.png" % name))
func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="): only = a.trim_prefix("only=")
	var world = load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival", true); root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	for id in SEWERS.extra_ids():
		if only != "" and id != only: continue
		var definition := PLACES.get_definition(id)
		session.controller.region.set_focus(definition.entry_position)
		world.player.teleport(definition.entry_position + Vector3(-1.2, 0.08, 1.0))
		for i in 60: await physics_frame
		await shot(id + "_rua")
		await session.enter_place(id, false, id)
		for i in 90: await physics_frame
		await shot(id + "_sala")
		await session.leave_place()
		for i in 40: await physics_frame
	quit()
