extends SceneTree
## Revisão próxima, fixa e pareada da produção ativa e dos candidatos offline.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ROOT := "res://artifacts/vehicle-fit-20261023/passenger"
const IDS := ["aurora_executive","beach_cabriolet","cobra_v8","metro_hatch","muscle_classic","nordic_estate","orbita_micro","porto_rosso","sedan_classic","sport_estate","station_wagon","surf_woody_wagon","taxi_yellow","union_sedan","vale_crossover","vertice_midengine"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var mode := "before"
	var steering:=0.0
	var ids: Array = IDS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--ids="): ids=Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--steer="): steering=float(arg.trim_prefix("--steer="))
	var output := ROOT+"/"+mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1200,800)
	Engine.max_fps=60
	var stage:=Node3D.new()
	root.add_child(stage)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("adb7bb")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("c1d0d8")
	env.environment.ambient_light_energy=.65
	stage.add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_color=Color("ffe2bd")
	sun.light_energy=1.4
	sun.shadow_enabled=true
	stage.add_child(sun)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(100,100)
	ground.mesh=plane
	var ground_mat:=StandardMaterial3D.new()
	ground_mat.albedo_color=Color("687477")
	ground_mat.roughness=.9
	ground.material_override=ground_mat
	stage.add_child(ground)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	stage.add_child(camera)
	for id: String in ids:
		var model: Node3D
		if mode=="before": model=FLEET.create(id)
		else:
			var packed:=load(ROOT+"/candidates/"+id+".scn") as PackedScene
			if packed==null: continue
			model=packed.instantiate() as Node3D
		if model==null: continue
		if steering!=0:
			for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				if not part.has_meta("wheel_center"): continue
				var center: Vector3=part.get_meta("wheel_center")
				if center.z<0:
					var basis:=Basis(Vector3.UP,steering)
					part.transform=Transform3D(basis,center-basis*center)
		stage.add_child(model)
		var spec:=FLEET.spec(id)
		var size: Array=spec.bounds_size
		var target:=Vector3(0,float(size[1])*.45,0)
		camera.size=maxf(float(size[2])*1.13,float(size[1])*2.7)
		for view in [{"name":"front","at":Vector3(-5,2.1,-6.8)},{"name":"rear","at":Vector3(5,2,6.8)},{"name":"side","at":Vector3(8,.7,0)},{"name":"top","at":Vector3(.01,10,.1)}]:
			camera.position=target+view.at
			camera.look_at(target)
			for frame in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+"/"+id+"-"+str(view.name)+".png"))
		model.free()
		await process_frame
		print("PASSENGER_PHOTO ",mode," ",id)
	stage.free()
	quit(0)
