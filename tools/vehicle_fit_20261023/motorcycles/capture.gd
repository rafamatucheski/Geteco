extends SceneTree
const IDS=["bike_sport","bike_cruiser","bike_urban"]
const ROOT="res://artifacts/vehicle-fit-20261023/motorcycles/"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var candidate: bool="--candidate" in OS.get_cmdline_user_args()
	var dest: String=ROOT+("after/" if candidate else "before/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	root.size=Vector2i(1100,700)
	var stage:=Node3D.new(); root.add_child(stage)
	var env:=WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("667985")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color("b5c4cc"); env.environment.ambient_light_energy=.65
	stage.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-35,0); sun.shadow_enabled=true; stage.add_child(sun)
	var floor_mesh:=MeshInstance3D.new(); var floor_plane:=PlaneMesh.new(); floor_plane.size=Vector2(30,30); floor_mesh.mesh=floor_plane
	var floor_mat:=StandardMaterial3D.new(); floor_mat.albedo_color=Color("3e484d"); floor_mesh.material_override=floor_mat; stage.add_child(floor_mesh)
	var camera:=Camera3D.new(); camera.fov=35; stage.add_child(camera)
	var info: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dest+"inspection.json")) if FileAccess.file_exists(dest+"inspection.json") else {}
	for id: String in IDS:
		var only: String=""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--only="): only=arg.trim_prefix("--only=")
		if not only.is_empty() and id!=only: continue
		var model: Node3D=(load(ROOT+id+".scn") as PackedScene).instantiate() if candidate else preload("res://runtime/FleetCatalog.gd").create(id)
		stage.add_child(model)
		var parts:={}
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.get_meta("motorcycle_rider",false): part.visible=false
			var surfaces:=[]
			for i in part.mesh.get_surface_count():
				surfaces.append({"role":preload("res://runtime/VehicleSurfaceRoles.gd").key(part,i),"bounds":str(part.transform*surface_bounds(part.mesh,i))})
			parts[str(part.name)]={"bounds":str(part.transform*part.mesh.get_aabb()),"meta":{},"surfaces":surfaces}
			for key in part.get_meta_list(): parts[str(part.name)].meta[str(key)]=str(part.get_meta(key))
		info[id]={"meta":{},"counts":preload("res://tools/fleet_fixups/FleetBatchMesh.gd").counts(model),"parts":parts}
		for key in model.get_meta_list(): info[id].meta[str(key)]=str(model.get_meta(key))
		var center:=Vector3(0,.65,0)
		var views:={"front_quarter":Vector3(-3.1,1.8,-4.4),"rear_quarter":Vector3(3.1,1.7,4.4),"side":Vector3(-4.6,1.05,.2),"front":Vector3(.0,1.15,-5.2),"rear":Vector3(.0,1.15,5.2),"top":Vector3(.05,5,.1)}
		for label: String in views:
			camera.position=views[label]; camera.look_at(center,Vector3.UP)
			for i in 7: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(dest+id+"_"+label+".png"))
		model.free()
	FileAccess.open(dest+"inspection.json",FileAccess.WRITE).store_string(JSON.stringify(info,"\t"))
	quit(0)
func surface_bounds(mesh: Mesh,i: int) -> AABB:
	var points: PackedVector3Array=mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	var box:=AABB(points[0],Vector3.ZERO)
	for p: Vector3 in points: box=box.expand(p)
	return box
