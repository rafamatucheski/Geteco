extends SceneTree
## Capturas do chão do porto para o antes/depois da camada única de chão (2026-10-13).
## Uso (com tela, nunca --headless): "$GODOT" --path . --script res://tests/capture/capture_harbor_ground_layers.gd -- --no-save --label=depois
## Antes: GETECO_GROUND_STACK=1 com --label=antes. Grava PNG em evidence/harbor-ground-layers/ (fora do Git).
const POINTS := {
	"cruzamento_oeste": Vector3(118.0, 0.0, 80.0),
	"rua_leste": Vector3(392.0, 0.0, 96.0),
	"porto_sul": Vector3(296.0, 0.0, 212.0),
}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var label := "medicao"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	var folder := "res://evidence/harbor-ground-layers"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for id in POINTS:
		var point: Vector3 = POINTS[id]
		world.player.teleport(point + Vector3.UP * .1)
		world.production.region.set_focus(point, true)
		# Streaming e acabamento fatiados terminarem antes do print.
		for frame in 240:
			await process_frame
			if world.production.region.is_streaming_idle() and frame > 60: break
		for frame in 20: await process_frame
		var image := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [folder, id, label]
		image.save_png(ProjectSettings.globalize_path(path))
		print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit(0)
