extends SceneTree
## Reações de testemunha, defesa desarmada e defesa armada na sessão real.
## Godot --path . --script res://tests/test_civilian_varied_reactions.gd -- --no-save --skip-arrival --population=8
const ACTOR := preload("res://scripts/Actor.gd")

var world
var player
var director
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(label: String, result: bool) -> void:
	print("CASE ", "PASS " if result else "FAIL ", label)
	if not result: failures += 1

func frames(count: int) -> void:
	for index in count: await physics_frame

func spawn_visible(identity: int, distance: float):
	for offset in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, -1).normalized()]:
		var actor := ACTOR.new()
		actor.identity = identity
		world.add_child(actor)
		var probe: Vector3 = player.global_position + offset * distance
		var ray := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 3.0, probe + Vector3.DOWN * 3.0, 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		actor.global_position = hit.position + Vector3.UP * 0.08 if not hit.is_empty() else probe
		if director._line_of_sight(actor, player):
			world.people.append(actor)
			return actor
		actor.free()
	return null

func remove(actor) -> void:
	if not is_instance_valid(actor): return
	director.reset_population()
	world.people.erase(actor)
	actor.queue_free()

func capture(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--out-dir="): continue
		var folder := arg.trim_prefix("--out-dir=")
		DirAccess.make_dir_recursive_absolute(folder)
		var image: Image = root.get_viewport().get_texture().get_image()
		if image != null: image.save_png(folder.path_join(name + ".png"))
		return

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		print("recusado: exige --no-save")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	await frames(30)
	player = world.player
	director = world.production.civilian_reactions
	for person in world.people:
		person.set_physics_process(false)
		person.global_position += Vector3.DOWN * 500.0
	world.people.clear()
	world.gameplay.clear_wanted()
	world.gameplay.health = 100.0
	world.gameplay.armor = 0.0

	var caller = spawn_visible(11, 5.0)
	check("testemunha encontrada com visão livre", is_instance_valid(caller))
	if is_instance_valid(caller):
		world.gameplay.register_crime(12, player.global_position)
		world.gameplay.dispatch_timer = 10.0
		check("testemunha saca o celular", director.report_assault(caller, player) and director.reactors[caller.get_instance_id()].phase == "call" and director.presenter.props.has(caller.get_instance_id()))
		await frames(165)
		var state: Dictionary = director.reactors.get(caller.get_instance_id(), {})
		check("ligação informa suspeito e adianta viatura", not state.is_empty() and state.reported and world.gameplay.contact_age < 1.0 and world.dispatch.events_named("witness_call").size() == 1 and world.dispatch._police_clock < 1.5)
		remove(caller)

	var fighter = spawn_visible(15, 1.3)
	check("lutador encontrado com visão livre", is_instance_valid(fighter))
	if is_instance_valid(fighter):
		world.gameplay.health = 100.0
		check("civil escolhe lutar", director.report_assault(fighter, player) and director.reactors[fighter.get_instance_id()].phase == "melee")
		await frames(100)
		check("soco real reduz a vida do jogador", world.gameplay.health < 100.0)
		remove(fighter)

	var gunner = spawn_visible(18, 2.3)
	check("civil armado encontrado com visão livre", is_instance_valid(gunner))
	if is_instance_valid(gunner):
		world.gameplay.health = 100.0
		check("civil escolhe sacar arma", director.report_assault(gunner, player) and director.reactors[gunner.get_instance_id()].phase == "armed")
		await frames(85)
		capture("civilian-armed")
		await frames(65)
		check("pistola aparece e bala atinge o jogador", director.presenter.props.has(gunner.get_instance_id()) and world.gameplay.health < 100.0)
		gunner.receive_damage(500.0, player)
		await frames(3)
		check("civil morto solta arma e controle", gunner.dead and not director.reactors.has(gunner.get_instance_id()) and not director.presenter.props.has(gunner.get_instance_id()))
		remove(gunner)

	world.gameplay.clear_wanted()
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)
