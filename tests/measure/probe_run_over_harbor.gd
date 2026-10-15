extends SceneTree
## Atropelar no porto (15/10: "polícia que não dava para atropelar"). Joga o carro do jogador, com comando
## externo, contra cada guarda do porto, policial e um civil de controle, e diz quem voou e quem não.
## Uso: "$GODOT" --headless --path . --script res://tests/measure/probe_run_over_harbor.gd -- --no-save --skip-arrival --play-at=harbor,280,170
var world: Node3D

func _initialize() -> void: run.call_deferred()

func _candidates() -> Array:
	var found: Array = []
	for group in ["port_staff", "v2_police_officers", "dispatch_officers", "police_officers"]:
		for node in root.get_tree().get_nodes_in_group(group):
			if node is CharacterBody3D and not node in found and node.get("dead") != true and node.is_inside_tree(): found.append(node)
	for person in world.people:
		if is_instance_valid(person) and person.get("dead") != true:
			found.append(person)
			break
	return found

func _layers(node: CharacterBody3D) -> String:
	return "layer=%d mask=%d physics=%s visible=%s" % [node.collision_layer, node.collision_mask, node.is_physics_processing(), node.is_visible_in_tree()]

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	world.gameplay.health = 1000000
	# Com estrela a polícia vem a pé; sem ela só existem guardas e patrulha.
	if "--estrelas" in OS.get_cmdline_user_args(): world.gameplay.register_crime(60, world.player.global_position, "test")
	var car: CharacterBody3D = world.driving.car
	# Carro sem motorista fica em repouso e não roda física: o Dante entra, como no jogo.
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .2)
	for frame in 3: await physics_frame
	world.driving.interact()
	var seated_deadline := Time.get_ticks_msec() + 15000
	while not world.player.seated and Time.get_ticks_msec() < seated_deadline: await process_frame
	print("ATROPELO motorista sentado=", world.player.seated)
	for second in 40: await create_timer(1.0).timeout
	for target in _candidates():
		if not is_instance_valid(target): continue
		var label := "%s <%s>" % [target.name, target.get_script().resource_path.get_file() if target.get_script() else target.get_class()]
		var before := _layers(target)
		var forward: Vector3 = -target.global_basis.z
		forward.y = 0
		forward = forward.normalized() if forward.length() > .1 else Vector3.FORWARD
		var start: Vector3 = target.global_position - forward * 10.0
		car.global_position = start + Vector3.UP * .3
		car.rotation = Vector3(0, atan2(-forward.x, -forward.z), 0)
		car.velocity = Vector3.ZERO
		car.horizontal_velocity = Vector3.ZERO
		car.speed = 12.0
		car.controlled = true
		car.external_input = true
		car.throttle_input = 1.0
		var hit := false
		var closest := 999.0
		var stopped_at := -1.0
		for frame in 90:
			await physics_frame
			if not is_instance_valid(target): break
			closest = minf(closest, Vector2(car.global_position.x - target.global_position.x, car.global_position.z - target.global_position.z).length())
			if target.has_meta("street_flying") or target.has_meta("street_down") or target.get("dead") == true:
				hit = true
				break
			if frame > 20 and absf(car.speed) < .5 and stopped_at < 0: stopped_at = closest
		car.throttle_input = 0.0
		car.speed = 0.0
		print("ATROPELO %s voou=%s mais_perto=%.2f parou_em=%.2f antes[%s] depois[%s]" % [label, hit, closest, stopped_at, before, _layers(target) if is_instance_valid(target) else "-"])
		for frame in 30: await physics_frame
	quit(0)
