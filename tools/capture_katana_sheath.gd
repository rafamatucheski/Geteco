extends SceneTree
## Captura o Dante guardando e sacando a katana (clipe da greatsword) para conferir que a espada segue a
## mão e chega às costas. Janela real (não --headless); PNGs em evidence/katana-sheath/ (fora do Git).
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
class State extends RefCounted:
	var equipped_weapon := "fists"
	func owns_weapon(id: String) -> bool: return id == "katana"
	func weapons_allowed() -> bool: return true
	func can_attack() -> bool: return true

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(900, 900)
	var stage := Node3D.new(); root.add_child(stage)
	var floor_mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(20, 20); floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("8a7a5c"); floor_mesh.material_override = mat; stage.add_child(floor_mesh)
	var ground := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(20, 0.2, 20)
	shape.shape = box; shape.position.y = -0.1; ground.add_child(shape); stage.add_child(ground)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 30, 0); stage.add_child(sun)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.85, 0.85, 0.9); env.environment.ambient_light_energy = 0.9
	stage.add_child(env)
	var actor := ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true
	stage.add_child(actor)
	for i in 5: await physics_frame
	var gp := GAMEPLAY.new()
	stage.add_child(gp)
	# O _ready do Gameplay religa o processamento; aqui só o laço da captura avança o clipe.
	gp.set_physics_process(false); gp.set_process(false)
	gp.player = actor; gp.state = State.new(); gp.enabled = true; gp.health = 100.0
	gp._build_socket()
	# Câmera atrás e um pouco ao lado direito do Dante, para ver as costas e o braço direito.
	var forward: Vector3 = actor.skeleton.global_transform.basis.z.normalized()
	var camera := Camera3D.new(); stage.add_child(camera)
	camera.global_position = actor.global_position - forward * 2.6 + Vector3(0, 1.7, 0) + actor.skeleton.global_transform.basis.x.normalized() * -1.0
	camera.look_at(actor.global_position + Vector3(0, 1.1, 0))
	camera.make_current()
	gp._update_back_katana("fists")
	for i in 10: await physics_frame
	await shot("0_costas")
	var plan := [["katana", "1_sacar"], ["fists", "2_guardar"]]
	for step in plan:
		gp._update_back_katana(step[0])
		var total: float = gp._sheath_length
		print("STEP ", step[1], " clip=", gp._sheath_clip, " total=", total)
		for k in 6:
			var target := total * k / 5.0
			while gp._sheath_age < target - 0.0001 and gp._sheath_clip != "":
				gp._update_sheath(1.0 / 60.0); gp._update_back_katana(step[0]); await physics_frame
			print("SHOT ", step[1], " ", k, " age=", gp._sheath_age, " clip=", gp._sheath_clip)
			await shot("%s_%d" % [step[1], k])
		for i in 20: gp._update_sheath(1.0 / 60.0); gp._update_back_katana(step[0]); await physics_frame
	await shot("3_costas_final")
	quit()

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/katana-sheath/%s.png" % label))
