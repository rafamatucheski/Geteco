extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/SummitSUVModel.gd"
const OUTPUT_PATH := "res://_codex_diag/summit-suv/prepared-vs-fallback.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	var script := load(MODEL_PATH) as Script
	if script == null:
		quit(1)
		return

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 700)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8496a8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dbe7f2")
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(13.0, 0.12, 8.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.09, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("536472")
	floor.material_override = floor_material
	viewport.add_child(floor)

	var prepared := script.new() as Node3D
	prepared.position = Vector3(-2.25, 0.0, 0.0)
	viewport.add_child(prepared)
	var prepared_rig := WHEEL_RIG.new()
	if not prepared_rig.mount(prepared) or prepared_rig.pivots.size() != 4:
		quit(1)
		return

	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var fallback := script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	fallback.call("build_procedural_source", true)
	fallback.position = Vector3(2.25, 0.0, 0.0)
	viewport.add_child(fallback)
	var fallback_rig := WHEEL_RIG.new()
	if not fallback_rig.mount(fallback) or fallback_rig.pivots.size() != 4:
		quit(1)
		return

	var camera := Camera3D.new()
	camera.fov = 38.0
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(8.2, 4.7, -11.5), Vector3(0.0, 0.95, 0.0), Vector3.UP)
	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 1.45
	key_light.shadow_enabled = true
	key_light.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.light_energy = 0.55
	fill_light.rotation_degrees = Vector3(-30.0, 145.0, 0.0)
	viewport.add_child(fill_light)

	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := viewport.get_texture().get_image().save_png(output_path)
	print("SUMMIT_SUV_PREPARED_CAPTURE path=%s error=%d prepared_meshes=%d fallback_meshes=%d" % [
		output_path, error, _mesh_count(prepared), _mesh_count(fallback),
	])
	quit(0 if error == OK else 1)


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count
