extends SceneTree
## Diagnostic comparison using the fleet's real paint, under the same light/camera.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const SOURCE := preload("res://runtime/VehiclePaint.gd")
const OUT := "res://evidence/paint-glare-20260929/"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(960,600)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("829da6")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c0d0e2")
	environment.environment.ambient_light_energy = .65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_energy = 1.6
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11
	# Align with the sun's reflection on horizontal body panels.
	var reflected := (-sun.transform.basis.z).bounce(Vector3.UP)
	camera.position = Vector3(0,1,0)+reflected*15.0
	stage.add_child(camera)
	camera.look_at(Vector3(0,1,0))
	var models: Array[Node3D] = []
	var paints: Array = []
	var finishes: Dictionary = {}
	for id in ["ranch_single","medic_box"]:
		var model := FLEET.create(id)
		stage.add_child(model)
		model.position.x = -2.3 if models.is_empty() else 2.3
		models.append(model)
		var paint := SOURCE.new()
		paint.bind(model,id)
		for material in paint.materials:
			finishes[material] = [material.clearcoat,material.clearcoat_roughness,material.roughness,material.metallic_specular]
		paints.append(paint)
	for before in [true,false]:
		for i in paints.size():
			var source := SOURCE.source_for("ranch_single" if i == 0 else "medic_box")
			for material in paints[i].materials:
				material.clearcoat = .5 if before else finishes[material][0]
				material.clearcoat_roughness = .2 if before else finishes[material][1]
				material.roughness = minf(source.roughness,.3) if before else finishes[material][2]
				material.metallic_specular = .5 if before else finishes[material][3]
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(OUT+("before" if before else "after")+".png")
		print("PAINT_CAPTURE ",before," error=",result)
	stage.queue_free()
	await process_frame
	quit()
