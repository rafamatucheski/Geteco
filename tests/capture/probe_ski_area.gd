extends SceneTree
## Sonda visual da área de esqui para escolher onde fica a saída do forte.
## Uso: --script res://tests/capture/probe_ski_area.gd -- --no-save out=res://evidence/... x,z x,z ...
## Coordenadas em unidades da serra (as mesmas de MountainProgression.COURSES).
const OFFSET := Vector2(4300,-4960)
var world
var output := "res://evidence/fort-exit-20260928/probe"

func _initialize() -> void:
	run.call_deferred()

func shot(id: String) -> void:
	for _frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+"/"+id+".png"))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var points: Array[Vector2] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("out="): output = argument.trim_prefix("out=")
		elif "," in argument and not argument.begins_with("out="):
			var parts := argument.split(",")
			points.append(Vector2(float(parts[0]),float(parts[1])))
	root.size = Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 420:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	for _frame in 120: await process_frame
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	if is_instance_valid(world.session.world.hud): world.session.world.hud.hide()
	world.production.travel("mountain")
	for _frame in 300: await physics_frame
	var index := 0
	for point in points:
		var global := (point+OFFSET)/16.0
		var height: float = world.production.region.terrain.surface_height_at(global) if world.production.region.get("terrain") != null else 0.0
		world.player.teleport(Vector3(global.x,height+.5,global.y))
		print("PROBE ",index," mountain=",point," world=",global," height=",height)
		for _frame in 90: await physics_frame
		await shot("p%02d"%index)
		index += 1
	quit(0)
