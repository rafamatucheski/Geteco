extends SceneTree
## Compara o lago alpino desenhado com o fundo tirado do mapa de alturas do terreno
## (mountain_lake_alpine.gdshader, 16/10) com a versão antiga que lia o buffer de profundidade
## (mountain_lake_depth.gdshader). A troca existe porque, com MSAA, um material vivo com
## hint_depth_texture tirava do jogo inteiro a pré-compilação de pipelines do Forward Mobile.
## Mesma câmera ortográfica e MSAA 4x do jogo; grava as duas imagens em evidence/alpine-lake-floor/.
## Falha se a média da diferença por pixel na água passar de MAX_MEAN_DIFF (as ondas andam entre as fotos).
const REGION := preload("res://world/regions/NativeRegion.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const DEPTH_SHADER := preload("res://world/regions/mountain_lake_depth.gdshader")
const ALPINE_SHADER := preload("res://world/regions/mountain_lake_alpine.gdshader")
const MAX_MEAN_DIFF := 0.01
const VIEWS := [Vector3(0, 25.3, 25.3), Vector3(25.3, 25.3, 0), Vector3(0, 30.4, 19.0)]
var errors: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("test_alpine_lake_floor: precisa de janela (não headless)")
		quit(2)
		return
	var center: Vector3 = CATALOG._at(Vector2(7000, 100), "mountain")
	var view := SubViewport.new()
	view.size = Vector2i(960, 540)
	view.msaa_3d = Viewport.MSAA_4X
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var region = REGION.build_region("mountain", center)
	view.add_child(region)
	region.prepare_collision_at(center)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.5, .6, .7)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.6, .65, .7)
	view.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	view.add_child(sun)
	# O trecho do lago entra pelo streaming em fatias: espera ele aparecer.
	var water: MeshInstance3D
	for frame in 1200:
		for node in get_nodes_in_group("native_water_surface"):
			if region.is_ancestor_of(node) and node.variant == "alpine": water = node.get_node_or_null("AlpineWater")
		if water != null: break
		await process_frame
	if water == null or not water.material_override is ShaderMaterial:
		printerr("test_alpine_lake_floor: lago alpino não encontrado (%d superfícies de água)" % get_nodes_in_group("native_water_surface").size())
		for node in get_nodes_in_group("native_water_surface"): printerr("  ", node.get_path(), " ", node.get("variant"), " ", node.get_children())
		quit(1)
		return
	# Terreno em volta também entra em fatias: sem esperar, as fotos comparavam trechos diferentes.
	var quiet := 0
	for frame in 3000:
		await process_frame
		var jobs: Variant = region.get("build_jobs")
		quiet = quiet + 1 if not (jobs is Array and not jobs.is_empty()) else 0
		if quiet >= 60: break
	var material := water.material_override as ShaderMaterial
	if material.shader != ALPINE_SHADER: errors.append("Lago alpino não usa o shader do mapa de alturas: %s" % material.shader.resource_path)
	var bounds: AABB = water.global_transform * water.get_aabb()
	var focus := bounds.get_center()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 34.0
	camera.far = 200.0
	view.add_child(camera)
	camera.current = true
	var folder := ProjectSettings.globalize_path("res://evidence/alpine-lake-floor")
	DirAccess.make_dir_recursive_absolute(folder)
	for index in VIEWS.size():
		camera.global_position = focus + VIEWS[index]
		camera.look_at(focus)
		material.shader = ALPINE_SHADER
		var floor_map := await _shot(view)
		material.shader = DEPTH_SHADER
		water.set_instance_shader_parameter("depth_fade", 1.0)
		var depth := await _shot(view)
		water.visible = false
		var dry := await _shot(view)
		water.visible = true
		material.shader = ALPINE_SHADER
		water.set_instance_shader_parameter("depth_fade", 1.0)
		floor_map.save_png("%s/view%d_floor_map.png" % [folder, index])
		depth.save_png("%s/view%d_depth_texture.png" % [folder, index])
		var stats := _difference(floor_map, depth, dry)
		print("test_alpine_lake_floor: vista %d, %d pixels de água: diferença média %.4f, máx %.3f, acima de 0,1 em %.2f%%" % [index, stats.pixels, stats.mean, stats.max, stats.over * 100.0])
		if stats.mean > MAX_MEAN_DIFF: errors.append("Vista %d: diferença média %.4f > %.3f" % [index, stats.mean, MAX_MEAN_DIFF])
	region.free()
	if errors.is_empty():
		print("test_alpine_lake_floor: OK")
		quit(0)
	else:
		for error in errors: printerr("test_alpine_lake_floor: ", error)
		quit(1)

func _shot(view: SubViewport) -> Image:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

## Só os pixels em que a água muda a imagem (em qualquer das versões) entram na conta.
func _difference(a: Image, b: Image, dry: Image) -> Dictionary:
	var total := 0.0
	var peak := 0.0
	var over := 0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var cd := dry.get_pixel(x, y)
			if _distance(ca, cd) < .02 and _distance(cb, cd) < .02: continue
			var d := _distance(ca, cb)
			total += d
			peak = maxf(peak, d)
			if d > .1: over += 1
			count += 1
	return {"mean": total / maxf(count, 1), "max": peak, "over": float(over) / maxf(count, 1), "pixels": count}

func _distance(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
