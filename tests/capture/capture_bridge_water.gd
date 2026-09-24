extends SceneTree
## Captura renderizada (Vulkan, não headless) da água sob a ponte Harbor–Mountain,
## de dia e à noite. Rodar com --no-save. Saída em res://evidence/bridge-water-0924/.
const OUTPUT := "res://evidence/bridge-water-0924/"
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var weather = world.session.weather
	weather.weather_state = 0
	weather.weather_timer = 99999.0
	var labels := {"a_conector": CONNECTION.HARBOR_CONNECTOR_X + 20.0, "b_ponte": (CONNECTION.SEAM.x + CONNECTION.BRIDGE_END_X) * .5}
	for label in labels:
		var point := Vector3(labels[label], .2, CONNECTION.CENTER_Z)
		world.player.teleport(point)
		world.session.controller.region.set_focus(point)
		weather.time_of_day = .45
		await frames(300)
		await shot(label + "_dia")
		weather.time_of_day = .95
		await frames(90)
		await shot(label + "_noite")
	print("CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit(0)
