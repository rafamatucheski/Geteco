extends SceneTree

const CIVIL := preload("res://prototypes/living_cast/LivingCivil.gd")
const LAB := preload("res://prototypes/living_cast/LivingCastLab.gd")

func _init() -> void: call_deferred("run")

func label(parent: Node, value: String, pos: Vector2, size: int = 18) -> void:
	var text := Label.new()
	text.text = value
	text.position = pos
	text.add_theme_font_size_override("font_size", size)
	text.add_theme_color_override("font_color", Color("e3dac7"))
	parent.add_child(text)

func run() -> void:
	root.size = Vector2i(1440, 1000)
	root.content_scale_size = root.size
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	RenderingServer.set_default_clear_color(Color("202a32"))
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	label(layer, "BREAKWATER / LABORATORIO DE DIVERSIDADE", Vector2(35,25), 20)
	label(layer, "Seis pessoas. Seis carrocerias. Comportamentos distintos.", Vector2(35,58), 30)
	var roles := ["Foge do perigo", "Trabalhador portuario", "Mochila e cabelo longo", "Passo mais lento", "Revida com socos", "Resposta armada"]
	var people: Array = []
	var cars: Array = []
	for i in 6:
		var actor := CIVIL.new()
		actor.appearance = i
		actor.response = 1 if i == 4 else (2 if i == 5 else 0)
		actor.roam = false
		actor.position = Vector2(-2000, i * 200)
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor.sprite_3d_display.hide()
		# Larger render ONLY for the review sheet, never the gameplay default.
		actor.viewport.size = Vector2i(220, 320)
		var camera3d := actor.viewport.get_child(0) as Camera3D
		camera3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera3d.size = 1.8
		camera3d.position = Vector3(2, 1.8, -4)
		camera3d.look_at(Vector3(0,0.72,0))
		var portrait := TextureRect.new()
		portrait.texture = actor.viewport.get_texture()
		portrait.position = Vector2(20 + i * 235,120)
		portrait.size = Vector2(220,320)
		layer.add_child(portrait)
		label(layer, CIVIL.NAMES[i], Vector2(35 + i * 235,440), 21)
		label(layer, roles[i], Vector2(35 + i * 235,470), 15)
		people.append(actor)
		var car := LAB.make_car(i)
		car.get_node("Camera").enabled = false
		car.position = Vector2(125 + i * 235,650)
		car.scale = Vector2.ONE * 2.3
		scene.add_child(car)
		car.set_physics_process(false)
		cars.append(car)
		label(layer, ["Seda", "Perua / bagageiro", "Furgao de entregas", "Picape / cacamba", "Cupe / aerofolio", "Taxi"][i], Vector2(35 + i * 235,720), 18)
	label(layer, "VEICULOS DIRIGIVEIS / colisao, amassado localizado e reparo", Vector2(35,545), 23)
	label(layer, "Prototipo isolado. Populacao e trafego da cidade nao foram alterados.", Vector2(35,875), 21)
	label(layer, "Malhas articuladas, materiais compartilhados e pecas agrupadas por articulacao.", Vector2(35,915), 18)
	for frame in 15: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("D:/geteco/living_cast_lineup.png")
	print("LIVING_CAST_CAPTURE result=%d" % result)
	# A second clearly labeled demonstration of the timed death and impact states.
	people[1].take_damage(1000, true)
	cars[0]._apply_crash_deformation(Vector2.LEFT, 350, cars[0].to_global(Vector2(35,0)))
	await create_timer(0.8).timeout
	label(layer, "DEMONSTRACAO: queda do portuario e impacto no seda (nao e teste de percurso)", Vector2(35,810), 21)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/living_cast_damage.png")
	scene.queue_free()
	await process_frame
	quit(result)
