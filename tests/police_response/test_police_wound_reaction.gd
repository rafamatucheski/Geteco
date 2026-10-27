extends SceneTree
## Policial ferido (27/10/2026): o tiro tira ele do eixo (recua e não atira por um instante), uma
## rajada não o deixa travado, abaixo de metade da vida ele manca e segura o ferimento, e com a vida
## no fim pode curvar de dor. Contrato físico sem Main.tscn; não mede quadro nem aparência.
const OFFICER := preload("res://gameplay/PoliceAgent.gd")

class State extends RefCounted:
	var place_id := ""
	var region_id := "harbor"
	func weapons_allowed() -> bool: return true

class Controller extends Node3D:
	var state := State.new()
	var player: CharacterBody3D
	var police: Array = []
	var stars := 3
	var health := 100.0
	var last_known_valid := true
	var last_known := Vector3.ZERO
	var contact_age := 0.0
	var shots := 0
	func police_force_authorized() -> bool: return true
	func police_surrendering() -> bool: return false
	func police_can_arrest() -> bool: return false
	func pursuit_target() -> Node3D: return player
	func police_can_see(_officer: CharacterBody3D) -> bool: return true
	func police_shoot(_officer: CharacterBody3D, _amount: float, _weapon: String) -> void: shots += 1
	func report_contact(point: Vector3) -> void:
		last_known = point
		contact_age = 0.0
	func find_path(_from: Vector3, to: Vector3) -> PackedVector3Array: return PackedVector3Array([to])
	func police_arrest_warning(_actor: Node3D = null) -> void: pass
	func police_reload(_officer: Node3D, _weapon: String) -> void: pass
	func drop_ammo(_point: Vector3, _weapon: String) -> void: pass
	func drop_dead_weapon(_actor: Node3D, _weapon: String) -> void: pass

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("WOUND PASS " if ok else "WOUND FAIL ") + label)
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.4, 80)
	floor_shape.shape = box
	ground.add_child(floor_shape)
	ground.position = Vector3(0, -0.2, 0)
	world.add_child(ground)
	var controller := Controller.new()
	world.add_child(controller)
	var player := CharacterBody3D.new()
	player.position = Vector3(0, 0.05, -12)
	world.add_child(player)
	controller.player = player
	controller.last_known = player.position
	var officer: CharacterBody3D = OFFICER.new()
	officer.controller = controller
	officer.position = Vector3(0, 0.05, 0)
	world.add_child(officer)
	await frames(30)
	# Tiro vindo do jogador (de -Z para +Z): ele recua para +Z e não atira enquanto se recompõe.
	var shots_before := controller.shots
	var start: Vector3 = officer.global_position
	officer.receive_damage(12.0, player)
	check(officer.hurt_time > 0.2 and officer.hurt_time <= OFFICER.HURT_STAGGER.y + 0.001, "tiro tira o policial do eixo por um instante")
	var stagger: float = officer.hurt_time
	var steps := int(ceil(stagger * 60.0)) + 2
	# Recuo máximo durante o tranco: passado ele, o policial volta a andar na direção do jogador.
	var recoil := 0.0
	for index in steps:
		await physics_frame
		if officer.hurt_time > 0.0: recoil = maxf(recoil, officer.global_position.z - start.z)
	check(controller.shots == shots_before, "não atira enquanto se recompõe do tiro")
	check(recoil > 0.15, "recua no sentido da bala (%.2f m)" % recoil)
	check(officer.hurt_time == 0.0, "volta a agir depois do tranco")
	# Rajada: logo depois do tranco os tiros seguintes só balançam o tronco.
	officer.receive_damage(6.0, player)
	check(officer.hurt_time == 0.0, "rajada não emenda trancos (sem travar o policial)")
	# Pode estar na pausa entre rajadas (até 2,5 s): espera até 4 s.
	for index in 240:
		await physics_frame
		if controller.shots > shots_before: break
	check(controller.shots > shots_before, "volta a atirar depois de se recompor")
	# Abaixo de metade da vida: manca, segura o ferimento e anda mais devagar.
	officer.health = officer.max_health * 0.3
	officer._hurt_ready_at = -INF
	officer.receive_damage(2.0, player)
	await frames(4)
	check(officer.wounded(), "abaixo de metade da vida conta como ferido")
	var visual: Node3D = officer.visual
	check(float(visual.wound_hold) > 0.0, "mão livre vai ao ferimento")
	var body: Node = visual.get("body")
	if is_instance_valid(body) and "limp" in body:
		check(float(body.limp) > 0.3, "corpo visível manca (limp=%.2f)" % float(body.limp))
	# Vida no fim e tiro forte: em alguma tentativa ele curva de dor (chance de 55% por tranco).
	var doubled := false
	for attempt in 24:
		officer.health = officer.max_health * 0.25
		officer.hurt_time = 0.0
		officer._double_over = 0.0
		officer._hurt_ready_at = -INF
		officer._react_to_wound(Vector3.BACK, 20.0, 0.0)
		if officer._double_over > 0.0:
			doubled = true
			break
	check(doubled, "com a vida no fim um tiro forte o faz curvar de dor")
	if doubled and is_instance_valid(body) and "hurt_bend" in body:
		check(float(body.hurt_bend) == 1.0, "corpo visível curva o tronco")
		await frames(int(OFFICER.HURT_DOUBLE_OVER * 60.0) + 4)
		check(float(body.hurt_bend) == 0.0, "depois de curvado ele se levanta")
	# Morte continua igual: cai e para de agir.
	officer.receive_damage(500.0, player)
	check(officer.dead and not officer.is_physics_processing(), "tiro letal derruba o policial")
	print("WOUND checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
