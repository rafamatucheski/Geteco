extends SceneTree
## Adereços da cidade antes (procedurais) e depois (Blender), na mesma cena, mesma luz e
## mesma câmera, com os materiais de verdade do jogo. Só para olhar; não mede desempenho.
## Uso: tools/run_godot_locked.sh --path . --script res://tools/capture_city_props.gd
const KIT := preload("res://world/city_look/CityPropKit.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const OUT := "res://evidence/blender-props/primeira-onda"
## Ordem e posição (x, z) de cada peça na calçada da foto.
const LAYOUT := [["phone_booth", -6.4, 1.2], ["planter", -4.8, 1.0], ["bench_seat", -1.4, 1.0],
	["trash_can", .1, 1.0], ["hydrant", 1.0, .2], ["bollard", 1.8, -.2], ["mailbox", 2.6, 1.0],
	["news_box", 3.7, 1.0], ["trash_bags", 5.0, 1.3], ["dumpster", 6.9, 1.5]]
var stage: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1800, 1000)
	_scene()
	for label in ["antes", "depois"]:
		KIT.blender_props_enabled = label == "depois"
		for item in LAYOUT: KIT._meshes.erase(item[0])
		DRESSING._lamp_meshes.clear()
		var props := _props()
		stage.add_child(props)
		await _shoot(label + "-calcada", Vector3(.5, 3.2, 14.0), Vector3(0, 1.2, 0), 30.0)
		await _shoot(label + "-perto", Vector3(1.4, 1.6, 4.4), Vector3(1.6, .6, .6), 45.0)
		props.free()
	quit(0)

func _scene() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9fb0b8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c3ccd2")
	env.environment.ambient_light_energy = .7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 28, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	ground.material_override = MATERIALS.flat(Color("8a8780"), .9)
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.name = "Camera"
	stage.add_child(camera)
	camera.current = true

func _props() -> Node3D:
	var group := Node3D.new()
	for item in LAYOUT:
		var visual := MeshInstance3D.new()
		visual.mesh = KIT.mesh(item[0])
		visual.material_override = KIT.material_for(item[0])
		# Frente (+Z) virada para a câmera, como na calçada.
		visual.position = Vector3(item[1], 0, -item[2])
		group.add_child(visual)
	for part in ["pole", "head"]:
		var lamp := MeshInstance3D.new()
		lamp.mesh = DRESSING._lamp_mesh(part)
		lamp.material_override = MATERIALS.flat(Color("4a5054"), .6) if part == "pole" else MATERIALS.lamp_head()
		lamp.position = Vector3(-3.0, 0, -.2)
		group.add_child(lamp)
	return group

func _shoot(name: String, from: Vector3, target: Vector3, fov: float) -> void:
	var camera := stage.get_node("Camera") as Camera3D
	camera.fov = fov
	camera.look_at_from_position(from, target)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + "/godot-" + name + ".png")
	root.get_texture().get_image().save_png(path)
	print("[captura] ", path)
