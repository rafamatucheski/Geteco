extends SceneTree
## Rendered depth test: low props hide legs, tall buildings retain the guide.
const SHADER := preload("res://world/city_look/occluded_silhouette.gdshader")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func mesh_box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node

func capture() -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			if absf(ca.r-cb.r) + absf(ca.g-cb.g) + absf(ca.b-cb.b) > .06: count += 1
	return count

func check(ok: bool, label: String) -> void:
	print("PROP_DEPTH ", label, " ", ok)
	if not ok: failures.append(label)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(480, 480)
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4
	camera.far = 180
	camera.position = Vector3(0,4,6)
	camera.look_at(Vector3(0,.7,0))
	var actor := mesh_box(stage, Vector3(.6,1.8,.4), Vector3(0,.9,0), Color("1839a0"))
	var prop := mesh_box(stage, Vector3(2,.8,.7), Vector3(0,.4,1), Color("396d26"))
	var overlay := ShaderMaterial.new()
	overlay.shader = SHADER
	overlay.set_shader_parameter("minimum_occluder_height",1.2)
	overlay.set_shader_parameter("box_min", Vector3(-.31,0,-.21))
	overlay.set_shader_parameter("box_max", Vector3(.31,1.8,.21))
	var plain := await capture()
	actor.material_overlay = overlay
	var low := await capture()
	check(difference(plain,low) == 0, "low prop does not show the hidden legs")
	actor.hide()
	var absent := await capture()
	check(difference(low,absent) > 100, "visible upper body remains visible")
	actor.show()
	prop.mesh.size.y = 3.5
	prop.position.y = 1.75
	actor.material_overlay = null
	var wall_plain := await capture()
	actor.material_overlay = overlay
	var wall_guide := await capture()
	check(difference(wall_plain,wall_guide) > 100, "tall wall retains the silhouette guide")
	stage.free()
	print("STREET_PROP_OCCLUSION failures=",failures)
	quit(0 if failures.is_empty() else 1)
