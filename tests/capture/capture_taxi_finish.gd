extends SceneTree
## Captura renderizada (Vulkan, não headless) de cada veículo da frota em quatro ângulos,
## para revisar a geometria (vidros, lanternas, proporções) sem entrar no jogo.
## Uso: --script res://tests/capture/capture_fleet_models.gd -- [id ...]. Saída em res://evidence/taxi-20260928/gallery/.
const OUTPUT := "res://evidence/taxi-20260928/gallery/"
const FLEET := preload("res://runtime/FleetCatalog.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var watermark := root.get_node_or_null("BuildWatermark")
	if watermark != null: watermark.queue_free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(960,600)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.55,.6,.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7,.72,.78)
	env.environment.ambient_light_energy = .7
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#385e86")
	sky_material.sky_horizon_color = Color("#b9cbd8")
	sky.sky_material = sky_material
	env.environment.sky = sky
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
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
	var brakes := "--brakes" in ids
	ids.erase("--brakes")
	if ids.is_empty(): ids = FLEET.all().keys()
	for id in ids:
		var model: Node3D
		if brakes:
			model = preload("res://scripts/Vehicle.gd").new()
			model.archetype = id
		else: model = FLEET.create(id)
		if model == null: continue
		stage.add_child(model)
		if brakes:
			model.set_physics_process(false)
			model.paint_color = Color("92979c") if id == "metro_hatch" else (Color("171b20") if id == "sedan_classic" else (Color("ffc526") if id == "taxi_yellow" else Color("e6e4df")))
			model.controlled = true
			model.ensure_equipment(stage)
		var spec: Dictionary = FLEET.spec(id)
		var size: Array = spec.bounds_size
		var center: Array = spec.bounds_center
		var c := Vector3(center[0],center[1],center[2])
		var reach := maxf(float(size[2]),float(size[1])*1.6)*1.45
		var views := {"fl":Vector3(-1,.45,-1.1),"rr":Vector3(1,.5,1.1),"side":Vector3(-1,.15,0),"top":Vector3(.2,1.6,.5),"rear":Vector3(.35,.25,1)}
		if brakes: views = {"rear":Vector3(.35,.25,1),"front":Vector3(-1,.6,-1.1)}
		for label in views:
			camera.position = c+views[label].normalized()*reach
			camera.look_at(c,Vector3.UP)
			for state in (["off","brake","headlights"] if brakes else [""]):
				if brakes:
					model.brake_input = state == "brake"
					model.equipment.headlights_on = state == "headlights"
					model.equipment._refresh()
				for i in 8: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+id+"_"+label+("_"+state if brakes else "")+".png"))
		model.queue_free()
		await process_frame
		print("CAPTURE ",id)
	quit(0)
