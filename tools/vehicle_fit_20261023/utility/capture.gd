extends SceneTree
## Capturas de câmera fixa da geometria de produção ou dos candidatos revisados.
const FLEET=preload("res://runtime/FleetCatalog.gd")
const IDS=["ranch_pickup","ranch_single","nimbus_minivan","courier_van","boxrunner","mare_microvan","toco_minitruck"]
const OUT="res://artifacts/vehicle-fit-20261023/utility"
var candidate:=false
func _initialize()->void: run.call_deferred()
func run()->void:
	if DisplayServer.get_name()=="headless": quit(2); return
	candidate="--candidate" in OS.get_cmdline_user_args()
	var ids:Array=[]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids=Array(arg.trim_prefix("--ids=").split(","))
	if ids.is_empty(): ids=IDS
	var folder:=OUT+("/after" if candidate else "/before")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT+"/originals"))
	root.size=Vector2i(1280,800)
	Engine.max_fps=60
	var stage:=Node3D.new();root.add_child(stage)
	var we:=WorldEnvironment.new();we.environment=Environment.new()
	we.environment.background_mode=Environment.BG_COLOR
	we.environment.background_color=Color("86969e")
	we.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color=Color("c4d4de")
	we.environment.ambient_light_energy=.65
	we.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	stage.add_child(we)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_color=Color("ffe2b8");sun.light_energy=1.6;sun.shadow_enabled=true;stage.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);ground.mesh=plane
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("545c60");mat.roughness=.88;ground.material_override=mat;stage.add_child(ground)
	var camera:=Camera3D.new();camera.fov=34;camera.near=.05;stage.add_child(camera);camera.make_current()
	for id:String in ids:
		var path:=OUT+"/candidates/"+id+".scn"
		if candidate and not FileAccess.file_exists(path): continue
		var model:Node3D=(load(path) as PackedScene).instantiate() if candidate else FLEET.create(id)
		if model==null:continue
		if not candidate and not FileAccess.file_exists(OUT+"/originals/"+id+".scn"):
			for child in model.find_children("*","",true,false):child.owner=model
			var packed:=PackedScene.new();packed.pack(model)
			ResourceSaver.save(packed,OUT+"/originals/"+id+".scn",ResourceSaver.FLAG_BUNDLE_RESOURCES)
		stage.add_child(model)
		var spec:Dictionary=FLEET.spec(id)
		var paint:=preload("res://runtime/VehiclePaint.gd").new();paint.bind(model,id)
		var palette:Array=spec.get("colors",[])
		if not palette.is_empty():paint.apply(Color.html(str(palette[0])))
		var size:Array=spec.get("bounds_size",[2.,1.5,4.8])
		var fit:float=maxf(float(size[2])/4.8,float(size[1])/1.6)
		var target:=Vector3(0,float(size[1])*.43,0)
		var views:={"front":Vector3(-5.7,3.,-6.7),"rear":Vector3(5.7,2.9,6.7),"side":Vector3(8.5,1.8,0),"top":Vector3(.01,10,.15),"cab_rear":Vector3(3.8,2.4,4.5)}
		for view:String in views:
			camera.position=views[view]*fit;camera.look_at(target)
			for frame in 6:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder+"/"+id+"-"+view+".png"))
		print("UTILITY_CAPTURE ",id," ",preload("res://tools/fleet_fixups/FleetBatchMesh.gd").counts(model))
		model.free();await process_frame
	stage.free();quit()
