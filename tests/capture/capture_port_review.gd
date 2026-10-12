extends SceneTree
## Captura renderizada (não headless) do porto: contêineres, guindastes e água.
## Rodar com --no-save. Saída em res://evidence/port-review-20261012/.
const OUTPUT := "res://evidence/port-review-20261012/"
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(3)
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
	for i in 1500:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var weather = world.session.weather
	weather.weather_state = 0
	weather.weather_timer = 99999.0
	weather.time_of_day = .45
	var spots: Dictionary = {}
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--at="):
			var p := a.substr(5).split(",")
			spots["at%d_%d" % [int(float(p[0])), int(float(p[1]))]] = Vector3(float(p[0]), .2, float(p[1]))
	if spots.is_empty():
		# Sem coordenada: percorre os contêineres que o mundo já conhece.
		var probe := Vector3(262, .2, 250)
		spots["probe"] = probe
	for label in spots:
		world.player.teleport(spots[label])
		world.session.controller.region.set_focus(spots[label])
		await frames(240)
		var nodes := get_nodes_in_group("lootable_port_containers")
		print("CONTAINERS ", nodes.size())
		if nodes.size() > 0 and label == "probe":
			var c: Node3D = nodes[0]
			world.player.teleport(c.global_position + Vector3(0, .2, 12))
			world.session.controller.region.set_focus(c.global_position)
			await frames(240)
		await shot(label + "_dia")
	print("CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit(0)
