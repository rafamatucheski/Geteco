extends SceneTree
## Ragdoll do atropelamento (BodyRagdoll3D via BodyFlight3D): voa, não atravessa o chão, joelho e cotovelo
## dobram só para o lado anatômico, assenta, deixa a pose deitada nas juntas, levanta e libera os corpos.
## Roda com o corpo do Meshy (pedestre genérico) e com o corpo procedural (guarda-roupa da montanha).
const FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")
const RAGDOLL := preload("res://gameplay/street_physics/BodyRagdoll3D.gd")
const ACTOR := preload("res://scripts/Actor.gd")
class Stage extends Node3D:
	var gameplay: Node
class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	var landings := 0
	func _ready() -> void:
		blood = BLOOD.new()
		add_child(blood)
		set_physics_process(false)
	func on_body_landed(actor: CharacterBody3D, lethal: bool, source: Node, speed: float, heading: Vector3) -> void:
		landings += 1
		super.on_body_landed(actor,lethal,source,speed,heading)
var world: Stage
var street: Street
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	print(("ok   " if ok else "FAIL ") + label)
func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = size
	shape.shape = hull
	body.add_child(shape)
	world.add_child(body)
	body.position = point
	return body
func person(point := Vector3.ZERO, procedural := false) -> CharacterBody3D:
	var body := ACTOR.new()
	body.controlled_automatically = true
	if procedural: body.set_meta("region_id","mountain")
	world.add_child(body)
	body.teleport(point)
	return body
func model_of(body: Node) -> Node3D:
	return RAGDOLL.find_model(body.visual)
## Dobra no referencial do osso pai: joelho com o pé atrás (+Z do Y da canela), cotovelo com a mão à frente.
func bends(model: Node3D) -> Vector2:
	var knee := INF
	var elbow := -INF
	for i in 2:
		knee = minf(knee,(model.shins[i] as Node3D).transform.basis.y.normalized().z)
		elbow = maxf(elbow,(model.forearms[i] as Node3D).transform.basis.y.normalized().z)
	return Vector2(knee,elbow)
## A mesma dobra medida nos corpos rígidos (antes da trava visual): confere o sinal da dobradiça na física.
func physical_bends(ragdoll: RefCounted) -> Vector2:
	var result := Vector2(INF,INF)
	if ragdoll == null: return result
	for part in ragdoll.parts:
		if part.hinge == 0.0 or not is_instance_valid(part.body): continue
		var parent: RigidBody3D = ragdoll.parts[part.parent].body
		if not is_instance_valid(parent): continue
		var bone: Vector3 = parent.global_basis.orthonormalized().inverse() * (part.body as Node3D).global_basis.y
		var amount: float = bone.normalized().z * part.hinge
		if part.hinge > 0.0: result.x = minf(result.x,amount)
		else: result.y = minf(result.y,amount)
	return result
func rigid_count() -> int:
	return world.find_children("*","RigidBody3D",true,false).size()
func run() -> void:
	world = Stage.new()
	root.add_child(world)
	box(Vector3(0,-.1,0),Vector3(80,.2,80))
	street = Street.new()
	world.add_child(street)
	for tick in 3: await physics_frame
	for procedural in [false,true]:
		for speed in [10.0,24.0]:
			var label := "%s %.0f m/s" % ["procedural" if procedural else "meshy", speed]
			var body = person(Vector3(0,.04,0),procedural)
			await physics_frame
			var model := model_of(body)
			var source := Node3D.new()
			world.add_child(source)
			var before := street.landings
			var began := Time.get_ticks_usec()
			var flight = FLIGHT.launch(body,Vector3(0,0,-speed),speed>12.5,street,source,true)
			var build_us := Time.get_ticks_usec()-began
			check(flight != null and flight.ragdoll != null,"%s: atropelamento usa ragdoll" % label)
			check(rigid_count() == 11,"%s: 11 corpos rígidos (%d)" % [label,rigid_count()])
			var lowest := INF
			var farthest := 0.0
			var highest := 0.0
			var worst := Vector2(INF,-INF)
			var physical := Vector2(INF,INF)
			var outside := 0
			var ticks := 0
			for tick in 400:
				await physics_frame
				ticks += 1
				if not body.has_meta("street_flying"): break
				var pelvis: Vector3 = model.pelvis.global_position
				lowest = minf(lowest,pelvis.y)
				highest = maxf(highest,pelvis.y)
				farthest = maxf(farthest,Vector2(pelvis.x,pelvis.z).length())
				var bend := bends(model)
				worst = Vector2(minf(worst.x,bend.x),maxf(worst.y,bend.y))
				var raw := physical_bends(flight.ragdoll)
				physical = Vector2(minf(physical.x,raw.x),minf(physical.y,raw.y))
				if raw.x < -.45 or raw.y < -.45: outside += 1
			print("  %s: monta %d us, assenta em %.2f s, alcance %.2f m, pelve %.2f..%.2f m, joelho %.2f, cotovelo %.2f, física joelho %.2f cotovelo %.2f" \
				% [label,build_us,ticks/60.0,farthest,lowest,highest,worst.x,worst.y,physical.x,physical.y])
			check(not body.has_meta("street_flying") and street.landings == before+1,"%s: assenta e aplica dano uma vez" % label)
			check(farthest > (1.5 if speed < 12 else 4.0),"%s: corpo é arremessado (%.2f m)" % [label,farthest])
			check(highest > .9,"%s: corpo sai do chão (pelve %.2f m)" % [label,highest])
			check(lowest > -.02,"%s: pelve não atravessa o chão (%.3f)" % [label,lowest])
			check(worst.x > -.25,"%s: joelho não dobra para a frente (%.2f)" % [label,worst.x])
			check(worst.y < .25,"%s: cotovelo não dobra para trás (%.2f)" % [label,worst.y])
			# O solver cede por alguns quadros no impacto (a trava visual cobre); sinal invertido ficaria fora o voo inteiro.
			check(outside <= maxi(3,ticks/20),"%s: dobradiças físicas no sentido certo (%d de %d quadros fora; pior %.2f, %.2f)" 				% [label,outside,ticks,physical.x,physical.y])
			await physics_frame
			check(rigid_count() == 0 and RAGDOLL.active == 0,"%s: corpos rígidos liberados ao assentar" % label)
			var spine_up: Vector3 = model.spine.global_basis.y.normalized()
			check(absf(spine_up.y) < .7,"%s: fica deitado nas juntas (tronco %.2f)" % [label,spine_up.y])
			var flat_root := Vector2(body.global_position.x,body.global_position.z)
			var flat_pelvis := Vector2(model.pelvis.global_position.x,model.pelvis.global_position.z)
			check(flat_root.distance_to(flat_pelvis) < .3,"%s: origem do ator acompanha o corpo" % label)
			check(body.dead == (speed > 12.5),"%s: contrato de velocidade letal mantido" % label)
			if body.dead:
				var lying: Transform3D = model.spine.global_transform
				for tick in 30: await physics_frame
				check(model.spine.global_transform.is_equal_approx(lying),"%s: corpo morto mantém a pose do ragdoll" % label)
			else:
				body.recover_from_injury()
				# Levantar com mocap (BodyGetUp3D, 28/10): 3–10 s, às vezes com uma tentativa que desaba antes.
				for tick in 900:
					await physics_frame
					if not body.has_meta("street_down"): break
				check(not body.has_meta("street_down") and body.is_physics_processing() and model.is_processing(),"%s: levanta e volta a andar" % label)
				check(model.spine.global_basis.y.normalized().y > .95,"%s: tronco volta à pose de pé" % label)
				check(body.collision_layer == 2 and body.collision_mask == 7,"%s: colisão de pedestre restaurada" % label)
			source.queue_free()
			body.queue_free()
			await process_frame
	# Parede fina: o corpo rígido para nela em vez de atravessar.
	var wall := box(Vector3(0,1,-3),Vector3(5,2,.15))
	var body = person(Vector3(0,.04,0))
	await physics_frame
	var flight = FLIGHT.launch(body,Vector3(0,0,-30),false,street,null,true)
	var deepest := 0.0
	for tick in 400:
		await physics_frame
		for part in world.find_children("*","RigidBody3D",true,false): deepest = minf(deepest,(part as Node3D).global_position.z)
		if not body.has_meta("street_flying"): break
	check(deepest > -3.1,"parede fina segura o corpo (%.2f)" % deepest)
	check(not body.has_meta("street_flying"),"bater na parede ainda assenta")
	wall.queue_free()
	body.queue_free()
	await process_frame
	# Teto de ragdolls simultâneos: o quinto usa o voo varrido.
	var crowd: Array = []
	var flights: Array = []
	for i in RAGDOLL.MAX_ACTIVE+1:
		var walker = person(Vector3(i*3.0-6.0,.04,10))
		crowd.append(walker)
	await physics_frame
	for walker in crowd: flights.append(FLIGHT.launch(walker,Vector3(0,0,-9),false,street,null,true))
	check(flights[RAGDOLL.MAX_ACTIVE].ragdoll == null and flights[0].ragdoll != null,"acima do teto cai no voo antigo")
	# Cancelar o dono no meio do voo devolve o ator e libera os corpos.
	flights[0].free()
	await physics_frame
	check(crowd[0].collision_mask == 7 and crowd[0].is_physics_processing() and not crowd[0].has_meta("street_down"),"cancelar restaura o ator")
	for walker in crowd: walker.queue_free()
	await process_frame
	await physics_frame
	check(rigid_count() == 0 and RAGDOLL.active == 0,"nenhum corpo rígido sobra (%d, ativos %d)" % [rigid_count(),RAGDOLL.active])
	RAGDOLL.enabled = false
	body = person()
	await physics_frame
	flight = FLIGHT.launch(body,Vector3(0,0,-9),false,street,null,true)
	check(flight.ragdoll == null,"GETECO_RAGDOLL=0 volta ao voo antigo")
	RAGDOLL.enabled = true
	world.free()
	await process_frame
	print("BODY_RAGDOLL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
