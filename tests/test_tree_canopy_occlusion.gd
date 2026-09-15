extends SceneTree
## Ator atrás do tronco deve ficar sob a copa; à frente, continua visível.
## Antes, o ator (z 10) era pintado sobre qualquer árvore e parecia em pé nela.
## A lógica (quem está atrás) roda em qualquer driver; a contagem de pixels
## cobertos só vale com renderização real, então é pulada em --headless.
const OUT := "res://docs/measurements/tree-occlusion-0914/"
const STREET_TREE := preload("res://geodata/nature/ProceduralStreetTree.gd")
const PINE_3D := preload("res://world/mountain_pass/MountainPine3D.gd")
const OCCLUSION := preload("res://systems/interiors/ExteriorOcclusion.gd")
const ACTOR_COLOR := Color(1, 0, 1)
var failures: Array[String] = []
var world: Node2D
var camera: Camera2D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _actor() -> CharacterBody2D:
	var script := GDScript.new()
	script.source_code = "extends CharacterBody2D\nvar sprite_3d_display: Sprite2D\n"
	script.reload()
	var body := CharacterBody2D.new()
	body.set_script(script)
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 6.0
	body.add_child(shape)
	var image := Image.create(20, 44, false, Image.FORMAT_RGBA8)
	image.fill(ACTOR_COLOR)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	# Pés na origem do corpo, como os atores reais.
	sprite.position = Vector2(0, -22)
	body.add_child(sprite)
	body.z_index = 10
	world.add_child(body)
	body.set("sprite_3d_display", sprite)
	return body

func _zone(tree: Node) -> Area2D:
	for child in tree.get_children():
		if child.get_script() == OCCLUSION: return child
	return null

func _settle() -> void:
	for i in 4: await physics_frame
	for i in 2: await process_frame

func _magenta_pixels(actor: CharacterBody2D) -> int:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var sprite: Sprite2D = actor.get("sprite_3d_display")
	var rect := sprite.global_transform * sprite.get_rect()
	var view := Vector2(root.size)
	var from := Vector2i(((rect.position - camera.global_position) * camera.zoom + view * .5).floor())
	var to := Vector2i(((rect.end - camera.global_position) * camera.zoom + view * .5).ceil())
	var count := 0
	for y in range(maxi(from.y, 0), mini(to.y, image.get_height())):
		for x in range(maxi(from.x, 0), mini(to.x, image.get_width())):
			var c := image.get_pixel(x, y)
			if c.r > .9 and c.b > .9 and c.g < .1: count += 1
	return count

func _case(label: String, tree: Node2D, behind_offset: Vector2) -> void:
	var zone := _zone(tree)
	check(zone != null, label + ": árvore cria a zona de oclusão")
	if zone == null: return
	var actor := _actor()
	camera.position = tree.global_position + Vector2(0, -30)
	actor.global_position = tree.global_position + behind_offset
	await _settle()
	check(zone.overlay.visible, label + ": ator atrás do tronco fica sob a copa")
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		var covered := await _magenta_pixels(actor)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + "-behind.png"))
		zone.set_process(false)
		zone.overlay.hide()
		await process_frame
		var bare := await _magenta_pixels(actor)
		zone.set_process(true)
		print("%s pixels do ator visíveis: com oclusão=%d sem=%d" % [label, covered, bare])
		check(bare > 0 and covered < bare * .8, label + ": copa cobre de fato parte do ator atrás")
	actor.global_position = tree.global_position + Vector2(behind_offset.x, 45)
	await _settle()
	check(not zone.overlay.visible, label + ": ator à frente do tronco não é coberto")
	if rendered:
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + "-ahead.png"))
	actor.global_position = tree.global_position + Vector2(400, 400)
	await _settle()
	check(not zone.overlay.visible, label + ": ator longe não liga o overlay")
	actor.queue_free()
	await _settle()

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	root.size = Vector2i(900, 700)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("56604f"))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * 4
	world.add_child(camera)
	camera.make_current()
	for style in [STREET_TREE.TreeStyle.STREET, STREET_TREE.TreeStyle.PINE, STREET_TREE.TreeStyle.COASTAL]:
		var tree := STREET_TREE.new()
		tree.tree_style = style
		tree.crown_scale = 1.25
		tree.variant_seed = 7
		tree.position = Vector2(style * 600, 0)
		world.add_child(tree)
		await _case("street-style%d" % style, tree, Vector2(0, -22))
	for variant in [3, 4, 0]:
		var pine := PINE_3D.new()
		pine.variant_seed = variant
		pine.tree_scale = .9
		pine.position = Vector2(variant * 600, 900)
		world.add_child(pine)
		for i in 3: await process_frame
		await _case("pine3d-variant%d" % variant, pine, Vector2(0, -34))
	print("TREE_CANOPY_OCCLUSION failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
