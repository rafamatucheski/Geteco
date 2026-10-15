extends SceneTree
## Teste da "fachada inteira pintada" (estilo GTA III/VC) com as imagens geradas
## pelo ChatGPT em output/imagegen/fachadas-20261015 (fora do Git). Cada sobrado é
## 1 caixa + 1 quad com a foto + peitoris e degrau em 3D só onde a silhueta
## importa. À noite, a emissão sai só dos pixels amarelos da versão noturna.
## Compara lado a lado com o sobrado atual (janela pintada) e conta peças.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const SOURCE := "res://output/imagegen/fachadas-20261015"
const W := 6.0
const H := 7.0
## Peitoris medidos na imagem (fração da largura/altura, origem no topo).
const SILLS := [[0.116, 0.405, 0.335], [0.592, 0.883, 0.335], [0.071, 0.336, 0.785], [0.406, 0.668, 0.785]]

var night_materials: Array[StandardMaterial3D] = []

func _initialize() -> void: run.call_deferred()

func load_image(file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path("%s/%s" % [SOURCE, file]))

## Só a luz da sala vira emissão: pixel quente e claro da versão noturna.
func glow_from_night(night: Image) -> Image:
	var glow := night.duplicate()
	glow.convert(Image.FORMAT_RGB8)
	for y in glow.get_height():
		for x in glow.get_width():
			var c: Color = glow.get_pixel(x, y)
			var warm: bool = c.r > 0.45 and c.r > c.b * 1.5 and c.g > c.b * 1.15
			glow.set_pixel(x, y, c if warm else Color.BLACK)
	glow.generate_mipmaps()
	return glow

func facade_house(parent: Node3D, origin: Vector3, kind: String) -> void:
	var day := load_image(kind + "-dia.png")
	var night := load_image(kind + "-noite.png")
	var house := Node3D.new()
	house.position = origin
	parent.add_child(house)
	var wall_color := day.get_pixel(day.get_width() / 3, day.get_height() / 2)
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(W, H, 8.0)
	body.position = Vector3(0, H * 0.5, -4.0)
	body.material_override = UrbanMaterials.textured_wall(wall_color)
	house.add_child(body)
	day.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(day)
	mat.normal_enabled = true
	mat.normal_texture = SURFACES.normal_from_albedo(day, 3.0)
	mat.roughness = 0.85
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.emission_enabled = true
	mat.emission = Color.BLACK
	mat.emission_texture = ImageTexture.create_from_image(glow_from_night(night))
	mat.emission_energy_multiplier = 0.0
	night_materials.append(mat)
	var front := MeshInstance3D.new()
	front.mesh = QuadMesh.new()
	front.mesh.size = Vector2(W, H)
	front.position = Vector3(0, H * 0.5, 0.01)
	front.material_override = mat
	house.add_child(front)
	var stone := UrbanMaterials.trim_stone()
	for sill in SILLS:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		box.mesh.size = Vector3((sill[1] - sill[0]) * W, 0.1, 0.18)
		box.position = Vector3(((sill[0] + sill[1]) * 0.5 - 0.5) * W, H * (1.0 - sill[2]), 0.09)
		box.material_override = stone
		house.add_child(box)
	for part in [[Vector3(W + 0.3, 0.3, 0.5), Vector3(0, H + 0.15, 0.05)], [Vector3(1.5, 0.18, 0.5), Vector3(W * 0.315, 0.09, 0.25)]]:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		box.mesh.size = part[0]
		box.position = part[1]
		box.material_override = stone
		house.add_child(box)

func run() -> void:
	var out := ProjectSettings.globalize_path("res://evidence/painted-windows-20261015")
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(120, 120)
	ground.material_override = UrbanMaterials.sidewalk_stone()
	stage.add_child(ground)
	var gpt := Node3D.new()
	stage.add_child(gpt)
	var x := -10.0
	for kind in ["tijolo", "reboco-creme", "concreto-cinza"]:
		facade_house(gpt, Vector3(x, 0, 0), kind)
		x += 6.6
	var chunk := Node3D.new()
	stage.add_child(chunk)
	FACTORY.populate_chunk(chunk, {"id":"NorthbankHomes1","kind":"brownstone","position":Vector3(16, 0, -5),"size":Vector2(12,10)})
	for i in 3: await process_frame
	DRESSING._night_pass(chunk, {"lamps":[]})
	var per_gpt := gpt.find_children("*", "MeshInstance3D", true, false).size() / 3.0
	print("GPT_FACADES pieces_per_gpt_house=", per_gpt, " pieces_current_brownstone=", chunk.find_children("*", "MeshInstance3D", true, false).size())
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	var shots := [["street", Vector3(2, 3.5, 21), Vector3(2, 3.5, 0)], ["gpt_close", Vector3(-12, 2.5, 7), Vector3(-9, 3.5, 0)]]
	for is_night in [false, true]:
		MATERIALS.set_night(1.0 if is_night else 0.0)
		for mat in night_materials: mat.emission_energy_multiplier = 1.6 if is_night else 0.0
		sun.light_energy = 0.05 if is_night else 1.0
		env.environment.background_energy_multiplier = 0.08 if is_night else 1.0
		env.environment.ambient_light_energy = 0.15 if is_night else 1.0
		for shot in shots:
			cam.look_at_from_position(shot[1], shot[2])
			for i in 8: await process_frame
			var path := "%s/gpt_%s_%s.png" % [out, shot[0], "night" if is_night else "day"]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	quit(0)
