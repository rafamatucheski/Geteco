extends SceneTree

## Isolated art study. Does not load or change the city or population scripts.
const OUT := "D:/geteco/civil_reference.png"
var mats: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func material(key: String, color: String) -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.9
	mats[key] = m
	return m

func ell(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.radius = 0.5
	mesh.height = 1.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.scale = size
	node.material_override = mat
	parent.add_child(node)
	return node

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	parent.add_child(node)
	return node

func limb(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var shape := CapsuleMesh.new()
	shape.radius = radius
	shape.height = start.distance_to(end) + radius * 1.5
	shape.radial_segments = 16
	shape.rings = 8
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = mat
	node.position = (start + end) * 0.5
	parent.add_child(node)
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())

func build_person(parent: Node3D) -> void:
	var skin := material("skin", "ad7655")
	var skin_light := material("skin_light", "bc8965")
	var hair := material("hair", "292623")
	var jacket := material("jacket", "586353")
	var seam := material("seam", "384539")
	var shirt := material("shirt", "ddd1b8")
	var denim := material("denim", "344553")
	var denim_light := material("denim_light", "435865")
	var shoe := material("shoe", "65493b")
	var sole := material("sole", "c5b99e")
	var eyes := material("eyes", "242322")
	var metal := material("metal", "b4a784")
	# Separate pelvis, legs and shoes; stance is slightly asymmetric.
	ell(parent, Vector3(0, 0.88, 0), Vector3(0.35, 0.26, 0.24), denim)
	for side in [-1.0, 1.0]:
		var hip := Vector3(side * 0.105, 0.87, 0)
		var knee := Vector3(side * 0.115, 0.51, -0.015 if side < 0 else 0.025)
		var ankle := Vector3(side * 0.135, 0.16, 0.015 if side < 0 else 0.06)
		limb(parent, hip, knee, 0.09, denim)
		limb(parent, knee, ankle, 0.072, denim)
		box(parent, ankle + Vector3(0, 0.015, -0.062), Vector3(0.12, 0.022, 0.024), denim_light)
		ell(parent, ankle + Vector3(0, -0.095, -0.063), Vector3(0.16, 0.095, 0.30), sole)
		ell(parent, ankle + Vector3(0, -0.065, -0.063), Vector3(0.153, 0.125, 0.27), shoe)
		for lace in 3:
			box(parent, ankle + Vector3(0, -0.005, -0.10 + lace * 0.028), Vector3(0.083, 0.009, 0.008), shirt)
	# Torso, open field jacket, hem and patch pockets.
	ell(parent, Vector3(0, 1.14, 0), Vector3(0.44, 0.51, 0.28), jacket)
	ell(parent, Vector3(0, 1.18, -0.128), Vector3(0.19, 0.37, 0.055), shirt)
	box(parent, Vector3(0, 0.925, -0.13), Vector3(0.32, 0.035, 0.024), seam)
	for side in [-1.0, 1.0]:
		var panel := ell(parent, Vector3(side * 0.123, 1.13, -0.104), Vector3(0.17, 0.43, 0.125), jacket)
		panel.rotation.z = side * 0.035
		box(parent, Vector3(side * 0.062, 1.12, -0.161), Vector3(0.012, 0.31, 0.012), seam)
		box(parent, Vector3(side * 0.143, 1.17, -0.158), Vector3(0.084, 0.083, 0.018), seam)
		box(parent, Vector3(side * 0.143, 1.18, -0.17), Vector3(0.077, 0.063, 0.011), jacket)
		box(parent, Vector3(side * 0.143, 1.211, -0.178), Vector3(0.084, 0.016, 0.013), seam)
		ell(parent, Vector3(side * 0.143, 1.205, -0.187), Vector3.ONE * 0.009, metal)
		var collar := box(parent, Vector3(side * 0.072, 1.345, -0.09), Vector3(0.086, 0.13, 0.028), seam)
		collar.rotation.z = side * -0.40
		var shoulder := Vector3(side * 0.21, 1.32, 0)
		var elbow := Vector3(side * 0.285, 1.085, 0.0)
		var wrist := Vector3(side * 0.285, 0.865, -0.07)
		limb(parent, shoulder, elbow, 0.084, jacket)
		limb(parent, elbow, wrist, 0.069, jacket)
		limb(parent, wrist + Vector3(0, 0.04, 0.006), wrist, 0.07, seam)
		ell(parent, wrist + Vector3(0, -0.064, -0.006), Vector3(0.075, 0.13, 0.055), skin)
		ell(parent, wrist + Vector3(-side * 0.031, -0.038, -0.033), Vector3(0.033, 0.075, 0.032), skin_light)
	# Neck, jaw and face are distinct volumes, not a single featureless sphere.
	ell(parent, Vector3(0, 1.405, 0), Vector3(0.135, 0.16, 0.135), skin)
	ell(parent, Vector3(0, 1.575, -0.005), Vector3(0.255, 0.315, 0.25), skin)
	ell(parent, Vector3(0, 1.48, -0.065), Vector3(0.187, 0.14, 0.17), skin_light)
	for side in [-1.0, 1.0]:
		ell(parent, Vector3(side * 0.126, 1.57, 0), Vector3(0.047, 0.088, 0.052), skin)
		ell(parent, Vector3(side * 0.050, 1.59, -0.115), Vector3(0.036, 0.014, 0.012), eyes)
		var brow := box(parent, Vector3(side * 0.05, 1.614, -0.113), Vector3(0.045, 0.012, 0.012), hair)
		brow.rotation.z = side * 0.07
	ell(parent, Vector3(0, 1.558, -0.128), Vector3(0.041, 0.063, 0.051), skin_light)
	ell(parent, Vector3(0, 1.479, -0.122), Vector3(0.105, 0.035, 0.014), material("stubble", "674e3e"))
	box(parent, Vector3(0, 1.499, -0.146), Vector3(0.058, 0.007, 0.009), material("lip", "835640"))
	ell(parent, Vector3(0, 1.694, 0.008), Vector3(0.259, 0.115, 0.251), hair)
	ell(parent, Vector3(0, 1.612, 0.09), Vector3(0.23, 0.15, 0.095), hair)
	for i in 5:
		var tuft := ell(parent, Vector3(-0.084 + i * 0.038, 1.733 + sin(i) * 0.006, -0.026), Vector3(0.064, 0.055, 0.19), hair)
		tuft.rotation.z = -0.18
	# Wristwatch gives one intentionally asymmetric detail.
	ell(parent, Vector3(-0.285, 0.88, -0.127), Vector3(0.045, 0.055, 0.018), metal)
	ell(parent, Vector3(-0.285, 0.88, -0.138), Vector3(0.034, 0.042, 0.009), eyes)

func label(parent: Node, text_value: String, pos: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text_value
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)

func run() -> void:
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var canvas := CanvasLayer.new()
	scene.add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color("17212a")
	bg.size = Vector2(1440, 960)
	canvas.add_child(bg)
	label(canvas, "BREAKWATER  /  ESTUDO DE PERSONAGEM", Vector2(50, 32), 18, Color("bdc5c9"))
	label(canvas, "Civil 01 — jaqueta de campo", Vector2(50, 62), 36, Color("f2e5cf"))
	var angles := [Vector3(2.6, 1.95, -4.2), Vector3(-2.8, 2.0, 4.0), Vector3(0, 4.2, -2.3)]
	var names := ["01  /  FRENTE · 3/4", "02  /  COSTAS · 3/4", "03  /  LEITURA SUPERIOR"]
	for i in 3:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(440, 660)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		scene.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		build_person(world)
		var floor_mat := material("floor", "333e45")
		box(world, Vector3(0, -0.025, 0), Vector3(200, 0.05, 200), floor_mat)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("333e45")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("b7c8da")
		env.environment.ambient_light_energy = 0.65
		world.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -35, 0)
		light.light_color = Color("ffe3bd")
		light.light_energy = 1.25
		light.shadow_enabled = true
		light.shadow_bias = 0.12
		light.shadow_normal_bias = 1.5
		world.add_child(light)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = angles[i]
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.25
		camera.look_at(Vector3(0, 0.86, 0))
		var picture := TextureRect.new()
		picture.texture = viewport.get_texture()
		picture.position = Vector2(40 + i * 460, 150)
		picture.size = Vector2(440, 660)
		canvas.add_child(picture)
		label(canvas, names[i], Vector2(50 + i * 460, 824), 17, Color("e3d5bc"))
	label(canvas, "PROTÓTIPO 3D REAL NO GODOT · sem substituir a população atual", Vector2(50, 883), 19, Color("c2cbd0"))
	label(canvas, "Silhueta adulta / roupa em camadas / materiais foscos / mãos e calçados definidos", Vector2(50, 915), 17, Color("96a8b3"))
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUT)
	print("CIVIL_REFERENCE_CAPTURE result=%d file=%s" % [result, OUT])
	quit(result)
