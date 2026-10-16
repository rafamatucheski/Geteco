extends SceneTree
## Oráculo renderizado da silhueta de oclusão (occluded_silhouette.gdshader), que desde 16/10 usa teste de
## profundidade invertido em vez de hint_depth_texture. Confere as quatro regras da versão antiga:
## aparece só onde algo está na frente; some onde o alvo está à vista; oclusor dentro da caixa do alvo não
## conta; oclusor abaixo da altura mínima não conta. Também confere que nenhum material vivo do teste lê
## o depth (com MSAA, isso tirava do jogo inteiro a pré-compilação de pipelines).
## Uso: godot --path . --script res://tests/test_occluded_silhouette.gd [-- --legacy]  (legacy = versão antiga)
const SHADER := preload("res://world/city_look/occluded_silhouette.gdshader")
const LEGACY := preload("res://world/city_look/occluded_silhouette_depth_texture.gdshader")
var errors: Array[String] = []
var stage: Node3D
var target: MeshInstance3D
var overlay: ShaderMaterial
var camera: Camera3D
var view: SubViewport

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("test_occluded_silhouette: precisa de janela (não headless)")
		quit(2)
		return
	# Viewport próprio com MSAA 4x, como o jogo do usuário: é com MSAA que o depth lido pesava.
	view = SubViewport.new()
	view.size = Vector2i(640, 360)
	view.msaa_3d = Viewport.MSAA_4X
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var legacy := "--legacy" in OS.get_cmdline_user_args()
	if not legacy and ": hint_depth_texture" in SHADER.code: errors.append("A silhueta voltou a ler hint_depth_texture")
	if not legacy and "#define LAKE_DEPTH_TEXTURE" in preload("res://world/regions/mountain_lake.gdshader").code:
		errors.append("O lago sem bacia voltou a ler hint_depth_texture")
	if not legacy:
		for path in _depth_texture_shaders("res://"): errors.append("Shader lê hint_depth_texture (tira a pré-compilação de pipelines com MSAA): " + path)
	stage = Node3D.new()
	view.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	stage.add_child(environment)
	# Mesma projeção da câmera do jogo (scripts/CameraRig.gd).
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.far = 60.0
	camera.position = Vector3(0, 0, 10)
	stage.add_child(camera)
	camera.current = true
	target = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3, 2, 1)
	target.mesh = box
	target.material_override = _flat(Color.RED)
	stage.add_child(target)
	overlay = ShaderMaterial.new()
	overlay.shader = LEGACY if legacy else SHADER
	overlay.set_shader_parameter("readable_actor", true)
	overlay.set_shader_parameter("target_inverse", Projection(target.global_transform.affine_inverse()))
	_set_box(Vector3(-1.58, -1.08, -.58), Vector3(1.58, 1.08, .58))
	target.material_overlay = overlay
	# Parede cobrindo só a metade esquerda do alvo, 4 m à frente dele.
	var wall := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 4)
	wall.mesh = quad
	wall.material_override = _flat(Color.WHITE)
	wall.position = Vector3(-1.2, 0, 4)
	stage.add_child(wall)
	var left := _uv_of(Vector3(-0.8, 0, 0.5))   # alvo atrás da parede
	var right := _uv_of(Vector3(0.8, 0, 0.5))   # alvo à vista
	await _frames()
	var shot := _shot()
	if not _is_dark(shot, left): errors.append("Silhueta ausente onde a parede cobre o alvo: %s" % _px(shot, left))
	if not _is_red(shot, right): errors.append("Silhueta acesa sobre o alvo à vista: %s" % _px(shot, right))
	# Oclusor dentro da caixa do alvo (a caixa cresce até passar da parede): é o próprio alvo, não conta.
	_set_box(Vector3(-1.58, -1.08, -.58), Vector3(1.58, 1.08, 4.5))
	await _frames()
	shot = _shot()
	if not _is_white(shot, left): errors.append("Oclusor dentro da caixa acendeu a silhueta: %s" % _px(shot, left))
	# Oclusor abaixo da altura mínima (câmera e parede abaixo dela): não conta.
	_set_box(Vector3(-1.58, -1.08, -.58), Vector3(1.58, 1.08, .58))
	overlay.set_shader_parameter("minimum_occluder_height", 1.5)
	await _frames()
	shot = _shot()
	if not _is_white(shot, left): errors.append("Oclusor abaixo da altura mínima acendeu a silhueta: %s" % _px(shot, left))
	# Câmera acima olhando para baixo: o raio cruza a altura mínima entre a parede e o alvo.
	# Com mínimo 0 a parede (cruzada a ~0,9 m) conta; com mínimo 1,2 ela fica abaixo e não conta.
	camera.position = Vector3(0, 3, 10)
	camera.look_at(Vector3(0, -0.3, 0))
	var left_low := _uv_of(Vector3(-0.6, -0.3, 0.5))
	overlay.set_shader_parameter("minimum_occluder_height", 0.0)
	await _frames()
	shot = _shot()
	if not _is_dark(shot, left_low): errors.append("Parede acima da altura mínima não acendeu a silhueta: %s" % _px(shot, left_low))
	overlay.set_shader_parameter("minimum_occluder_height", 1.2)
	await _frames()
	shot = _shot()
	if not _is_white(shot, left_low): errors.append("Parede abaixo da altura mínima acendeu a silhueta: %s" % _px(shot, left_low))
	if errors.is_empty():
		print("test_occluded_silhouette: OK", " (legacy)" if legacy else "")
		quit(0)
	else:
		for error in errors: printerr("test_occluded_silhouette: ", error)
		quit(1)

func _set_box(low: Vector3, high: Vector3) -> void:
	overlay.set_shader_parameter("box_min", low)
	overlay.set_shader_parameter("box_max", high)

func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _frames() -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw

func _shot() -> Image:
	return view.get_texture().get_image()

func _uv_of(world: Vector3) -> Vector2:
	return camera.unproject_position(world) / Vector2(view.size)

func _px(image: Image, uv: Vector2) -> Color:
	return image.get_pixel(clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1), clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1))

func _is_dark(image: Image, uv: Vector2) -> bool:
	var c := _px(image, uv)
	# Preenchimento escuro (0,06 linear, ~0,27 sRGB) com alfa 0,92 sobre a parede branca.
	return c.r < .5 and c.g < .5 and c.b < .5

func _is_white(image: Image, uv: Vector2) -> bool:
	var c := _px(image, uv)
	return c.r > .8 and c.g > .8 and c.b > .8

func _is_red(image: Image, uv: Vector2) -> bool:
	var c := _px(image, uv)
	return c.r > .8 and c.g < .3 and c.b < .3

## Versões antigas guardadas só para A/B (HARBOR_PIPELINE_DEPTH_FREE=0 / HARBOR_ALPINE_LAKE_DEPTH=1).
const DEPTH_TEXTURE_ALLOWED := ["res://world/city_look/occluded_silhouette_depth_texture.gdshader", "res://world/regions/mountain_lake_depth.gdshader"]

## Todo shader do jogo que declara hint_depth_texture (ou liga a versão do lago que lê o depth): um só material vivo assim, com MSAA,
## faz o Forward Mobile compilar no primeiro desenho todo material novo (16/10).
func _depth_texture_shaders(folder: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null: return found
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub in ["evidence", "builds", "output", "artifacts", "addons", "tests"]: continue
		found.append_array(_depth_texture_shaders(folder.path_join(sub)))
	for file in dir.get_files():
		if not file.ends_with(".gdshader"): continue
		var path := folder.path_join(file)
		if path in DEPTH_TEXTURE_ALLOWED: continue
		var text := FileAccess.get_file_as_string(path)
		# Includes (.gdshaderinc) não são expandidos: o do lago só declara o depth sob #ifdef, ligado
		# apenas pela versão de A/B permitida acima.
		if ": hint_depth_texture" in text or "#define LAKE_DEPTH_TEXTURE" in text: found.append(path)
	return found
