extends SceneTree
func _initialize(): run.call_deferred()
func run():
	root.size=Vector2i(1280,720)
	var holder=Node2D.new()
	root.add_child(holder)
	holder.position=Vector2(640,400)
	holder.self_modulate.a=0
	var facade=load("res://world/mountain_pass/MountainStaticModelView.gd").new()
	holder.add_child(facade)
	facade.build_view(load("res://guns/ammunation/AmmunationFacade3D.gd"),12.0,65.0,Vector3(0,1.8,0))
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/ammunation-0910/facade-diagnostic.png")
	facade.viewport_3d.get_texture().get_image().save_png("D:/geteco/artifacts/ammunation-0910/facade-model.png")
	print("FACADE ",facade.position," ",facade.sprite_3d.position," ",facade.sprite_3d.scale)
	quit()
