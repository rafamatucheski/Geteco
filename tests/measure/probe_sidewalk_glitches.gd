extends "res://tests/capture/capture_lighting_glitches.gd"
## One-variable rendered diagnostics. No persistent runtime mutation or saves.
const SURFACE := preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
var snapshots: Array = []

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	output_dir = "res://evidence/sidewalk-glitches/probe"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): output_dir += "-"+arg.trim_prefix("--variant=").validate_filename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session!=null and world.session.weather!=null: break
	if world.session==null or world.session.weather==null: quit(1); return
	world.player.controlled_automatically=true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	var reference := "--reference-framing" in OS.get_cmdline_user_args()
	var anchor := Vector3(137.5,.08,89 if reference else 105)
	await move_to(anchor,0,14 if reference else 26,true)
	world.session.weather.time_of_day=.567 if reference else .55
	world.session.weather.weather_state=3
	world.session.weather.weather_timer=10000
	world.session.weather._update()
	world.session.weather.set_process(false)
	await create_timer(2).timeout
	await capture(output_dir+"/01-normal.png")
	world.production.sun.shadow_enabled=false
	await create_timer(.2).timeout
	await capture(output_dir+"/02-no-sun-shadows.png")
	world.production.sun.shadow_enabled=true
	world.production.environment.environment.fog_enabled=false
	await create_timer(.2).timeout
	await capture(output_dir+"/03-no-fog.png")
	world.production.environment.environment.fog_enabled=true
	var targets: Array = []
	for node in world.production.region.find_children("HarborSurface_*","MeshInstance3D",true,false):
		targets.append(node)
		var mat: StandardMaterial3D = node.mesh.surface_get_material(0).duplicate()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override=mat
	await create_timer(.2).timeout
	await capture(output_dir+"/04-unshaded-surfaces.png")
	for node in targets: node.material_override=null
	for i in 8:
		world.player.teleport(anchor+Vector3(0,0,i*.18))
		await create_timer(.15).timeout
		await capture(output_dir+"/motion-%02d.png"%i)
	# Record authored overlaps, independently of shadows or shader output.
	var factory = SURFACE.new()
	factory.configure()
	var overlaps: Array = []
	for i in factory._surfaces.size():
		for j in range(i+1,factory._surfaces.size()):
			var a: Rect2=factory._surfaces[i].rect
			var b: Rect2=factory._surfaces[j].rect
			var area := a.intersection(b)
			if area.has_area(): overlaps.append({"a":i,"b":j,"rect":str(area),"area_m2":area.get_area()})
	var file=FileAccess.open(output_dir+"/overlaps.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"count":overlaps.size(),"overlaps":overlaps},"\t"))
	file.close()
	print("SIDEWALK_PROBE overlaps=",overlaps.size()," surfaces=",targets.size())
	world.queue_free()
	await process_frame
	quit()
