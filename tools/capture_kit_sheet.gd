extends SceneTree
## Folha de contato de tipos do kit da cidade: cada tipo lado a lado, com o material do
## jogo, de frente e um pouco de cima. Só para olhar; não mede desempenho.
## Uso: tools/run_godot_locked.sh --path . --script res://tools/capture_kit_sheet.gd -- --kinds=a,b,c --out=nome
##   GETECO_BLENDER_PROPS=0 mostra as procedurais. --variants=N repete cada tipo N vezes com
##   as variações de cor e forma do kit (KIT.variation_for).
const KIT := preload("res://world/city_look/CityPropKit.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const OUT := "res://evidence/blender-props/onda3"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var kinds: PackedStringArray = []
	var out_name := "sheet"
	var copies := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kinds="): kinds = arg.substr(8).split(",")
		elif arg.begins_with("--out="): out_name = arg.substr(6)
		elif arg.begins_with("--variants="): copies = int(arg.substr(11))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1800, 1000)
	var stage := Node3D.new()
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
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.material_override = MATERIALS.flat(Color("8a8780"), .9)
	stage.add_child(ground)
	var x := 0.0
	var tallest := 1.0
	for kind in kinds:
		var mesh := KIT.mesh(kind)
		var box := mesh.get_aabb()
		tallest = maxf(tallest, box.end.y)
		for copy in copies:
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			var variation: Dictionary = KIT.variation_for(kind)
			multimesh.use_colors = not variation.is_empty()
			multimesh.mesh = mesh
			multimesh.instance_count = 1
			var placement := Transform3D(Basis.IDENTITY, Vector3(x - box.position.x, -box.position.y if box.position.y < -0.05 else 0.0, 0))
			if not variation.is_empty():
				var varied: Array = KIT.vary(kind, placement, copy)
				placement = varied[0]
				multimesh.set_instance_color(0, varied[1])
			multimesh.set_instance_transform(0, placement)
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = multimesh
			visual.material_override = KIT.material_for(kind)
			stage.add_child(visual)
			x += box.size.x * 1.15 + .5
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 30.0
	var width := x
	var distance := maxf(width * 0.5 / tan(deg_to_rad(camera.fov * 0.5 * 1.6)), tallest * 2.4)
	camera.look_at_from_position(Vector3(width * .5, tallest * .9 + distance * .18, distance), Vector3(width * .5, tallest * .42, 0))
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + "/" + out_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("[captura] ", path)
	quit(0)
