extends SceneTree
## Rendered geometric oracle: a red marker's virtual point must be red in
## the reflected camera. Checks projection/UV parity under camera movement.
const BATCHES := preload("res://world/city_look/CoastalFacadeBatches.gd")
const PLANAR := preload("res://world/city_look/CoastalPlanarReflections.gd")
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(800,450)
	var stage := Node3D.new()
	root.add_child(stage)
	var source := MultiMeshInstance3D.new()
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var original := MultiMesh.new()
	original.transform_format = MultiMesh.TRANSFORM_3D
	original.use_colors = true
	original.use_custom_data = true
	original.mesh = BoxMesh.new()
	original.instance_count = 3
	original.visible_instance_count = 2
	for i in 3:
		original.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0,0,[2,-2,4][i])))
	original.set_instance_color(0,Color.RED)
	original.set_instance_custom_data(0,Color(.2,.3,.4,.5))
	source.multimesh = original
	stage.add_child(source)
	var subset := preload("res://world/city_look/CoastalFacadeBatches.gd").build(source,Vector3.BACK,Vector3.ZERO,1<<16)
	if subset == null or subset.multimesh.instance_count != 1: errors.append("Mixed batch must retain only visible front instance")
	else:
		if subset.multimesh.get_instance_color(0) != Color.RED: errors.append("Batch color was lost")
		if not subset.multimesh.get_instance_custom_data(0).is_equal_approx(Color(.2,.3,.4,.5)): errors.append("Batch instance custom data was lost")
		if subset.layers != 1<<16: errors.append("Batch leaked to gameplay layer")
		if subset.multimesh.mesh != original.mesh: errors.append("Batch duplicated mesh resource")
		source.add_child(subset)
		original.set_instance_color(0, Color.BLUE)
		original.set_instance_custom_data(0, Color(.6,.5,.4,.3))
		BATCHES.sync(source, subset, Vector3.BACK, Vector3.ZERO)
		if subset.multimesh.get_instance_color(0) != Color.BLUE: errors.append("Changed color left a stale reflection")
		if not subset.multimesh.get_instance_custom_data(0).is_equal_approx(Color(.6,.5,.4,.3)): errors.append("Changed custom data left a stale reflection")
		original.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0,0,-3)))
		BATCHES.sync(source, subset, Vector3.BACK, Vector3.ZERO)
		if subset.visible: errors.append("Broken/moved prop left a ghost in the original half-space")
		original.visible_instance_count = 3
		BATCHES.sync(source, subset, Vector3.BACK, Vector3.ZERO)
		if not subset.visible or subset.multimesh.instance_count != 1: errors.append("Newly visible front instance did not enter the subset")
		original.visible_instance_count = 0
		BATCHES.sync(source, subset, Vector3.BACK, Vector3.ZERO)
		if subset.visible: errors.append("Hidden source instances remained reflected")
		original.visible_instance_count = 3
		BATCHES.sync(source, subset, Vector3.BACK, Vector3.ZERO)
		if not subset.visible: errors.append("Subset did not recover after visibility restoration")
		var unchanged := subset.multimesh
		BATCHES.sync(source, subset, Vector3.BACK, Vector3.ZERO)
		if subset.multimesh != unchanged: errors.append("Unchanged subset was rebuilt")
		var owner := PLANAR.new()
		owner._batches[source.get_instance_id()] = {"visual":subset,"source":weakref(source)}
		owner._clear_batches()
		if subset.visible or subset.layers != 0 or not owner._batches.is_empty(): errors.append("Disposed owner left a capture proxy visible")
		owner.free()
	source.free()
	await _check_interpolated_batch(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	stage.add_child(camera)
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.8,.8,.8)
	marker.mesh = box
	marker.position = Vector3(1,2,0)
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color.RED
	marker.material_override = red
	stage.add_child(marker)
	var view := SubViewport.new()
	view.size = Vector2i(640,360)
	view.world_3d = stage.get_world_3d()
	view.transparent_bg = true
	view.use_hdr_2d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(view)
	var mirrored := Camera3D.new()
	view.add_child(mirrored)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.TRANSPARENT
	mirrored.environment = env
	var positions := [Vector3(8,10,12),Vector3(-8,10,12),Vector3(1,13,12)]
	for position in positions:
		camera.position = position
		camera.look_at(Vector3.ZERO)
		PLANAR.mirror_camera(camera,mirrored,Vector3.UP,Vector3.ZERO)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		if not PLANAR.bounds_in_frustum(camera, marker.global_transform * marker.get_aabb()): errors.append("Visible facade bounds were culled")
		if PLANAR.bounds_in_frustum(camera, AABB(Vector3(10000,10000,10000),Vector3.ONE)): errors.append("Offscreen facade bounds were not culled")
		var image := view.get_texture().get_image()
		# Actual projection of the marker, not the arbitrary ground coordinate.
		var clip := PLANAR.projection_for(mirrored) * Vector4(1,2,0,1)
		var uv := Vector2(clip.x/clip.w*.5+.5,-clip.y/clip.w*.5+.5)
		var pixel := Vector2i(uv*Vector2(image.get_size()))
		var sample := image.get_pixelv(pixel)
		if sample.r < .8 or sample.g > .1: errors.append("Wrong projected marker/UV parity: "+str(sample))
		if image.get_pixel(0,0).a > .01: errors.append("Background must remain transparent")
		var mirror_point := Vector3(1,-2,0)
		var main_pixel := camera.unproject_position(mirror_point)/root.get_visible_rect().size
		var reflect_pixel := mirrored.unproject_position(marker.position)/Vector2(view.size)
		# Reflection introduces horizontal parity. Shader projection resolves it.
		if absf(main_pixel.y-reflect_pixel.y)>.001 or absf(main_pixel.x-(1-reflect_pixel.x))>.001:
			errors.append("Virtual marker and reflected camera disagree")
	print("COASTAL_PLANAR projection poses=",positions.size()," errors=",errors)
	stage.queue_free()
	for i in 3: await process_frame
	quit(0 if errors.is_empty() else 1)

func _check_interpolated_batch(stage: Node3D) -> void:
	var source := MultiMeshInstance3D.new()
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var original := MultiMesh.new()
	original.transform_format = MultiMesh.TRANSFORM_3D
	original.use_colors = true
	original.use_custom_data = true
	original.mesh = BoxMesh.new()
	original.instance_count = 1
	original.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0,0,2)))
	original.set_instance_color(0, Color.RED)
	original.set_instance_custom_data(0, Color(.2,.3,.4,.5))
	source.multimesh = original
	stage.add_child(source)
	var proxy := BATCHES.build(source, Vector3.BACK, Vector3.ZERO, 1 << 16)
	if proxy == null:
		errors.append("Interpolated source failed initial subset construction")
		source.free()
		return
	source.add_child(proxy)
	if proxy.physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_OFF:
		errors.append("Displayed reflection pose must not be interpolated twice")
	await physics_frame
	original.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0,0,4)))
	original.set_instance_color(0, Color.BLUE)
	original.set_instance_custom_data(0, Color(.6,.5,.4,.3))
	for tick in 2: await physics_frame
	await RenderingServer.frame_post_draw
	var displayed := original.get_instance_transform(0)
	var displayed_color := original.get_instance_color(0)
	var displayed_custom := original.get_instance_custom_data(0)
	# Establish that the real rendered source changed before comparing its proxy.
	if not displayed.origin.is_equal_approx(Vector3(0,0,4)) or not displayed_color.is_equal_approx(Color.BLUE):
		errors.append("Interpolated fixture never displayed the changed source pose/color")
	if not displayed_custom.is_equal_approx(Color(.6,.5,.4,.3)):
		errors.append("Interpolated fixture never displayed the changed source custom data")
	BATCHES.sync(source, proxy, Vector3.BACK, Vector3.ZERO)
	if not proxy.multimesh.get_instance_transform(0).is_equal_approx(displayed):
		errors.append("Reflection differs from the interpolated source's displayed pose")
	if not proxy.multimesh.get_instance_color(0).is_equal_approx(displayed_color):
		errors.append("Reflection differs from the interpolated source's displayed color")
	if not proxy.multimesh.get_instance_custom_data(0).is_equal_approx(displayed_custom):
		errors.append("Reflection differs from the interpolated source's displayed custom data")
	await physics_frame
	original.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0,0,-3)))
	for tick in 2: await physics_frame
	await RenderingServer.frame_post_draw
	if not original.get_instance_transform(0).origin.is_equal_approx(Vector3(0,0,-3)):
		errors.append("Interpolated fixture did not display the moved/broken source")
	BATCHES.sync(source, proxy, Vector3.BACK, Vector3.ZERO)
	if proxy.visible: errors.append("Interpolated moved/broken prop left a reflection ghost")
	if source.physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_ON:
		errors.append("Reflection sync altered source interpolation")
	source.free()
