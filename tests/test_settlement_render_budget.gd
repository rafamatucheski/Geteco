extends SceneTree
class Registration:
	extends RefCounted
	func register_exterior_entrance(_a: Node,_id: StringName,_p: Vector2) -> void: pass
class Region:
	extends Node2D
	var streamed_region := true
	var interior_manager := Registration.new()
var failures := 0
func _init() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures+=1
func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var scene := Region.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.make_current()
	var settlement = load("res://district/mountain_pass/MountainSettlement.gd").new()
	scene.add_child(settlement)
	var frame_count := 0
	while not settlement.region_ready:
		await process_frame
		frame_count += 1
	check(frame_count>=15,"streamed settlement distributes creation across frames")
	var props: Array[Node2D] = []
	for node in settlement.get_children():
		if node.get_script() != null and node.get_script().resource_path.ends_with("/MountainProp.gd"): props.append(node)
	check(props.size()==8,"all eight settlement props retain geometry")
	var offscreen := true
	for prop in props: offscreen = offscreen and prop.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not prop._rendered_once
	check(offscreen,"distant props avoid first 3D render")
	camera.global_position = props[0].global_position
	for i in 8: await process_frame
	check(props[0]._rendered_once,"approaching camera requests first prop render")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image: Image = props[0].viewport.get_texture().get_image()
		check(image.get_used_rect().has_area(),"visible prop has a rendered texture")
	check(props[0].project(Vector3.ZERO).is_finite(),"projection available for entrances and collisions")
	print("SETTLEMENT_BUDGET failures=",failures)
	scene.queue_free()
	for i in 4: await process_frame
	quit(failures)
