extends SceneTree
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const STATE := preload("res://runtime/GameState.gd")
const ROOF := preload("res://world/places/harbor_buildings/HarborBuildingRooftop.gd")
class TestWorld extends Node3D:
	var gameplay
var world: Node3D
var player: CharacterBody3D
var gameplay
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("AIR_FAIL " + label)

func floor_box(point: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = point
	body.add_child(shape)
	world.add_child(body)

func settle(frames := 8) -> void:
	for i in frames: await physics_frame

func until_ground(limit := 360) -> void:
	for i in limit:
		await physics_frame
		if player.dead or (player.is_on_floor() and player.air_movement.phase == "ground"): return
	check(false, "bounded landing/recovery")

func run() -> void:
	world = TestWorld.new()
	root.add_child(world)
	floor_box(Vector3(0,-.25,0), Vector3(80,.5,80))
	player = ACTOR.new()
	player.is_player = true
	world.add_child(player)
	gameplay = GAMEPLAY.new()
	world.gameplay = gameplay
	gameplay.configure(world,player,null,STATE.new())
	# As legendas dirigidas de dor usam timers de cena. O dono de produção do Gameplay
	# pertence à árvore; a fixture precisa preservar também esse ciclo de vida.
	world.add_child(gameplay)
	gameplay.set_physics_process(false)
	gameplay.set_process(false)
	player.controlled_automatically = true
	await settle()
	await until_ground()
	var initial_landings: int = player.air_movement.landings
	check(player.animation.has_animation("ual/Jump_Start") and player.animation.has_animation("ual/Jump_Land"), "native retargeted clips available")
	check(player.air_movement.request_jump(), "ground jump accepted")
	await settle(4)
	check(player.global_position.y > .1 and not player.is_on_floor(), "jump raises native capsule")
	check(not player.air_movement.request_jump(), "no repeated air jump")
	await until_ground()
	check(gameplay.health == 100.0, "ordinary jump causes no damage")
	check(player.air_movement.landings == initial_landings + 1, "one landing per jump")
	player.input_locked = true
	check(not player.air_movement.request_jump(), "locked movement rejects jumping")
	player.input_locked = false
	# A colisão com um teto precisa parar a cápsula varrida, sem penetração.
	floor_box(Vector3(0,2.15,0), Vector3(4,.2,4))
	check(player.air_movement.request_jump(), "jump below ceiling starts")
	var maximum := 0.0
	for i in 60:
		await physics_frame
		maximum = maxf(maximum, player.global_position.y)
	check(maximum < .5, "ceiling blocks capsule")
	await until_ground()
	# Quedas baixas e altas usam o caminho real de dano do Gameplay e nunca a blindagem.
	player.teleport(Vector3(8,4.1,0))
	gameplay.armor = 60.0
	await until_ground()
	check(gameplay.health > 0.0 and gameplay.health < 100.0, "low fall hurts and survives")
	check(gameplay.armor == 60.0, "fall does not spend armor")
	check(player.air_movement.phase == "ground" and not player.get_meta("player_air_busy",true), "survivor gets up and recovers")
	var health_after: float = gameplay.health
	await settle(20)
	check(gameplay.health == health_after, "landing damage is not repeated")
	# Um telhado real de um andar mantém o colisor da platibanda durante toda a saída.
	var roof = ROOF.new()
	roof.definition = {"id":"air_fixture_roof", "size":Vector2(8,8), "floor_count":1, "roof_height":4.0, "reward":{}, "rewards":[]}
	roof.position = Vector3(16,4,0)
	world.add_child(roof)
	player.teleport(roof.to_global(Vector3(2,.04,3.1)))
	await settle()
	player.air_movement.roof = roof
	player.automatic_direction = Vector3.BACK
	player.speed = 3.5
	var saw_grip := false
	var saw_fall := false
	var gate_solid := true
	var grip_measured := false
	for i in 300:
		await physics_frame
		saw_grip = saw_grip or player.air_movement.phase == "grip"
		saw_fall = saw_fall or player.air_movement.phase == "fall"
		if player.air_movement.phase == "grip" and player.air_movement.age > .12 and not grip_measured:
			grip_measured = true
			var contact: Vector3 = roof.to_global(Vector3(2,1.04,3.88))
			for side in ["Left", "Right"]:
				var target: Vector3 = contact + Vector3.LEFT * (-1.0 if side == "Left" else 1.0) * .20
				var error: float = player._clip_palm(side).distance_to(target)
				print("ROOF_GRIP ",side," distance=",error)
				check(error < .16, side + " palm contacts solid parapet")
		gate_solid = gate_solid and roof._jump_gate.collision_layer == 1
		if player.is_on_floor() and player.global_position.y < 1.0:
			player.automatic_direction = Vector3.ZERO
			break
	check(player.global_position.y < 1.0 and player.global_position.z > 4.3, "walking toward parapet exits physically")
	check(saw_grip and saw_fall, "one-storey exit catches ledge then falls")
	check(grip_measured, "ledge grip is held long enough to present")
	check(gate_solid, "parapet stays solid throughout traversal")
	await until_ground()
	check(not player.dead and player.air_movement.phase == "ground", "low rooftop survivor rises")
	player.teleport(Vector3(-8,14,0))
	await until_ground()
	check(gameplay.health == 0.0 and player.dead, "high fall is fatal")
	check(player.last_death_clip == "mixamo/death_forward", "fatal impact uses prone fall presentation")
	player.respawn_player()
	player.teleport(Vector3(8,.04,0))
	player.input_locked = false
	await settle()
	check(player.air_movement.phase == "ground" and not player.dead, "respawn clears flight ownership")
	gameplay.free()
	world.queue_free()
	await process_frame
	print("PLAYER_AIR_MOVEMENT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
