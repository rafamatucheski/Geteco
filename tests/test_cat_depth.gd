extends SceneTree
## Native cat mesh depth with a visible positive control at every tested position.
## This isolated fixture proves depth ordering only, not complete interior approval
## or performance. Run rendered in Godot 4.7.2 .NET after building Harbor.csproj.

const CAT := preload("res://runtime/cats/CatModel.gd")
const FURNITURE := preload("res://runtime/cats/CatFurniture.gd")
var output := "res://evidence/cats-depth"
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var completed := false


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		if not completed:
			push_error("CAT_DEPTH_TIMEOUT")
			quit(3))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	print("CAT_DEPTH ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("CSharpScript"):
		push_error("Cat depth requires rendered Godot .NET")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 900)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("28333b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c8d2da")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -28, 0)
	light.light_color = Color("fff0da")
	light.light_energy = 1.0
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(9, 9)
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = material(Color("657069"))
	stage.add_child(floor)
	var cabinet := Node3D.new()
	cabinet.name = "DepthCabinet"
	stage.add_child(cabinet)
	var cabinet_mesh := BoxMesh.new()
	cabinet_mesh.size = Vector3(1.3, 1.6, 0.44)
	var cabinet_visual := MeshInstance3D.new()
	cabinet_visual.mesh = cabinet_mesh
	cabinet_visual.position.y = 0.8
	cabinet_visual.material_override = material(Color("765c43"))
	cabinet.add_child(cabinet_visual)
	# A matching native solid keeps this a real piece of furniture, while pixel
	# assertions below deliberately remain separate from swept-physics assertions.
	var cabinet_body := StaticBody3D.new()
	cabinet_body.collision_layer = 1
	cabinet_body.collision_mask = 0
	var cabinet_shape := CollisionShape3D.new()
	var cabinet_box := BoxShape3D.new()
	cabinet_box.size = cabinet_mesh.size
	cabinet_shape.shape = cabinet_box
	cabinet_shape.position.y = 0.8
	cabinet_body.add_child(cabinet_shape)
	cabinet.add_child(cabinet_body)
	for setup in [
		{"kind": "bed", "at": Vector3(-1.2, 0, 0.75)},
		{"kind": "toy", "at": Vector3(1.5, 0, 0.95)},
		{"kind": "scratcher", "at": Vector3(-1.5, 0, -0.7)}]:
		var furniture := FURNITURE.create(setup.kind)
		furniture.position = setup.at
		stage.add_child(furniture)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.4
	camera.near = 0.05
	stage.add_child(camera)
	camera.position = Vector3(0, 2.8, 4.0)
	camera.look_at(Vector3(0, 0.45, 0))
	camera.make_current()
	var cat = CAT.new()
	cat.configure(0)
	cat.rotation.y = PI
	stage.add_child(cat)
	var meshes: Array[MeshInstance3D] = []
	find_meshes(cat, meshes)
	check(meshes.size() >= 8, "real articulated CatModel meshes are present")
	var originals: Array[Material] = []
	for mesh in meshes:
		originals.append(mesh.material_override)
	var mask_material := StandardMaterial3D.new()
	mask_material.albedo_color = Color(1, 0, 1)
	mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask_material.emission_enabled = true
	mask_material.emission = Color(1, 0, 1)
	mask_material.emission_energy_multiplier = 1.0
	mask_material.vertex_color_use_as_albedo = false
	for pose in ["sit", "walk"]:
		cat.set_activity(pose)
		for step in range(90):
			cat.animate(1.0 / 60.0, 0.62 if pose == "walk" else 0.0)
		for setup in [
			{"id": "front", "position": Vector3(0, 0, 0.84), "occluded": false},
			{"id": "behind", "position": Vector3(0, 0, -0.72), "occluded": true},
			{"id": "side", "position": Vector3(1.15, 0, 0), "occluded": false}]:
			var label: String = pose + "-" + str(setup.id)
			cat.position = setup.position
			cat.reset_physics_interpolation()
			cabinet.show()
			for index in range(meshes.size()):
				meshes[index].material_override = originals[index]
			var normal := await capture()
			save_image(normal, label + ".png")
			for mesh in meshes:
				mesh.material_override = mask_material
			var actual := await capture()
			cabinet.hide()
			var control := await capture()
			cabinet.show()
			var visible_pixels := mask_count(actual)
			var control_pixels := mask_count(control)
			var ratio := float(visible_pixels) / maxf(1.0, float(control_pixels))
			check(control_pixels > 500, label + " unobstructed positive control: %d pixels" % control_pixels)
			if setup.occluded:
				check(ratio < 0.05, label + " cabinet occludes cat: %.4f visible" % ratio)
			else:
				check(ratio > 0.95, label + " cat remains visible: %.4f visible" % ratio)
			results.append({"case": label, "control_pixels": control_pixels, "visible_pixels": visible_pixels, "visible_ratio": ratio})
			save_image(actual, label + "-mask.png")
			save_image(control, label + "-control.png")
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": results, "engine": Engine.get_version_info(), "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"), "scope": "isolated native cat depth only"}, "\t"))
	else:
		check(false, "results.json could not be written")
	print("CAT_DEPTH_RESULT checks=", checks, " failures=", failures, " output=", output)
	completed = true
	quit(0 if failures.is_empty() else 1)


func capture() -> Image:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func save_image(image: Image, filename: String) -> void:
	var error := image.save_png(output.path_join(filename))
	check(error == OK, "capture saved " + filename)


func mask_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.75 and pixel.b > 0.75 and pixel.g < 0.25:
				count += 1
	return count


func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	return result


func find_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		find_meshes(child, meshes)
