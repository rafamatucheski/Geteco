extends SceneTree
## Captura a morte do jogador no jogo real. Argumento: variant=0 (clipe do Dante) ou variant=1 (UAL Death01).
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var variant := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("variant="): variant = a.trim_prefix("variant=").to_int()
	var world = load("res://Main.tscn").instantiate(); root.add_child(world); current_scene = world
	for f in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	for i in 40: await physics_frame
	var player = world.player
	player.on_player_death(variant)
	var n := 0
	for step in 5:
		for i in 18: await physics_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/game/morte_v%d_%d.png" % [variant, step]))
	quit()
