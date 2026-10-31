extends SceneTree
## Fotografa os assets salvos de verdade. Este showroom não certifica gameplay/FPS.
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
var batch := "passenger"
var variant := "before"
var selected := ""
var production := false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--batch="): batch=arg.trim_prefix("--batch=")
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=")
		if arg.begins_with("--ids="): selected=arg.trim_prefix("--ids=")
		if arg=="--production": production=true
	preload("res://runtime/RedesignedFleet.gd").enabled=variant!="before"
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(1280,800)
	Engine.max_fps=60
	var folder := "res://evidence/fleet-redesign-20261011/"+batch
	var ids: Array=[]
	if not selected.is_empty(): ids=Array(selected.split(","))
	elif batch in ["passenger","special"]:
		ids=(JSON.parse_string(FileAccess.get_file_as_string(folder+"/original-inventory.json")) as Dictionary).keys()
	elif batch=="utility":
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"/baseline.json"))
		ids=data.keys() if data is Dictionary else []
	elif batch=="service":
		ids=(JSON.parse_string(FileAccess.get_file_as_string(folder+"/report.json")) as Dictionary).vehicles.keys()
	var outdir := folder+"/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("86969e")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c4d4de")
	env.ambient_light_energy=.65
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	we.environment=env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_color=Color("ffe2b8")
	sun.light_energy=1.6
	sun.shadow_enabled=true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(200,200)
	ground.mesh=plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color("545c60")
	mat.roughness=.88
	ground.material_override=mat
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.fov=34
	camera.near=.05
	world.add_child(camera)
	camera.make_current()
	for id: String in ids:
		var path := "res://assets/fleet/redesigned/"+id+".scn"
		if variant=="before":
			path=folder+"/original/"+id+".scn"
			if batch=="utility": path=folder+"/"+id+"-before.scn"
			if batch=="service": path=folder+"/before/"+id+".scn"
		if not ResourceLoader.exists(path): print("PHOTO_MISSING ",path); continue
		var model: Node3D
		if production or (variant=="before" and id in ["metro_hatch","taxi_yellow"]):
			model=preload("res://runtime/FleetCatalog.gd").create(id)
		else: model=(load(path) as PackedScene).instantiate() as Node3D
		world.add_child(model)
		await process_frame
		var spec: Dictionary=preload("res://runtime/FleetCatalog.gd").spec(id)
		var paint := preload("res://runtime/VehiclePaint.gd").new()
		paint.bind(model,id)
		var palette: Array=spec.get("colors",[])
		if not palette.is_empty(): paint.apply(Color.html(str(palette[0])))
		var size: Array=spec.get("bounds_size",[2.0,1.5,4.8])
		var scale: float=maxf(float(size[2])/4.8,float(size[1])/1.6)
		var target := Vector3(0,float(size[1])*.43,0)
		for view in [{"id":"front","at":Vector3(-5.7,3.0,-6.7)},{"id":"rear","at":Vector3(5.7,2.9,6.7)}]:
			camera.position=view.at*scale
			camera.look_at(target)
			for frame in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(outdir+"/"+id+"-"+str(view.id)+".png")
		print("PHOTO ",variant," ",id," ",MESH.counts(model))
		model.free()
		await process_frame
	world.free()
	quit()
