extends SceneTree
## Captura a guarda e os três golpes da greatsword na katana do Dante (janela real, não --headless).
## PNGs em evidence/katana-attacks/ (fora do Git).
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const KATANA := preload("res://gameplay/KatanaModel.gd")
class State extends RefCounted:
	var equipped_weapon := "katana"
	func owns_weapon(id: String) -> bool: return id == "katana"
	func weapons_allowed() -> bool: return true
	func can_attack() -> bool: return true

var gp
var actor

func _initialize() -> void: run.call_deferred()

func step(delta: float) -> void:
	gp._update_combat_clip(delta)
	gp._update_weapon_pose(delta)
	await physics_frame

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
	actor = ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true
	stage.add_child(actor)
	for i in 5: await physics_frame
	gp = GAMEPLAY.new()
	stage.add_child(gp)
	gp.set_physics_process(false); gp.set_process(false)
	gp.player = actor; gp.state = State.new(); gp.enabled = true; gp.health = 100.0
	gp._build_socket()
	KATANA.build(gp.gun, false, Color("68cfff"))
	gp.gun.visible = true
	actor.set_combat_weapon_mount(gp.gun, Vector3(0, 0, 0.04))
	# Câmera ao lado direito do Dante: a lâmina apontando para a frente aparece inteira, sem encurtar.
	var basis: Basis = actor.skeleton.global_transform.basis.orthonormalized()
	var camera := Camera3D.new(); stage.add_child(camera)
	camera.global_position = actor.global_position - basis.x * 3.6 + basis.z * 0.6 + Vector3(0, 1.3, 0)
	camera.look_at(actor.global_position + Vector3(0, 1.0, 0))
	camera.make_current()
	for i in 30: await step(1.0 / 60.0)
	await shot("0_guarda")
	for combo in 3:
		gp._katana_combo = combo - 1
		gp._play_katana_clip()
		var attack: Array = gp.KATANA_ATTACKS[combo]
		var total: float = (float(attack[3]) - float(attack[1])) / gp.KATANA_ATTACK_RATE
		var contact: float = gp._katana_contact_time()
		var times := [0.0, contact * 0.5, contact, contact + (total - contact) * 0.5]
		var age := 0.0
		for k in times.size():
			while age < times[k]:
				await step(1.0 / 60.0); age += 1.0 / 60.0
			await shot("%d_golpe_%d" % [combo + 1, k])
		while gp._clip_name != "":
			await step(1.0 / 60.0)
		for i in 10: await step(1.0 / 60.0)
	quit()

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/katana-attacks/%s.png" % label))
