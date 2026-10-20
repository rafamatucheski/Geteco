extends SceneTree
## Adereços das zonas do porto antes (procedurais) e depois (Blender), com os materiais
## do porto, mesma luz e mesma câmera. Só para olhar; não mede desempenho.
## Uso: tools/run_godot_locked.sh --path . --script res://tools/capture_harbor_props.gd
const OUT := "res://evidence/blender-props/porto"
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
var stage: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1800, 1000)
	_scene()
	for label in ["antes", "depois"]:
		HarborRouteProps.blender_props_enabled = label == "depois"
		var props := _props()
		stage.add_child(props)
		await _shoot("godot-%s-geral" % label, Vector3(0, 3.4, 13.5), Vector3(0, 1.8, 0), 40.0)
		await _shoot("godot-%s-perto" % label, Vector3(2.2, 1.5, 4.6), Vector3(2.2, .6, 0), 45.0)
		await _shoot("godot-%s-postes" % label, Vector3(-4.2, 3.4, 7.5), Vector3(-4.2, 3.8, 0), 45.0)
		props.free()
	quit(0)

func _props() -> Node3D:
	var group := Node3D.new()
	var items := [
		[HarborRouteProps.create_streetlight(5.4, 1.35, "standard", 0.0), -7.0, -1.0],
		[HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0), -4.2, -1.0],
		[HarborRouteProps.create_streetlight(5.2, 1.1, "industrial", 0.0), -1.8, -1.0],
		[HarborRouteProps.create_bench(2.2), .6, -.6],
		[HarborRouteProps.create_trash_bin(), 2.2, .3],
		[HarborRouteProps.create_fire_hydrant(), 3.0, .8],
		[HarborRouteProps.create_bollard("civic"), 3.7, 1.0],
		[HarborRouteProps.create_bollard("police"), 4.2, 1.0],
		[HarborRouteProps.create_bollard("hazard"), 4.7, 1.0],
		[HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85)), 6.3, -.4],
		[HarborRouteProps.create_bike_rack(4, 0.85), -3.0, 2.2],
		[HarborRouteProps.create_drain_grate(), 1.2, 2.0],
	]
	for item in items:
		var node: Node3D = item[0]
		node.position = Vector3(item[1], 0, item[2])
		group.add_child(node)
	return group

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
	ground.material_override = HarborRouteMaterials.sidewalk_concrete()
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.name = "Camera"
	stage.add_child(camera)
	camera.current = true

func _shoot(name: String, from: Vector3, target: Vector3, fov: float) -> void:
	var camera := stage.get_node("Camera") as Camera3D
	camera.fov = fov
	camera.look_at_from_position(from, target)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + "/" + name + ".png")
	root.get_texture().get_image().save_png(path)
	print("[captura] ", path)
