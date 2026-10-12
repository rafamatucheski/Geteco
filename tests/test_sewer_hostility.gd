extends SceneTree
## Real room actors, swept collision, social escalation and combat; temporary controller
## only for focused physics tests. Default mode uses Main and Gameplay's real melee.
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const HOSTILITY := preload("res://world/places/sewers/SewerHostility.gd")
var failures: Array[String] = []
var world

class PlayerFixture extends CharacterBody3D:
	var input_locked := false
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3
		capsule.height = 1.75
		shape.shape = capsule
		shape.position.y = .88
		add_child(shape)

class CombatFixture extends Node:
	signal npc_gunfire(origin, direction, source)
	var player: CharacterBody3D
	var health := 100.0
	var weapon := "fists"
	func equipped() -> String: return weapon
	func damage_player(amount: float, _from: Vector3) -> void: health -= amount
	func _sound(_id: String, _point: Vector3) -> void: pass
	func _trace(_from: Vector3, _to: Vector3, _duration: float, _width: float) -> void: pass

class WorldFixture extends Node3D:
	var player: CharacterBody3D
	var gameplay: Node

class SessionFixture extends Node:
	var room: Node3D
	var world: Node3D
	var state := {"place_id": ""}

func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)
func settle(frames := 10) -> void:
	for i in frames: await physics_frame

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute("res://output/sewer-hostility")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/sewer-hostility/"+label+".png")

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	if "--unit" in OS.get_cmdline_user_args():
		await focused()
	else:
		await integrated()
	print("SEWER_HOSTILITY failures=", failures)
	quit(0 if failures.is_empty() else 1)

func focused() -> void:
	world = WorldFixture.new()
	root.add_child(world)
	world.player = PlayerFixture.new()
	world.add_child(world.player)
	world.gameplay = CombatFixture.new()
	world.gameplay.player = world.player
	world.add_child(world.gameplay)
	var session := SessionFixture.new()
	session.world = world
	world.add_child(session)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	for id in SEWERS.ids():
		if not only.is_empty() and id != only: continue
		var definition: Dictionary
		if id == SEWERS.ORIGINAL_ID:
			definition = {"id": id, "size": Vector2(23,13.5), "model": "res://world/places/SewerModel.gd", "variant": 0,
				"spawn": Vector3(-5,0,-.85), "npcs": SEWERS.original_residents()}
		else:
			var site := SEWERS.site(id)
			definition = {"id": id, "size": site.size, "model": SEWERS.PLACES_ROOT+site.model+".gd", "variant": 0}
			SEWERS.decorate(definition)
		var room = preload("res://world/places/NativePlace.gd").new()
		room.definition = definition
		world.add_child(room)
		session.room = room
		session.state.place_id = id
		world.player.position = definition.spawn + Vector3.UP*.04
		var actors: Array[CharacterBody3D] = []
		for spec in definition.npcs:
			check(room.is_floor_clear(spec.local_position), id+": spawn livre de "+str(spec.name))
			actors.append(HOSTILITY.install(session, spec, spec.local_position+Vector3.UP*.04))
		await settle()
		var actor = actors[0]
		var origin: Vector3 = actor.position
		var wall_hit: KinematicCollision3D = actor.move_and_collide(Vector3(0, 0, 40))
		# Rect2.grow is conservative at corners; the real rounded capsule is authoritative.
		var shape: CollisionShape3D = actor.get_child(0)
		var overlap := PhysicsShapeQueryParameters3D.new()
		overlap.shape = shape.shape
		overlap.transform = shape.global_transform
		overlap.collision_mask = 1
		overlap.exclude = [room.get_node("Floor").get_rid()]
		var penetrations: Array = actor.get_world_3d().direct_space_state.intersect_shape(overlap)
		if wall_hit != null: print("SWEPT ", id, " blocker=", wall_hit.get_collider().name, " solid_overlaps=", penetrations.size())
		check(wall_hit != null and actor.position.distance_to(origin) < 39 and penetrations.is_empty(), id+": movimento varrido não atravessa sólidos")
		actor.position = origin
		actor.receive_damage(NAN, world.player)
		actor.receive_damage(-1, world.player)
		check(actor.health == 90 and not actor.warned, id+": dano inválido ignorado")
		actor.receive_damage(9, world.player)
		check(actor.warned and not actor.hostile and actor._warning.visible and actor._warning.text == "PARE!", id+": primeiro soco avisa")
		for other in actors: check(not other.hostile, id+": primeiro soco não inicia conflito coletivo")
		actor.receive_damage(9, world.player)
		check(actor.hostile and actor.health == 72 and actor.visual.armed, id+": segundo soco inicia combate com dano real")
		if id == "harbor_sewer":
			await settle(45)
			check(actors[1].hostile and actors[2].hostile, "aliados próximos defendem morador, inclusive do outro lado do canal")
		# Direct contact exercises attack wind-up and actual physics visibility.
		world.player.position = actor.position+Vector3(0, 0, .85)
		world.gameplay.health = 100
		await settle(100)
		check(world.gameplay.health < 100 and actor.attacks > 0, id+": retaliação tira vida")
		world.player.input_locked = true
		var before: float = world.gameplay.health
		await settle(70)
		check(world.gameplay.health == before, id+": transição bloqueia ataques")
		world.player.input_locked = false
		world.player.position = Vector3(actor.position.x, .04, float(definition.size.y)*.5+2.0)
		before = world.gameplay.health
		await settle(100)
		check(world.gameplay.health == before, id+": parede impede dano e travessia")
		for other in actors:
			if other == actor: continue
			other.engage(world.player)
			world.player.position = other.position+Vector3(0, 0, .85)
			world.gameplay.health = 100
			await settle(100)
			check(world.gameplay.health < 100 and other.attacks > 0, id+": arma de "+str(other.definition.name)+" causa dano")
		actor.receive_damage(1000, world.player)
		check(actor.dead and actor.collision_layer == 0 and not actor.is_physics_processing(), id+": morte encerra combate")
		var armed_victim = HOSTILITY.install(session, definition.npcs[0], origin)
		world.gameplay.weapon = "knife"
		armed_victim.receive_damage(25, world.player)
		check(armed_victim.hostile and not armed_victim.warned, id+": ataque armado provoca defesa imediata")
		armed_victim.free()
		world.gameplay.weapon = "fists"
		for other in actors: other.free()
		room.free()
		session.room = null
		await settle(2)
	world.free()
	await process_frame

func integrated() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "sessão integrada inicia")
	if not failures.is_empty(): world.free(); return
	var session = world.session
	var access: Vector3 = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_sewer").exterior_position
	world.production.region.set_focus(access)
	world.player.teleport(access+Vector3(0,.04,1.2))
	await settle(10)
	check(await session.enter_place("harbor_sewer", false), "entra no boeiro original")
	check(session.room_npcs.size() == 3, "três moradores no boeiro original")
	if session.room_npcs.size() != 3: world.free(); return
	var residents: Array = session.room_npcs.duplicate()
	var actor = residents[0]
	world.player.teleport(actor.global_position+Vector3(0, .02, 1.0))
	world.gameplay.state.equipped_weapon = "fists"
	await settle()
	await capture("residents-idle")
	var data: Dictionary = world.gameplay.weapon_data("fists")
	world.gameplay._melee(world.player.global_position+Vector3.UP, Vector3.FORWARD, data, "fists")
	check(actor.warned and not actor.hostile, "soco pelo Gameplay provoca PARE sem retaliação")
	await capture("first-punch-warning")
	await settle(30)
	var toward: Vector3 = actor.global_position-world.player.global_position
	toward.y = 0
	world.gameplay._melee(world.player.global_position+Vector3.UP, toward.normalized(), data, "fists")
	await settle(50)
	check(actor.hostile and residents[1].hostile and residents[2].hostile, "segundo soco chama aliados, inclusive morador com pistola")
	for i in 6:
		await settle(3)
		await capture("fight-%02d" % i)
	check(not session.services.perform(str(actor.definition.id)), "morador hostil não abre diálogo")
	var saved_health: float = world.gameplay.health
	await settle(180)
	check(world.gameplay.health < saved_health, "combate integrado fere Dante")
	var refs: Array[WeakRef] = []
	for resident in residents: refs.append(weakref(resident))
	check(await session.leave_place(), "saída funciona durante briga")
	await settle(20)
	for reference in refs: check(reference.get_ref() == null, "saída libera moradores sem perseguir na rua")
	check(await session.enter_place("harbor_sewer", false), "reentrada funciona")
	for resident in session.room_npcs: check(not resident.hostile and not resident.warned, "nova visita sem alvo ou golpe residual")
	check(await session.leave_place(), "retorno final à rua")
	session.state.grant_weapon("pistol")
	check(session.state.equip_weapon("pistol"), "arma disponível fora da garagem")
	check(await session.enter_place("maciota", false), "regressão: entrada na garagem")
	check(not session.state.weapons_allowed() and not session.state.can_attack() and session.state.equipped_weapon == "fists", "garagem guarda arma e bloqueia ataques")
	check(not session.state.equip_weapon("pistol") and not world.gameplay.attack_allowed(), "garagem bloqueia saque e combate")
	for resident in [session.room.maciota, session.room.mechanic]:
		check(preload("res://gameplay/DamageProtection.gd").is_protected(resident) and not resident.has_method("receive_damage"), "Maciota e mecânico protegidos sem rotina de dano")
	check(await session.leave_place(), "regressão: saída da garagem")
	check(session.state.owns_weapon("pistol") and session.state.equip_weapon("pistol"), "saída preserva inventário e libera arma")
	world.free()
	await process_frame
