extends SceneTree
## Captura o Dante com a katana parado, andando, correndo, parando, andando em guarda e golpeando
## andando, de três ângulos ao mesmo tempo (lado direito, frente-esquerda e a câmera alta do jogo,
## ortográfica, por trás na diagonal). Janela real (não --headless). Uma folha por estado em
## evidence/katana-locomotion/<rótulo>/ (fora do Git): colunas = ângulos, linhas = instantes.
## Também imprime ossos/lâmina no espaço do Actor, a folga da lâmina até cabeça e tronco e, nas
## transições, o giro da lâmina e o deslocamento da palma quadro a quadro (um salto aparece como pico).
## Uso: tools/run_godot_locked.sh --path . --script res://tools/capture_katana_locomotion.gd -- --label=antes
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const KATANA := preload("res://gameplay/KatanaModel.gd")
const TILE := Vector2i(360, 480)
const DT := 1.0 / 60.0
class State extends RefCounted:
	var equipped_weapon := "katana"
	func owns_weapon(id: String) -> bool: return id == "katana"
	func weapons_allowed() -> bool: return true
	func can_attack() -> bool: return true
	func get_ammo(_id: String) -> Dictionary: return {}

var gp
var actor
var label := "atual"
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
## Lâmina e palma do quadro anterior no espaço do Actor, e o registro quadro a quadro.
var _last_blade := Vector3.ZERO
var _last_asked := Vector3.ZERO
var _last_palm := Vector3.ZERO
var _trace: Array[String] = []

func _initialize() -> void: run.call_deferred()

func step(delta: float = DT) -> void:
	gp._update_combat_clip(delta)
	gp._update_weapon_pose(delta)
	await physics_frame
	_follow()
	var blade: Vector3 = actor.visual.global_basis.inverse() * -(gp.gun.global_basis.z as Vector3).normalized()
	var palm: Vector3 = actor.visual.to_local(actor.combat_palm_position("Right"))
	var pose: Dictionary = actor.combat_weapon_pose
	var asked: Vector3 = -((pose.basis as Basis).z).normalized() if pose.has("basis") else blade
	if _last_blade != Vector3.ZERO:
		# lâmina realizada / pedida pela pose / palma, por quadro
		_trace.append("%.0f°(%.0f°)/%.1fcm" % [rad_to_deg(_last_blade.angle_to(blade)), rad_to_deg(_last_asked.angle_to(asked)), _last_palm.distance_to(palm) * 100.0])
	_last_blade = blade
	_last_asked = asked
	_last_palm = palm

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/katana-locomotion/%s" % label))
	root.size = Vector2i(64, 64)
	var stage := Node3D.new(); root.add_child(stage)
	var floor_mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(400, 400); floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("8a7a5c"); floor_mesh.material_override = mat; stage.add_child(floor_mesh)
	var ground := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(400, 0.2, 400)
	shape.shape = box; shape.position.y = -0.1; ground.add_child(shape); stage.add_child(ground)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 30, 0); sun.shadow_enabled = true; stage.add_child(sun)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color("c9d3dc")
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
	for i in 3:
		var view := SubViewport.new(); view.size = TILE; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		root.add_child(view)
		var camera := Camera3D.new(); view.add_child(camera); camera.current = true
		views.append(view); cameras.append(camera)
	cameras[2].projection = Camera3D.PROJECTION_ORTHOGONAL
	cameras[2].size = 3.0
	# Parado por 1 s, quatro instantes.
	actor.automatic_direction = Vector3.ZERO
	for i in 60: await step()
	await sheet("1_parado", [0.0, 0.45, 0.45, 0.45])
	# Andando (3,5 m/s, como o jogador sem correr) e correndo (6,5 m/s), sempre para −Z.
	actor.automatic_direction = Vector3.FORWARD
	actor.speed = 3.5
	_trace.clear()
	for i in 70: await step()
	print("TRACE arrancar ", " ".join(_trace.slice(0, 24)))
	await sheet("2_andando", [0.0, 0.13, 0.13, 0.13])
	actor.speed = 6.5
	for i in 70: await step()
	await sheet("3_correndo", [0.0, 0.13, 0.13, 0.13])
	# Parar de correr: a transição para a guarda parada, quadro a quadro.
	actor.automatic_direction = Vector3.ZERO
	_trace.clear()
	await sheet("4_parando", [0.0, 0.10, 0.10, 0.30])
	print("TRACE parar ", " ".join(_trace.slice(0, 40)))
	# Em guarda (logo depois de um golpe): anda com as duas mãos. O relógio de combate não anda aqui.
	gp._katana_attack_clock = gp._combat_clock
	actor.automatic_direction = Vector3.FORWARD
	actor.speed = 3.5
	for i in 70: await step()
	await sheet("5_guarda_andando", [0.0, 0.13, 0.13, 0.13])
	gp._katana_attack_clock = -10.0
	for i in 60: await step()
	# Golpe andando: entrada no clipe e volta ao carregar.
	_trace.clear()
	await sheet("6_golpe_andando", [0.0, 0.05, 0.07], _strike_on_second_row)
	print("TRACE entrada ", " ".join(_trace))
	while gp._clip_name != "": await step()
	_trace.clear()
	await sheet("7_fim_do_golpe", [0.0, 0.05, 0.10, 0.25])
	print("TRACE saida ", " ".join(_trace))
	# Curva de 90° à esquerda andando: a ponta fica por fora da curva e volta.
	gp._katana_attack_clock = -10.0
	for i in 150: await step()
	_trace.clear()
	actor.automatic_direction = Vector3.LEFT
	await sheet("8_curva", [0.0, 0.07, 0.10, 0.30])
	print("TRACE curva ", " ".join(_trace))
	# Golpe saindo da guarda parada (antes era a "Great Sword Idle" do Mixamo, agora a pose procedural).
	actor.automatic_direction = Vector3.ZERO
	gp._katana_attack_clock = -10.0
	for i in 90: await step()
	_trace.clear()
	await sheet("9_golpe_parado", [0.0, 0.05, 0.07, 0.20], _strike_on_second_row)
	print("TRACE entrada_parado ", " ".join(_trace))
	quit()

func _strike_on_second_row(row: int) -> void:
	if row == 1: gp._play_katana_clip()

func _follow() -> void:
	var at: Vector3 = actor.global_position
	cameras[0].global_position = at + Vector3(4.4, 1.2, -0.2)
	cameras[0].look_at(at + Vector3(0, 1.05, -0.2))
	cameras[0].fov = 40.0
	cameras[1].global_position = at + Vector3(-2.9, 1.5, -3.3)
	cameras[1].look_at(at + Vector3(0, 1.05, 0))
	cameras[1].fov = 40.0
	# Câmera do jogo: por trás na diagonal (PREVIEW_HEADING = 45°), inclinação de ~36°.
	cameras[2].global_position = at + Vector3(0, 21.0, 29.0).rotated(Vector3.UP, PI / 4.0).normalized() * 30.0 + Vector3(0, 0.9, 0)
	cameras[2].look_at(at + Vector3(0, 0.9, 0))

## Ossos e lâmina no espaço do Actor (+X direita, −Z frente) e a menor folga entre o eixo da lâmina e
## o centro da cabeça (raio com cabelo ~0,14 m) e os ossos do tronco (a malha fica ~0,10–0,14 m fora).
func measure() -> void:
	var sk: Skeleton3D = actor.skeleton
	var line := "  "
	for bone in ["RightArm", "RightForeArm", "RightHand", "LeftHand"]:
		var p: Vector3 = actor.visual.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(bone)).origin))
		line += "%s=(%.2f,%.2f,%.2f) " % [bone, p.x, p.y, p.z]
	var gun: Node3D = gp.gun
	var hilt: Vector3 = gun.global_transform * Vector3(0, 0, -0.12)
	var tip: Vector3 = gun.global_transform * KATANA.TIP
	var d: Vector3 = actor.visual.global_basis.inverse() * (tip - hilt).normalized()
	var head_bone := sk.find_bone("Head")
	var head := sk.to_global(sk.get_bone_global_pose(head_bone).origin)
	var head_end := sk.find_bone("head_end")
	head = head.lerp(sk.to_global(sk.get_bone_global_pose(head_end).origin), 0.4) if head_end >= 0 else head + Vector3.UP * 0.10
	var body_min := INF
	for bone in ["Hips", "Spine01", "Spine02", "neck"]:
		var c := sk.to_global(sk.get_bone_global_pose(sk.find_bone(bone)).origin)
		body_min = minf(body_min, c.distance_to(Geometry3D.get_closest_point_to_segment(c, hilt, tip)))
	var shoulder := sk.to_global(sk.get_bone_global_pose(sk.find_bone("RightArm")).origin)
	var shoulder_gap := shoulder.distance_to(Geometry3D.get_closest_point_to_segment(shoulder, hilt, tip))
	var head_gap := head.distance_to(Geometry3D.get_closest_point_to_segment(head, hilt, tip))
	var tip_local: Vector3 = actor.visual.to_local(tip)
	var head_local: Vector3 = actor.visual.to_local(head)
	print(line, "head=(%.2f,%.2f,%.2f) blade_dir=(%.2f,%.2f,%.2f) tip=(%.2f,%.2f,%.2f) head_gap=%.3f shoulder_gap=%.3f body_gap=%.3f" % [head_local.x, head_local.y, head_local.z, d.x, d.y, d.z, tip_local.x, tip_local.y, tip_local.z, head_gap, shoulder_gap, body_min])

## Folha: uma linha por espera de `waits` (s, contada da linha anterior); cada linha tem os três ângulos
## do mesmo quadro. `before_row(row)` roda antes da espera da linha (ex.: disparar um golpe).
func sheet(name: String, waits: Array, before_row: Callable = Callable()) -> void:
	var image := Image.create(TILE.x * 3, TILE.y * waits.size(), false, Image.FORMAT_RGBA8)
	for row in waits.size():
		if before_row.is_valid(): before_row.call(row)
		var waited := 0.0
		while waited < float(waits[row]) - 0.0001:
			await step(); waited += DT
		await RenderingServer.frame_post_draw
		for col in 3:
			var tile := views[col].get_texture().get_image()
			tile.convert(Image.FORMAT_RGBA8)
			image.blit_rect(tile, Rect2i(Vector2i.ZERO, TILE), Vector2i(col * TILE.x, row * TILE.y))
		print("SHOT %s %d phase=%.2f speed=%.2f clip=%s" % [name, row, actor.phase, Vector2(actor.velocity.x, actor.velocity.z).length(), actor.combat_clip])
		measure()
	var path := ProjectSettings.globalize_path("res://evidence/katana-locomotion/%s/%s.png" % [label, name])
	image.save_png(path)
	print("SHEET ", path)
