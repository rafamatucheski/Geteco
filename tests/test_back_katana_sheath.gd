extends SceneTree
## Katana nas costas: fica presa à coluna quando guardada; ao equipar, o clipe da greatsword toca ao
## contrário (sacar) com a espada na mão, e ao trocar de arma toca para frente (guardar) até as costas.
## Também confere, no esqueleto real do Dante, que a espada na mão chega exatamente à posição das costas.
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")

class SheathGameplay extends "res://gameplay/Gameplay.gd":
	# Esta fixture aciona os métodos reais da bainha à mão. Só a preparação do soquete
	# deles é necessária; polícia, áudio e efeitos não relacionados precisam de um mundo completo.
	func _ready() -> void:
		_build_socket()

class State extends RefCounted:
	var owned := true
	var allowed := true
	var equipped_weapon := "fists"
	func owns_weapon(id: String) -> bool: return owned and id == "katana"
	func weapons_allowed() -> bool: return allowed
	func can_attack() -> bool: return allowed

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run_clip(gp, seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)): gp._update_sheath(1.0 / 60.0)

func run() -> void:
	await geometry()
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true
	stage.add_child(actor)
	await frames(3)
	var gp := SheathGameplay.new()
	gp.process_mode = Node.PROCESS_MODE_DISABLED
	gp.world = stage
	gp.player = actor
	gp.state = State.new()
	gp.enabled = true
	gp.health = 100.0
	stage.add_child(gp)
	check(gp.back_katana != null and gp.hand_katana != null, "katana das costas (coluna) e da mão (sacar/guardar) criadas")
	check(actor.animation.has_animation("mixsword/sheathe_greatsword"), "clipe da greatsword carregado")
	gp._update_back_katana("fists")
	check(gp.back_katana.visible and not gp.hand_katana.visible, "sem katana na mão, ela fica nas costas")
	gp._update_back_katana("katana")
	check(gp._sheath_clip == "mixsword/sheathe_greatsword" and gp._sheath_kind == "draw", "equipar a katana toca o clipe da greatsword para sacar")
	check(gp._sheath_length <= 0.30, "sacar termina em até 0,30 s, sem espera longa")
	gp._update_back_katana("katana")
	check(gp.back_katana.visible and not gp.hand_katana.visible, "no primeiro instante do saque a espada ainda está nas costas (a mão ainda está chegando)")
	gp._update_sheath(gp.SHEATH_HANDOFF)
	check(actor.combat_weapon_pose.get("native_sword", false), "clipe de saque controla os braços sem sobreposição procedural")
	check(hand_rotation(gp.hand_katana.transform.basis), "pegada nas costas mantém rotação ortonormal")
	gp._update_back_katana("katana")
	check(gp.hand_katana.visible and not gp.back_katana.visible, "durante o saque a espada está na mão, não nas costas")
	var clip_length: float = actor.animation.get_animation("mixsword/sheathe_greatsword").length
	check(absf(actor.combat_clip_time - clip_length) < 0.001, "saque só sai das costas depois de a mão alcançar o cabo")
	gp._update_sheath((gp._sheath_length - gp.SHEATH_HANDOFF) * 0.5)
	check(actor.combat_clip == "mixsword/sheathe_greatsword" and absf(actor.combat_clip_time - clip_length * 0.5) < 0.001, "sacar percorre a greatsword ao contrário até a guarda")
	check(hand_rotation(gp.hand_katana.transform.basis), "pegada intermediária gira sem deformação")
	await run_clip(gp, 0.15)
	check(gp._sheath_clip == "" and actor.combat_clip == "", "saque termina e devolve a locomoção")
	gp._update_back_katana("katana")
	check(not gp.back_katana.visible and not gp.hand_katana.visible, "katana sacada: sai das costas e a pose de combate assume")
	gp._update_back_katana("fists")
	check(gp._sheath_clip == "mixsword/sheathe_greatsword" and gp._sheath_kind == "holster", "trocar de arma toca o guardar")
	check(gp._sheath_length <= 0.30, "guardar termina em até 0,30 s, sem espera longa")
	gp._update_sheath(gp._sheath_length * 0.5)
	check(absf(actor.combat_clip_time - clip_length * 0.5) < 0.001, "guardar toca para frente, até a espada nas costas")
	check(actor.combat_weapon_pose.get("native_sword", false), "guardar preserva os braços nativos ao trocar para outra arma")
	gp._update_back_katana("fists")
	check(gp.hand_katana.visible and not gp.back_katana.visible, "durante o guardar a espada continua na mão")
	await run_clip(gp, 0.15)
	gp._update_back_katana("fists")
	check(gp.back_katana.visible and not gp.hand_katana.visible, "depois de guardar, a katana volta às costas")
	gp._update_back_katana("katana")
	gp._update_sheath(0.03)
	gp._update_back_katana("fists")
	await run_clip(gp, 0.30)
	gp._update_back_katana("fists")
	check(gp._sheath_clip == "" and gp.back_katana.visible and not gp.hand_katana.visible, "troca rápida repetida termina com uma única espada nas costas")
	gp._update_back_katana("katana")
	gp.state.allowed = false
	gp._update_sheath(0.01)
	gp._update_back_katana("fists")
	gp._update_sheath(0.01)
	gp._update_back_katana("fists")
	check(gp._sheath_clip == "" and not gp.hand_katana.visible and gp.state.owned, "área sem armas cancela troca e preserva inventário")
	gp.state.owned = false
	gp._update_back_katana("fists")
	check(not gp.back_katana.visible and not gp.hand_katana.visible, "sem a katana no inventário, nada aparece")
	stage.queue_free()
	await process_frame
	print("BACK_KATANA_SHEATH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func hand_rotation(basis: Basis) -> bool:
	return basis.is_finite() and absf(basis.determinant() - 1.0) < 0.00001 and basis.transposed().is_equal_approx(basis.inverse())

## Posições medidas no esqueleto do Dante com o clipe tocando de fato.
func geometry() -> void:
	var dante: Node = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(dante)
	var skeleton: Skeleton3D = dante.find_child("Skeleton3D", true, false)
	var player := dante.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.add_animation_library("mixsword", load("res://assets/dante/mixamo/dante_mixamo_sword.res"))
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := "mixsword/sheathe_greatsword"
	player.play(clip)
	player.seek(player.get_animation(clip).length, true); player.advance(0.0)
	await process_frame
	var hand := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).orthonormalized() * GAMEPLAY.HAND_KATANA_SHEATHED
	var back := skeleton.get_bone_global_pose(skeleton.find_bone("Spine02")).orthonormalized() * GAMEPLAY.BACK_KATANA_LOCAL
	check(hand.origin.distance_to(back.origin) < 0.02 and (-hand.basis.z).dot(-back.basis.z) > 0.999, "no fim do guardar a espada da mão coincide com a das costas (sem salto)")
	var spine := skeleton.get_bone_global_pose(skeleton.find_bone("Spine02")).origin
	check(back.origin.z < spine.z - 0.08 and (-back.basis.z).y < -0.8, "nas costas: cabo atrás da coluna (%.2f m) e lâmina descendo" % (spine.z - back.origin.z))
	player.seek(0.0, true); player.advance(0.0)
	await process_frame
	var guard := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).orthonormalized() * GAMEPLAY.HAND_KATANA_GUARD
	check((-guard.basis.z).z > 0.5, "na guarda (fim do sacar) a lâmina aponta para a frente")
	dante.free()
