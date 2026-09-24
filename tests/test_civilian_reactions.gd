extends SceneTree

class DummyPlayer extends CharacterBody2D:
	var health := 100
	func _ready() -> void:
		add_to_group("player")
		collision_layer = 4
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 12.0
		shape.shape = circle
		add_child(shape)
	func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
		health -= amount

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func citizen(scene: Node2D, at: Vector2, profile: int) -> AnimatedPedestrian3D:
	var actor := AnimatedPedestrian3D.new()
	actor.district_theme = AnimatedPedestrian3D.DistrictTheme.WINTER_SNOW
	actor.civilian_reaction_profile = profile
	scene.add_child(actor)
	actor.global_position = at
	return actor

func run() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	var player := DummyPlayer.new()
	scene.add_child(player)
	player.global_position = Vector2(180, 0)

	var armed := citizen(scene, Vector2.ZERO, AnimatedPedestrian3D.CivilianReaction.ARMED)
	var shot = load("res://guns/Bullet.tscn").instantiate()
	shot.owner_body = player
	shot.direction = Vector2.RIGHT
	scene.add_child(shot)
	shot.global_position = player.global_position
	await frames(2)
	check(armed.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.ARMED and armed.get_node_or_null("NPCCombatRig") != null, "Armed witness draws a real pistol")
	await frames(160)
	check(player.health < 100, "Armed witness fires and damages the aggressor")
	armed.civilian_reaction_time = 0.01
	await frames(2)
	var armed_rig := armed.get_node("NPCCombatRig")
	check(armed.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.FLEE and not armed_rig.is_physics_processing() and not armed_rig.current_gun_mesh.visible, "Defender holsters pistol and stops its combat rig after disengaging")
	armed.queue_free()
	await frames(2)

	player.health = 100
	player.global_position = Vector2(35, 100)
	var fighter := citizen(scene, Vector2(0, 100), AnimatedPedestrian3D.CivilianReaction.FIGHT)
	fighter.react_to_gunfire(player.global_position, player.global_position + Vector2.RIGHT * 500.0, player)
	check(fighter.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.FIGHT and fighter.get_node_or_null("NPCCombatRig") != null, "Unarmed witness raises fists")
	await frames(105)
	check(player.health < 100, "Unarmed witness punches the aggressor")
	fighter.queue_free()
	await frames(2)

	wanted.reset_crime()
	player.global_position = Vector2(210, 200)
	var caller := citizen(scene, Vector2(0, 200), AnimatedPedestrian3D.CivilianReaction.CALL_POLICE)
	caller.react_to_gunfire(player.global_position, player.global_position + Vector2.RIGHT * 500.0, player)
	check(wanted.current_stars == 0 and not caller.civilian_called_police, "Witness must complete the call before dispatch")
	await frames(420)
	check(caller.civilian_called_police and wanted.current_stars >= 1, "Completed call reports the crime to WantedManager")
	var points: int = wanted.crime_points
	caller.react_to_gunfire(player.global_position, player.global_position + Vector2.RIGHT * 500.0, player)
	await frames(3)
	check(wanted.crime_points == points, "Repeated gunfire does not repeat one witness call")
	caller.queue_free()
	await frames(2)

	var other_shooter := Node2D.new()
	scene.add_child(other_shooter)
	var bystander := citizen(scene, Vector2(0, 300), AnimatedPedestrian3D.CivilianReaction.ARMED)
	bystander.react_to_gunfire(Vector2(80, 300), Vector2(500, 300), other_shooter)
	check(bystander.is_scared and bystander.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.FLEE and bystander.combat_target == null, "Witness of another NPC's shot flees without blaming player")
	var harbor_walker = load("res://world/harbor/HarborLife.gd").HarborWalker.new()
	harbor_walker.configure_authored_route(PackedVector2Array([Vector2(0, 400), Vector2(0, 800)]), "harbor_witness")
	harbor_walker.civilian_reaction_profile = AnimatedPedestrian3D.CivilianReaction.CALL_POLICE
	scene.add_child(harbor_walker)
	player.global_position = Vector2(210, 400)
	harbor_walker.react_to_gunfire(player.global_position, player.global_position + Vector2.RIGHT * 500.0, player)
	check(harbor_walker.is_in_group("authored_sidewalk_pedestrian") and harbor_walker.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.CALL_POLICE, "Actual HarborWalker subclass chooses a witness action")

	print("CIVILIAN REACTIONS failures=", failures)
	scene.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
