extends SceneTree
var failures: Array[String] = []
var actors: Array[Node2D] = []
var scene: Node2D
const OUTPUT := "res://docs/measurements/death-variants-0912/"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")

func step(frames: int) -> void:
	for frame in frames:
		for actor in actors: actor._physics_process(1.0 / 60.0)
		await physics_frame

func _run() -> void:
	seed(910)
	create_timer(30).timeout.connect(func(): printerr("CHARACTER_FALL TIMEOUT"); quit(2))
	root.size = Vector2i(1300, 650)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2.ZERO, Vector2(2000, 0), Vector2(2000, 1000), Vector2(0, 1000)])
	backdrop.color = Color("b9c1bf")
	scene.add_child(backdrop)
	var scripts := ["AnimatedPedestrian3D", "PoliceOfficer", "Paramedic", "Firefighter", "Mortician", "world/mountain_pass/WinterResident", "CarjackedDriver"]
	for i in scripts.size():
		var actor = load("res://" + scripts[i] + ".gd").new()
		actor.set_meta("quiet_patrol", true)
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.position = Vector2(95 + i * 180, 330)
		actor.scale = Vector2.ONE * 3.5
		actors.append(actor)
		var title := Label.new()
		title.text = ["Civil", "Polícia", "Paramédico", "Bombeiro", "IML", "Morador", "Motorista"][i]
		title.position = Vector2(45 + i * 180, 110)
		title.add_theme_color_override("font_color", Color("182424"))
		scene.add_child(title)
	await physics_frame
	# As texturas dos SubViewports precisam ser apresentadas antes da captura.
	for frame in 3: await process_frame
	await capture("01_em_pe")
	for actor in actors:
		actor.take_damage(1000)
		check(actor.fall_presentation.active and is_zero_approx(actor.fall_presentation.rig.rotation.x), actor.get_script().resource_path + ": morte inicia queda sem salto de pose")
	await step(18)
	for actor in actors:
		var fall = actor.fall_presentation
		check(fall.rig.rotation.x > 0.05 and fall.rig.rotation.x < 1.3, "Corpo passa por inclinação intermediária")
		check(fall.shadow.get_parent() == fall.viewport and fall.shadow.global_basis.y.normalized().dot(Vector3.UP) > 0.999, "Sombra permanece horizontal e separada do corpo")
	await capture("02_perda_equilibrio")
	await step(22)
	await capture("03_queda")
	await step(27)
	var poses: Array[Transform3D] = []
	for actor in actors:
		var fall = actor.fall_presentation
		check(not fall.active and absf(fall.rig.rotation.x - PI * 0.5) < 0.01, "Queda termina deitada")
		check(fall.shadow.global_basis.y.normalized().dot(Vector3.UP) > 0.999 and fall.shadow.scale.z > 2.0, "Sombra no chão acompanha a extensão do corpo")
		poses.append(fall.rig.transform)
	await capture("04_no_chao")
	await step(12)
	for i in actors.size():
		check(actors[i].fall_presentation.rig.transform.is_equal_approx(poses[i]), "Corpo permanece estável após a queda")
	var injured = load("res://AnimatedPedestrian3D.gd").new()
	injured.defer_presentation = true
	scene.add_child(injured)
	injured.set_physics_process(false)
	injured.position = Vector2(100, 550)
	injured.get_run_over(Vector2(120, 0))
	check(injured.viewport != null and injured.fall_presentation.active, "Atropelamento constrói apresentação adiada e anima a queda")
	check(injured.is_incapacitated and not injured.is_dead, "Queda leve mantém a vítima viva para a ambulância")
	for frame in 65:
		injured._physics_process(1.0 / 60.0)
		await physics_frame
	check(not injured.is_flying and not injured.fall_presentation.active, "Atropelamento termina sem giro contínuo")
	var original: Transform3D = injured.fall_presentation.initial_transform
	injured.fall_presentation.reset()
	check(injured.model_root.transform.is_equal_approx(original) and injured.fall_presentation.shadow.scale.is_equal_approx(Vector3.ONE), "Recuperação restaura postura e sombra de pé")
	var variants: Dictionary = {}
	for attempt in 32:
		injured.fall_presentation.start(injured, injured.model_root, injured.viewport)
		var fall = injured.fall_presentation
		fall.update(fall.duration)
		var rotations: Array[Vector3] = []
		for joint in fall.joints: rotations.append(joint.node.rotation)
		variants[fall.variant] = rotations
		check(not fall.active, "Variante termina sem atualização permanente")
		fall.reset()
	check(variants.size() == 4, "Sorteio exercita quatro variantes")
	for a in variants:
		for b in variants:
			if a < b: check(variants[a] != variants[b], "Variantes têm poses finais distintas")
	scene.queue_free()
	await process_frame
	print("CHARACTER_FALL: ", failures)
	quit(0 if failures.is_empty() else 1)
