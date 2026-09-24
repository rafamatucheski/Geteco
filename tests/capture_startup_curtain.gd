extends SceneTree
## Quadros da abertura (Main, save real se existir), a cada ~0,1 s: nenhum deve
## mostrar o terreno cru antes da cortina sair.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var out := "res://evidence/startup-curtain-0922"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var world: Node = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 40:
		for f in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "/f%02d.png" % i))
	quit()
