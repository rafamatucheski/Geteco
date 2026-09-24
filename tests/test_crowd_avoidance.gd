extends SceneTree
## Desvio local de pedestres e percepção de tiro de NPC.
##   godot --path . --script res://tests/test_crowd_avoidance.gd
## Janela real (sem --headless): move_and_slide e colisões precisam rodar de verdade.
## Mede: dois civis em sentidos opostos na mesma linha se cruzam; civil encurralado contra um muro não fica parado
## no ponto de contato; um tiro de NPC (sinal npc_gunfire) faz o civil no raio entrar em fuga; rajada não varre a população
## a cada bala. NÃO mede: multidões densas, calçada real da cidade, custo por quadro.
const ACTOR := preload("res://scripts/Actor.gd")
const DIRECTOR := preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd")

var failures := 0
var root3d: Node3D

func check(ok: bool, label: String, detail := "") -> void:
	print("CASE %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await physics_frame

func _initialize() -> void:
	_run.call_deferred()

func _world_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar people: Array = []\n"
	script.reload()
	return script

func _gameplay_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node\nsignal npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D)\nvar player = null\nfunc weapon_data(_id): return {}\n"
	script.reload()
	return script

func _floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	parent.add_child(body)

func _wall(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)

func _walker(parent: Node3D, at: Vector3, route: PackedVector3Array) -> CharacterBody3D:
	var actor = ACTOR.new()
	actor.identity = 3
	actor.position = at
	actor.speed = 1.5
	actor.route = route
	actor.waypoint = 1
	parent.add_child(actor)
	return actor

func _run() -> void:
	root3d = _world_script().new()
	root.add_child(root3d)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 12, 8)
	root3d.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	_floor(root3d)
	await frames(2)

	# Cabeça com cabeça: A anda para +X, B para -X, exatamente na mesma linha.
	var a := _walker(root3d, Vector3(-6, 0.1, 0), PackedVector3Array([Vector3(-20, 0, 0), Vector3(20, 0, 0)]))
	var b := _walker(root3d, Vector3(6, 0.1, 0), PackedVector3Array([Vector3(20, 0, 0), Vector3(-20, 0, 0)]))
	await frames(8 * 60)
	# Começaram em -6 e +6; trocar de lado prova que passaram um pelo outro.
	check(a.global_position.x > 3.0 and b.global_position.x < -3.0, "frente a frente: os dois se cruzam",
		"a.x=%.1f b.x=%.1f" % [a.global_position.x, b.global_position.x])
	a.queue_free()
	b.queue_free()
	await frames(2)

	# Faixas coincidentes: a rota de B está deslocada de modo que a faixa dele cai exatamente na de A.
	# Aqui só o passo lateral por contato resolve.
	var d := _walker(root3d, Vector3(-6, 0.1, 0.4), PackedVector3Array([Vector3(-20, 0, 0), Vector3(20, 0, 0)]))
	var e := _walker(root3d, Vector3(6, 0.1, 0.4), PackedVector3Array([Vector3(20, 0, 0.8), Vector3(-20, 0, 0.8)]))
	await frames(10 * 60)
	check(d.global_position.x > 3.0 and e.global_position.x < -3.0, "mesma faixa: passo lateral destrava",
		"d.x=%.1f e.x=%.1f" % [d.global_position.x, e.global_position.x])
	d.queue_free()
	e.queue_free()
	await frames(2)

	# Muro atravessado na rota: não pode ficar empurrando parado; desiste do ponto e volta.
	_wall(root3d, Vector3(3, 1, 0), Vector3(0.5, 2, 12))
	var c := _walker(root3d, Vector3(0, 0.1, 0), PackedVector3Array([Vector3(-8, 0, 0), Vector3(8, 0, 0)]))
	await frames(7 * 60)
	# Vale contornar o muro ou desistir e voltar; não vale ficar parado no ponto em que encostou (x≈2,45, z≈0).
	var pinned := Vector2(c.global_position.x - 2.45, c.global_position.z).length()
	check(pinned > 2.0, "muro: não fica empurrando parado", "pos=%s afastamento=%.1f m" % [c.global_position, pinned])
	c.queue_free()
	await frames(2)

	# Tiro de policial: civil a 15 m ouve e foge; fora de 40 m não ouve.
	var gameplay: Node = _gameplay_script().new()
	root3d.add_child(gameplay)
	var director: Node = DIRECTOR.new()
	root3d.add_child(director)
	director.configure(root3d, gameplay)
	var near := _walker(root3d, Vector3(-20, 0.1, 15), PackedVector3Array([Vector3(-25, 0, 15), Vector3(-15, 0, 15)]))
	var far := _walker(root3d, Vector3(40, 0.1, 30), PackedVector3Array([Vector3(35, 0, 30), Vector3(45, 0, 30)]))
	root3d.people = [near, far]
	var officer := Node3D.new()
	root3d.add_child(officer)
	officer.position = Vector3(-20, 0, 0)
	await frames(2)
	gameplay.npc_gunfire.emit(Vector3(-20, 1.2, 0), Vector3.RIGHT, officer)
	await frames(2)
	check(director.reactors.has(near.get_instance_id()) and near.controlled_automatically, "tiro de policial: civil no raio reage")
	check(not director.reactors.has(far.get_instance_id()), "tiro de policial: civil fora do raio ignora")
	var bubble_found := false
	for child in near.get_children():
		if child is Label3D: bubble_found = true
	check(not bubble_found, "pânico por tiro sem balão de texto")
	var start_distance := Vector2(near.global_position.x + 20, near.global_position.z).length()
	# Rajada: 10 disparos em 0,5 s não viram 10 varreduras.
	var alerts_before: int = director.stats.alerts
	for i in 10:
		gameplay.npc_gunfire.emit(Vector3(-20, 1.2, 0), Vector3.RIGHT, officer)
		await frames(3)
	check(director.stats.alerts - alerts_before <= 2, "rajada de NPC limitada por atirador", "alertas=%d" % (director.stats.alerts - alerts_before))
	await frames(120)
	var end_distance := Vector2(near.global_position.x + 20, near.global_position.z).length()
	check(end_distance > start_distance + 3.0, "tiro de policial: civil se afasta", "%.1f -> %.1f m" % [start_distance, end_distance])

	print("CROWD_AVOIDANCE %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
