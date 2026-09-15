extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720)
	var scene=Node2D.new()
	root.add_child(scene)
	current_scene=scene
	var room=load("res://world/harbor/interiors/HarborHospitalInterior3D.gd").new()
	scene.add_child(room)
	var camera=Camera2D.new()
	camera.position=Vector2.ZERO
	camera.zoom=Vector2.ONE*1.2
	scene.add_child(camera)
	room.set_npc_rendering_active(true)
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/hospital-interior-0912/isolated.png")
	quit()
