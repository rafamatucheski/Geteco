extends SceneTree
## Katana nas costas: fica presa à coluna quando guardada, o clipe de sacar (withdraw) toca ao
## equipar e o de guardar (sheathe) ao trocar de arma. Usa o Dante real e os clipes do Mixamo.
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")

class State extends RefCounted:
	var owned := true
	func owns_weapon(id: String) -> bool: return owned and id == "katana"
	func weapons_allowed() -> bool: return true
	func can_attack() -> bool: return true

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run_clip(gp, actor, seconds: float) -> void:
	var steps := int(ceil(seconds * 60.0))
	for i in steps: gp._update_sheath(1.0 / 60.0)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true
	stage.add_child(actor)
	await frames(3)
	var gp := GAMEPLAY.new()
	stage.add_child(gp)
	gp.player = actor
	gp.state = State.new()
	gp.enabled = true
	gp.health = 100.0
	gp._build_socket()
	check(gp.back_katana != null, "katana das costas criada no osso da coluna")
	check(actor.animation.has_animation("mixsword/withdraw_katana") and actor.animation.has_animation("mixsword/sheathe_katana"), "clipes de sacar e guardar carregados")
	gp._update_back_katana("fists")
	check(gp.back_katana.visible, "sem katana na mão, ela fica nas costas")
	gp._update_back_katana("katana")
	check(gp._sheath_clip == "mixsword/withdraw_katana", "equipar a katana toca o clipe de sacar")
	check(gp.back_katana.visible and gp._sheath_drawing(), "durante o saque a katana ainda está nas costas e a mão espera")
	gp._update_sheath(0.5)
	check(actor.combat_clip == "mixsword/withdraw_katana" and absf(actor.combat_clip_time - 0.5) < 0.02, "clipe de saque vai para o Actor no tempo certo")
	await run_clip(gp, actor, 1.6)
	check(gp._sheath_clip == "" and not gp._sheath_drawing(), "saque termina sozinho")
	check(actor.combat_clip == "", "clipe liberado para a locomoção ao terminar o saque")
	gp._update_back_katana("katana")
	check(not gp.back_katana.visible, "katana na mão: sai das costas")
	gp._update_back_katana("fists")
	check(gp._sheath_clip == "mixsword/sheathe_katana", "trocar de arma toca o clipe de guardar")
	check(not gp.back_katana.visible, "durante guardar a katana ainda não voltou às costas")
	await run_clip(gp, actor, 1.8)
	gp._update_back_katana("fists")
	check(gp.back_katana.visible, "depois de guardar, a katana volta às costas")
	gp.state.owned = false
	gp._update_back_katana("fists")
	check(not gp.back_katana.visible, "sem a katana no inventário, nada aparece nas costas")
	print("BACK_KATANA_SHEATH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
