extends SceneTree
## Morte de civis e policiais com os clipes do Mixamo: o clipe segue o lado do empurrão, o corpo termina
## deitado, todo tier de policial tem as juntas, e quem está vivo ou é o jogador fica de fora.
const DEATH := preload("res://gameplay/MixamoDeath.gd")
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const POLICE := preload("res://gameplay/PoliceModel.gd")

class Body extends CharacterBody3D:
	var dead := true
	var is_player := false

var failures: Array[String] = []
var checks := 0
var stage: Node3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func make_civilian(at: Vector3, dead := true, player := false) -> Array:
	var actor := Body.new()
	actor.dead = dead
	actor.is_player = player
	actor.position = at
	stage.add_child(actor)
	var model := CIVILIAN.new()
	actor.add_child(model)
	return [actor, model]

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	check(DEATH.library() != null and DEATH.library().get_animation_list().size() == 4, "biblioteca npc_death carregada com quatro clipes")
	check(DEATH.clip_for(Vector3(0, 0, 1)) == "death_forward", "empurrão para a frente -> cai para frente")
	check(DEATH.clip_for(Vector3(0, 0, -1)) == "death_back", "empurrão para trás -> cai para trás")
	check(DEATH.clip_for(Vector3(1, 0, 0.2)) == "death_left", "empurrão para +X -> cai para o lado +X")
	check(DEATH.clip_for(Vector3(-1, 0, 0.2)) == "death_right", "empurrão para -X -> cai para o lado -X")
	for i in 5: await process_frame
	# Civil caindo para frente: a cabeça termina à frente e perto do chão.
	var pair := make_civilian(Vector3(0, 0, 0))
	for i in 5: await process_frame
	var actor: Node3D = pair[0]
	var model: Node3D = pair[1]
	check(DEATH.play(actor, model, Vector3(0, 0, 1)), "civil morto recebe o clipe")
	check(actor.get_meta("mixamo_death_clip", "") == "death_forward", "clipe escolhido pelo empurrão: death_forward")
	await create_timer(4.2).timeout
	var head: Node3D = model.find_child("Head", true, false)
	var pelvis: Node3D = model.find_child("Pelvis", true, false)
	check(head.global_position.z > 1.0, "cabeça terminou à frente: %.2f m" % head.global_position.z)
	check(pelvis.global_position.y < 0.35 and head.global_position.y < 0.45, "corpo termina deitado: pelve %.2f m, cabeça %.2f m" % [pelvis.global_position.y, head.global_position.y])
	# Policial de todos os tiers: o corpo instalado tem as juntas do rig.
	for tier in 5:
		var cop_actor := Body.new()
		stage.add_child(cop_actor)
		var cop := POLICE.new()
		cop.tier = tier
		cop.appearance_index = tier
		cop_actor.add_child(cop)
		cop.equip("pistol" if tier == 0 else ("smg" if tier == 1 else "m4a1"))
		cop._install_body()
		await process_frame
		check(DEATH.play(cop_actor, cop, Vector3(1, 0, 0)), "policial do tier %d recebe o clipe" % tier)
		cop_actor.queue_free()
	# Vivo e jogador ficam de fora; quem cai e levanta não perde a pose.
	var alive := make_civilian(Vector3(6, 0, 0), false)
	check(not DEATH.play(alive[0], alive[1], Vector3(0, 0, 1)), "ator vivo não recebe o clipe de morte")
	var player := make_civilian(Vector3(8, 0, 0), true, true)
	check(not DEATH.play(player[0], player[1], Vector3(0, 0, 1)), "jogador não recebe o clipe de NPC")
	# Integração: a queda de personagens manda os mortos para o clipe do Mixamo.
	var hit := make_civilian(Vector3(-6, 0, 0))
	for i in 5: await process_frame
	FALL.apply_fall(hit[0], hit[1], Vector3(1, 0, 0))
	check(hit[0].get_meta("mixamo_death_clip", "") == "death_left", "apply_fall de morto usa o clipe: %s" % hit[0].get_meta("mixamo_death_clip", ""))
	print("MIXAMO_NPC_DEATH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
