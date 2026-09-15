extends SceneTree
const BLAST := preload("res://world/shared/combat/ExplosionVisual.gd")
func _initialize() -> void: run.call_deferred()
func caption(world: Node, text: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size",18)
	label.z_index = 40
	world.add_child(label)
func run() -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_size = Vector2i(1280,900)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var floor := Polygon2D.new()
	floor.polygon = PackedVector2Array([Vector2.ZERO,Vector2(1280,0),Vector2(1280,900),Vector2(0,900)])
	floor.color = Color("30393c")
	floor.z_index = -5
	world.add_child(floor)
	caption(world,"LATARIA / LUZES / CARCACA QUEIMADA",Vector2(45,24))
	for row in 2:
		for col in 3:
			var id := "union_sedan" if row==0 else "sport_coupe"
			var car = ModernTrafficFactory.spawn_parked_vehicle(world,"Review",Vector2(210+col*410,160+row*195),-0.3,id,0,Color("9ba955"))
			car.ensure_presentation()
			car.scale = Vector2.ONE * 2.6
			car.set_physics_process(false)
			car.set_process(false)
			if col == 1:
				for i in 4:
					car.body_model.apply_impact(Vector3(-0.68,0.81,2.20),Vector3.FORWARD,16)
				car.body_model.apply_impact(Vector3(-0.68,0.81,-2.2),Vector3.BACK,16)
			elif col == 2: car.body_model.char_body()
			car.body_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			caption(world,["INTEIRO","BATIDA NA TRASEIRA + FAROL","QUEIMADO"][col],Vector2(70+col*410,220+row*195))
	caption(world,"EXPLOSAO: PRESSAO, FOGO, FUMACA E FRAGMENTOS",Vector2(45,462))
	for i in 4:
		var effect = BLAST.spawn(world,Vector2(165+i*310,620),140,i==3)
		effect.set_process(false)
		effect.age = [0.07,0.22,0.58,1.3][i]
		effect.queue_redraw()
		caption(world,["70 ms","220 ms","580 ms","1,3 s"][i],Vector2(130+i*310,714))
	var fx := WeaponEffects.new()
	world.add_child(fx)
	caption(world,"TIRO / CAPSULA EM QUEDA / CAPSULA NO CHAO",Vector2(45,770))
	fx.spawn_muzzle_flash(Vector2(170,850),Vector2.RIGHT,{"flash_radius":10.0})
	fx.spawn_shell(Vector2(470,850),Vector2.RIGHT)
	fx.spawn_shell(Vector2(770,850),Vector2.RIGHT)
	for i in fx.get_child_count():
		var node = fx.get_child(i)
		node.set_process(false)
		if i == 0: node.age=0.012
		else:
			for frame in (9 if i==1 else 70): node._process(1.0/60.0)
		node.scale = Vector2.ONE * 2.4
		node.queue_redraw()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/effects-driving-0910/review.png")
	print("CAPTURE SAVED")
	quit()
