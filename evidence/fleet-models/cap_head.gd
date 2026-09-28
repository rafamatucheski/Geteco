extends SceneTree
## Captura renderizada (Vulkan, não headless) de cada veículo da frota em quatro ângulos,
## para revisar a geometria (vidros, lanternas, proporções) sem entrar no jogo.
## Uso: --script res://tests/capture/capture_fleet_models.gd -- [id ...]. Saída em res://evidence/fleet-models/.
const OUTPUT := "res://evidence/fleet-models/"
const FLEET := preload("res://runtime/FleetCatalog.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(640,400)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.55,.6,.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7,.72,.78)
	env.environment.ambient_light_energy = .7
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,35,0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(40,40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(.32,.32,.33)
	ground.material_override = gm
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.fov = 40
	stage.add_child(camera)
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty(): ids = FLEET.all().keys()
	for id in ids:
		var model: Node3D = (load("res://evidence/fleet-models/head_%s.scn" % id) as PackedScene).instantiate()
		if model == null: continue
		stage.add_child(model)
		var spec: Dictionary = FLEET.spec(id)
		var size: Array = spec.bounds_size
		var center: Array = spec.bounds_center
		var c := Vector3(center[0],center[1],center[2])
		var reach := maxf(float(size[2]),float(size[1])*1.6)*1.45
		var views := {"fl":Vector3(-1,.45,-1.1),"rr":Vector3(1,.5,1.1),"side":Vector3(-1,.15,0),"top":Vector3(.2,1.6,.5),"rear":Vector3(.35,.25,1)}
		for label in views:
			camera.position = c+views[label].normalized()*reach
			camera.look_at(c,Vector3.UP)
			for i in 4: await process_frame
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+"head_"+id+"_"+label+".png"))
		model.queue_free()
		await process_frame
		print("CAPTURE ",id)
	quit(0)
