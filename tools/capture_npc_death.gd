extends SceneTree
## Captura a queda de civis com os clipes de morte do Mixamo: um civil por direção de empurrão.
## Janela real (não --headless): grava PNGs em evidence/npc-death/ (fora do Git).
const MODEL := preload("res://assets/CivilianModel.gd")
const DEATH := preload("res://gameplay/MixamoDeath.gd")
const PUSHES := {"frente": Vector3(0, 0, 1), "tras": Vector3(0, 0, -1), "esquerda": Vector3(1, 0, 0), "direita": Vector3(-1, 0, 0)}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1400, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(30, 20)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("5c6670")
	floor_mesh.material_override = mat
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); stage.add_child(sun)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.85, 0.9); env.environment.ambient_light_energy = 0.8
	stage.add_child(env)
	var camera := Camera3D.new(); camera.position = Vector3(0, 5.5, 9.0); camera.fov = 48
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.4, 0))
	camera.make_current()
	var actors := []
	var index := 0
	for key in PUSHES:
		var actor := Node3D.new()
		actor.position = Vector3(index * 3.6 - 5.4, 0, 0)
		stage.add_child(actor)
		var model := MODEL.new()
		actor.add_child(model)
		actors.append({"key": key, "actor": actor, "model": model})
		index += 1
	for i in 10: await process_frame
	for item in actors:
		var ok: bool = DEATH.play(item.actor, item.model, PUSHES[item.key])
		print("DEATH ", item.key, " played=", ok, " clip=", item.actor.get_meta("mixamo_death_clip", ""))
	var shots := [0.05, 0.5, 1.2, 4.2]
	var elapsed := 0.0
	for step in shots.size():
		await create_timer(shots[step] - elapsed).timeout
		elapsed = shots[step]
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/npc-death/queda_%d.png" % step))
	for item in actors:
		var pelvis: Node3D = item.model.find_child("Pelvis", true, false)
		var head: Node3D = item.model.find_child("Head", true, false)
		print("FINAL ", item.key, " pelvis_y=", snappedf(pelvis.global_position.y, 0.01), " head_y=", snappedf(head.global_position.y, 0.01), " head_xz=", Vector2(head.global_position.x - item.actor.position.x, head.global_position.z).snapped(Vector2.ONE * 0.01))
	quit()
