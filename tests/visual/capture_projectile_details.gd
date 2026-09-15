extends SceneTree
## Render the actual production projectile sprites at native and inspection scale.
const BULLET := preload("res://guns/Bullet.tscn")
const CATALOG := preload("res://guns/WeaponCatalog.gd")

func _initialize() -> void:
	run.call_deferred()

func label_at(world: Node, text: String, at: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	world.add_child(label)

func run() -> void:
	root.size = Vector2i(1080, 650)
	root.content_scale_size = root.size
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1080, 650)
	backdrop.color = Color("182126")
	world.add_child(backdrop)
	label_at(world, "PROJÉTEIS", Vector2(42, 25), 32, Color("f2e9d7"))
	label_at(world, "TAMANHO DO JOGO", Vector2(235, 85), 16, Color("92a7ae"))
	label_at(world, "DETALHE ×5", Vector2(630, 85), 16, Color("92a7ae"))
	var weapons := ["pistol", "smg", "shotgun", "ak47", "hunting_rifle", "rpg"]
	for index in weapons.size():
		var id: String = weapons[index]
		var data: Dictionary = CATALOG.get_weapon(id)
		var y := 152.0 + index * 77.0
		label_at(world, data.short_label, Vector2(42, y - 10), 18, Color("dce4e2"))
		for magnification in [1.0, 5.0]:
			var bullet := BULLET.instantiate()
			bullet.lifetime = 30
			world.add_child(bullet)
			bullet.set_physics_process(false)
			# Exercise the Player's late-assignment spawn order.
			bullet.tracer_color = data.tracer_color
			bullet.speed = data.projectile_speed
			bullet.is_explosive = data.get("is_explosive", false)
			bullet.position = Vector2(325 if magnification == 1.0 else 790, y)
			bullet.scale = Vector2.ONE * magnification
	await process_frame
	await RenderingServer.frame_post_draw
	var output := "D:/geteco/artifacts/projectiles-0913"
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output.path_join("projectile-details.png"))
	print("PROJECTILE_CAPTURE ", output)
	quit()
