extends SceneTree
## Rendered regression: additive lamp quads must not paint rectangular fog.
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size = Vector2i(640,480)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("344955")
	env.fog_enabled = true
	env.fog_light_color = Color("779baa")
	env.fog_density = .045
	environment.environment = env
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	stage.add_child(camera)
	camera.position = Vector3(10,18,20)
	camera.look_at(Vector3.ZERO)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60,60)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.albedo_color = Color("242c33")
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var pool := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	pool.mesh = quad
	pool.scale = Vector3(10,1,10)
	pool.position.y = .05
	pool.extra_cull_margin = 2
	pool.material_override = MATERIALS.light_pool()
	stage.add_child(pool)
	MATERIALS.set_night(1)
	MATERIALS.set_wetness(1)
	pool.visible = false
	var baseline := await capture()
	pool.visible = true
	var fixed := await capture()
	var original_shader: Shader = (pool.material_override as ShaderMaterial).shader
	var broken := Shader.new()
	broken.code = original_shader.code.replace(", fog_disabled;",";")
	(pool.material_override as ShaderMaterial).shader = broken
	var defect := await capture()
	var corrected_max := 0.0
	var broken_max := 0.0
	for x in [-5.8,5.8]:
		for z in [-5.8,5.8]:
			# Project coordinates use the project's logical stretch viewport;
			# readback uses the actual window resolution.
			var pixel: Vector2i = Vector2i(camera.unproject_position(Vector3(x,.05,z))*Vector2(baseline.get_size())/root.get_visible_rect().size)
			if not Rect2i(Vector2i.ZERO,baseline.get_size()).has_point(pixel):
				errors.append("Projected fixture corner outside readback")
				continue
			var base_color := baseline.get_pixelv(pixel)
			corrected_max = maxf(corrected_max,color_delta(base_color,fixed.get_pixelv(pixel)))
			broken_max = maxf(broken_max,color_delta(base_color,defect.get_pixelv(pixel)))
	if corrected_max>.015: errors.append("Zero-light quad corners alter the fogged floor")
	if broken_max<.03: errors.append("Fixture did not reproduce the rectangular fog defect")
	var brightest := 0.0
	for y in range(40,440,4):
		for x in range(40,600,4): brightest=maxf(brightest,color_delta(baseline.get_pixel(x,y),fixed.get_pixel(x,y)))
	if brightest<.03: errors.append("Correction removed the intended lamp light")
	var folder := "res://evidence/coastal-weather-20261013/lamp-fog-regression"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	baseline.save_png(folder+"/baseline.png")
	fixed.save_png(folder+"/fixed.png")
	defect.save_png(folder+"/reproduced-defect.png")
	print("LAMP_POOL_FOG corrected_corner_delta=",corrected_max," broken_corner_delta=",broken_max," retained_light=",brightest," errors=",errors)
	(pool.material_override as ShaderMaterial).shader = original_shader
	stage.queue_free()
	for i in 6: await process_frame
	quit(0 if errors.is_empty() else 1)

func capture() -> Image:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func color_delta(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
