extends SceneTree
## Katana na mão fora do golpe (pedido de 19/10/2026: "segura e corre como se estivesse segurando um
## graveto para frente"). Contratos de `KatanaMoveset` e, no esqueleto real do Dante, da pose resolvida:
## - a lâmina fica para cima em todo instante do passo e nunca aponta para a frente;
## - parado: duas mãos; andando: só a direita; correndo: lâmina deitada para trás; em guarda: anda com
##   as duas mãos, mas corre com uma;
## - folga da lâmina até a cabeça e o ombro, e as palmas chegam ao cabo;
## - saindo do golpe do Mixamo, a lâmina e a mão não saltam de um quadro para o outro;
## - com os clipes da greatsword (19/10/2026, pedido do usuário): Great Sword Idle, Walk e Run, fio para o
##   inimigo e pé de apoio sem deslizar demais. O carregar procedural fica como reserva sem a biblioteca.
## Lógica e geometria só (pode rodar headless); a aparência fica com tools/capture_katana_locomotion.gd.
const MOVES := preload("res://gameplay/KatanaMoveset.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const KATANA := preload("res://gameplay/KatanaModel.gd")
const DT := 1.0 / 60.0
## Raio da cabeça com cabelo (WeaponRigPose.HEAD_CLEARANCE_CARRY em V2) + 2 cm.
const HEAD_CLEARANCE := 0.16
## Só o soquete da arma: polícia, áudio e efeitos do `_ready` real precisam do mundo inteiro.
class CarryGameplay extends "res://gameplay/Gameplay.gd":
	func _ready() -> void:
		_build_socket()

class State extends RefCounted:
	var equipped_weapon := "katana"
	func owns_weapon(id: String) -> bool: return id == "katana"
	func weapons_allowed() -> bool: return true
	func can_attack() -> bool: return true
	func get_ammo(_id: String) -> Dictionary: return {}

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func blade(pose: Dictionary) -> Vector3:
	return -((pose.basis as Basis).z).normalized()

## Câmera do jogo atrás e acima do Dante (CameraRig.EXTERIOR_OFFSET, 45°), olhando para a frente e para baixo.
const GAME_VIEW := Vector3(0, -1, -1) / sqrt(2.0)

## Anda `seconds` na velocidade dada e devolve a pior lâmina (menor Y, maior avanço para a frente e menor
## fração do comprimento visível na câmera do jogo vista de trás) depois de `skip` segundos, e a última pose.
func settle(moves, seconds: float, speed: float, ready := false, skip := 0.6) -> Dictionary:
	var lowest := 1.0
	var forward := -1.0
	var visible := 1.0
	var pose: Dictionary = {}
	var phase := 0.0
	for i in int(seconds / DT):
		phase = fposmod(phase + speed * DT / lerpf(1.8, 3.4, smoothstep(3.8, 6.0, speed)), 1.0)
		pose = moves.update(DT, speed, phase, 0.0, 0.0, ready, -1, 10.0)
		if i >= int(skip / DT):
			lowest = minf(lowest, blade(pose).y)
			forward = maxf(forward, -blade(pose).z)
			visible = minf(visible, sqrt(maxf(0.0, 1.0 - pow(blade(pose).dot(GAME_VIEW), 2.0))))
	return {"pose": pose, "lowest": lowest, "forward": forward, "visible": visible}

func run() -> void:
	contracts()
	await skeleton_checks()
	print("KATANA_CARRY checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func contracts() -> void:
	var moves = MOVES.new()
	var idle := settle(moves, 1.5, 0.0)
	check(idle.pose.left_solve and idle.pose.support_locked and is_equal_approx(float(idle.pose.left_weight), 1.0), "parado: as duas mãos no cabo")
	check(idle.lowest > 0.85 and idle.forward < 0.0, "parado: lâmina em pé (y mín %.2f), sem apontar para a frente (%.2f)" % [idle.lowest, idle.forward])
	var walk := settle(moves, 1.5, 3.5)
	check(not walk.pose.left_solve and float(walk.pose.left_weight) < 0.001, "andando: só a mão direita, a esquerda balança com o passo")
	check(walk.lowest > 0.8 and walk.forward < -0.05, "andando: lâmina para cima (y mín %.2f) e um pouco para trás (frente máx %.2f)" % [walk.lowest, walk.forward])
	var sprint := settle(moves, 1.5, 6.5)
	check(sprint.lowest > 0.65 and sprint.forward < -0.25, "correndo: lâmina para trás e para cima por cima do ombro (y mín %.2f, frente máx %.2f)" % [sprint.lowest, sprint.forward])
	# Antes (lâmina 45° para trás correndo) só 19% dela aparecia na câmera do jogo com o Dante de costas.
	for state in [["parado", idle], ["andando", walk], ["correndo", sprint]]:
		check(state[1].visible > 0.5, "%s: de costas para a câmera do jogo, %.0f%% da lâmina aparece na tela" % [state[0], state[1].visible * 100.0])
	var guard := settle(moves, 1.5, 3.5, true)
	check(guard.pose.support_locked and guard.lowest > 0.85 and guard.forward < 0.0, "em guarda andando: duas mãos e lâmina em pé")
	var guard_run := settle(moves, 1.5, 6.5, true)
	check(not guard_run.pose.left_solve, "em guarda, correr solta a mão esquerda")
	# Inércia: arrancar parado direto para a corrida e frear de uma vez.
	moves = MOVES.new()
	settle(moves, 1.0, 0.0)
	var start := settle(moves, 0.6, 6.5, false, 0.0)
	var stop := settle(moves, 0.8, 0.0, false, 0.0)
	check(absf(moves._lag) < 0.01, "a inércia da ponta assenta depois de parar (%.3f rad)" % moves._lag)
	check(start.lowest > 0.45 and stop.forward < 0.05, "arrancar e frear balançam a ponta sem ela descer nem apontar para a frente (y mín %.2f, frente máx %.2f)" % [start.lowest, stop.forward])
	# Meia-volta andando: a ponta sai para fora da curva no máximo TURN_LAG_MAX (+ folga da mola) e volta.
	moves = MOVES.new()
	settle(moves, 1.0, 3.5)
	var yaw := 0.0
	var widest := 0.0
	var lowest := 1.0
	for i in 40:
		yaw = lerp_angle(yaw, PI, 1.0 - exp(-14.0 * DT))
		var turning: Dictionary = moves.update(DT, 3.5, 0.0, 0.0, yaw, false, -1, 10.0)
		widest = maxf(widest, absf(moves._turn_lag))
		lowest = minf(lowest, blade(turning).y)
	check(widest > 0.03 and widest < MOVES.TURN_LAG_MAX * 1.3, "meia-volta: a ponta sai para fora da curva (%.3f rad) sem passar do teto" % widest)
	check(lowest > 0.75, "meia-volta: lâmina continua para cima (y mín %.2f)" % lowest)
	# Corte de reserva (sem clipes do Mixamo): duas mãos e a lâmina chega à frente no contato.
	moves = MOVES.new()
	settle(moves, 1.0, 0.0)
	var cut: Dictionary = moves.update(DT, 0.0, 0.0, 0.0, 0.0, true, 0, MOVES.CONTACT[0])
	check(cut.melee_action and cut.support_locked and blade(cut).z < -0.8, "corte de reserva com as duas mãos e a lâmina à frente no contato")

## No Dante de verdade, com os clipes da greatsword: parado, andando e correndo tocam Great Sword Idle, Walk
## e Run, o fio fica para o inimigo, a lâmina longe da cabeça e o pé de apoio quase não desliza; o golpe
## entra e sai sem salto. Depois, sem o Walk na biblioteca, o carregar procedural (reserva).
func skeleton_checks() -> void:
	var stage := Node3D.new(); root.add_child(stage)
	var ground := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(400, 0.2, 400)
	shape.shape = box; shape.position.y = -0.1; ground.add_child(shape); stage.add_child(ground)
	var actor := ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true
	stage.add_child(actor)
	for i in 5: await physics_frame
	var gp := CarryGameplay.new()
	gp.process_mode = Node.PROCESS_MODE_DISABLED
	gp.player = actor; gp.state = State.new(); gp.enabled = true; gp.health = 100.0
	stage.add_child(gp)
	KATANA.build(gp.gun, false, Color("68cfff"))
	gp.gun.visible = true
	actor.set_combat_weapon_mount(gp.gun, KATANA.GRIP)
	var step := func() -> void:
		gp._update_combat_clip(DT)
		gp._update_weapon_pose(DT)
		await physics_frame
	check(gp._sword_locomotion_clips(), "biblioteca tem Great Sword Idle, Walk e Run")
	for state in [["parado", 0.0, actor.SWORD_IDLE], ["andando", 3.5, actor.SWORD_WALK], ["correndo", 6.5, actor.SWORD_RUN]]:
		actor.automatic_direction = Vector3.FORWARD if state[1] > 0.0 else Vector3.ZERO
		actor.speed = state[1]
		for i in 80: await step.call()
		var playing := true
		var heard := {}
		var worst_head := INF
		var edge_sum := 0.0
		var feet: Array = []
		for i in 60:
			await step.call()
			playing = playing and actor.animation.assigned_animation == state[2] and actor.combat_weapon_pose.get("native_sword", false)
			heard[actor.animation.assigned_animation] = true
			worst_head = minf(worst_head, clearance(actor, gp.gun).head)
			var body: Basis = actor.visual.global_basis.orthonormalized().inverse()
			var d: Vector3 = body * -(gp.gun.global_basis.z as Vector3).normalized()
			var edge: Vector3 = body * (gp.gun.global_basis.x as Vector3).normalized()
			# Parado e andando: fio para baixo e para a frente. Correndo a espada vai arrastada atrás: fio para fora.
			var want := Vector3(0, -1, -1)
			if state[2] == actor.SWORD_RUN: want = actor.visual.to_local(gp.gun.global_transform * Vector3(0, 0, -0.6)) * Vector3(1, 0, 1)
			want = (want - d * want.dot(d)).normalized()
			edge_sum += edge.dot(want) / 60.0
			var sk: Skeleton3D = actor.skeleton
			var low := {}
			for side in ["Left", "Right"]:
				var foot := sk.to_global(sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin)
				if low.is_empty() or foot.y < low.y: low = {"side": side, "y": foot.y, "at": foot}
			feet.append(low)
		check(playing, "%s: toca %s com a katana na pegada do clipe (tocou %s)" % [state[0], state[2], heard.keys()])
		check(edge_sum > 0.6, "%s: fio para o inimigo (%.2f; 1 = certo, 0 = de lado)" % [state[0], edge_sum])
		check(worst_head > HEAD_CLEARANCE, "%s: lâmina longe da cabeça (%.3f m do centro)" % [state[0], worst_head])
		if state[1] > 0.0:
			# Pé de apoio: o mais baixo, perto do chão, no mesmo lado de um quadro para o outro.
			var floor_y := INF
			for f in feet: floor_y = minf(floor_y, f.y)
			var slips: Array[float] = []
			for i in range(1, feet.size()):
				if feet[i].side == feet[i - 1].side and feet[i].y < floor_y + 0.02 and feet[i - 1].y < floor_y + 0.02:
					slips.append(Vector2(feet[i].at.x - feet[i - 1].at.x, feet[i].at.z - feet[i - 1].at.z).length() / DT)
			slips.sort()
			var slip: float = slips[slips.size() / 2] if not slips.is_empty() else INF
			check(slip < state[1] * 0.35, "%s: pé de apoio desliza %.2f m/s (%.0f%% da velocidade)" % [state[0], slip, slip / state[1] * 100.0])
	# Golpe andando e volta à locomoção: tudo é clipe com a mesma pegada, sem salto da lâmina.
	actor.automatic_direction = Vector3.FORWARD
	actor.speed = 3.5
	for i in 40: await step.call()
	gp._play_katana_clip()
	check(gp._clip_name.begins_with("mixsword/gs_"), "golpe da katana usa o clipe do Mixamo")
	var exit: float = await strike_exit(actor, gp, step)
	check(exit < 15.0, "saindo do golpe a lâmina gira no máximo %.1f°/quadro (sem salto)" % exit)
	check(actor.animation.assigned_animation == actor.SWORD_WALK, "depois do golpe volta ao Great Sword Walk")
	# Reserva sem a biblioteca: tira o Walk (só em memória) e confere o carregar procedural.
	(actor.animation.get_animation_library("mixsword") as AnimationLibrary).remove_animation("gs_walk")
	check(not gp._sword_locomotion_clips(), "sem o Walk na biblioteca, volta ao carregar procedural")
	for state in [["parado", 0.0], ["andando", 3.5], ["correndo", 6.5]]:
		actor.automatic_direction = Vector3.FORWARD if state[1] > 0.0 else Vector3.ZERO
		actor.speed = state[1]
		for i in 80: await step.call()
		var worst_head := INF
		var worst_shoulder := INF
		var worst_reach := 0.0
		var worst_support := 0.0
		for i in 40:
			await step.call()
			var gaps := clearance(actor, gp.gun)
			worst_head = minf(worst_head, gaps.head)
			worst_shoulder = minf(worst_shoulder, gaps.shoulder)
			var pose: Dictionary = actor.combat_weapon_pose
			# A lâmina é posta na palma direita realizada; o erro dela é o alcance do braço até o pedido.
			worst_reach = maxf(worst_reach, actor.visual.to_local(actor.combat_palm_position("Right")).distance_to(pose.right))
			if pose.get("support_locked", false):
				worst_support = maxf(worst_support, actor.combat_palm_position("Left").distance_to(gp.gun.global_transform * (KATANA.GRIP + MOVES.SUPPORT)))
		check(worst_head > HEAD_CLEARANCE, "reserva %s: lâmina longe da cabeça (%.3f m do centro)" % [state[0], worst_head])
		check(worst_shoulder > 0.08, "reserva %s: lâmina por fora do ombro (%.3f m da articulação)" % [state[0], worst_shoulder])
		check(worst_reach < 0.04, "reserva %s: a mão direita chega aonde a pose pede (erro máx %.3f m)" % [state[0], worst_reach])
		check(worst_support < 0.035, "reserva %s: mão esquerda no cabo quando segura com as duas (erro máx %.3f m)" % [state[0], worst_support])
	# Golpe na reserva: do clipe ao carregar procedural, a lâmina gira com mistura (antes, até 34°/quadro).
	actor.automatic_direction = Vector3.FORWARD
	actor.speed = 3.5
	for i in 40: await step.call()
	gp._play_katana_clip()
	exit = await strike_exit(actor, gp, step)
	check(exit < 15.0, "reserva: saindo do golpe a lâmina gira no máximo %.1f°/quadro (sem salto)" % exit)
	check(actor.combat_weapon_pose.get("right_solve", false) and blade(actor.combat_weapon_pose).y > 0.5, "reserva: depois do golpe volta ao carregar com a lâmina para cima")
	stage.queue_free()
	await process_frame

## Maior giro da lâmina por quadro nos 30 quadros depois de o golpe acabar.
func strike_exit(actor, gp, step: Callable) -> float:
	var previous := Vector3.ZERO
	var exit_frames := -1
	var worst := 0.0
	while exit_frames < 30:
		await step.call()
		var direction: Vector3 = actor.visual.global_basis.inverse() * -(gp.gun.global_basis.z as Vector3).normalized()
		if exit_frames >= 0 and previous != Vector3.ZERO: worst = maxf(worst, rad_to_deg(previous.angle_to(direction)))
		previous = direction
		if gp._clip_name == "" or exit_frames >= 0: exit_frames += 1
	return worst

func clearance(actor, gun: Node3D) -> Dictionary:
	var sk: Skeleton3D = actor.skeleton
	var hilt: Vector3 = gun.global_transform * Vector3(0, 0, -0.12)
	var tip: Vector3 = gun.global_transform * KATANA.TIP
	var head := sk.to_global(sk.get_bone_global_pose(sk.find_bone("Head")).origin)
	var head_end := sk.find_bone("head_end")
	head = head.lerp(sk.to_global(sk.get_bone_global_pose(head_end).origin), 0.4) if head_end >= 0 else head + Vector3.UP * 0.10
	var shoulder := sk.to_global(sk.get_bone_global_pose(sk.find_bone("RightArm")).origin)
	return {"head": head.distance_to(Geometry3D.get_closest_point_to_segment(head, hilt, tip)),
		"shoulder": shoulder.distance_to(Geometry3D.get_closest_point_to_segment(shoulder, hilt, tip))}
