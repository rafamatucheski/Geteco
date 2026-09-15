extends SceneTree

class SuspectCar extends CharacterBody2D:
	var health := 100
	var is_driven_by_player := true
	func take_damage(amount: int, _player_attacker := false) -> void: health -= amount

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	await physics_frame
	await physics_frame
	var unit: Node2D = root.get_node("EmergencyPool").get_vehicle("police")
	unit.set_physics_process(false)
	unit.position = Vector2.ZERO
	unit.rotation = 0
	var target := SuspectCar.new()
	target.position = Vector2(170, 45)
	target.collision_layer = 2
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60, 32)
	collider.shape = shape
	target.add_child(collider)
	scene.add_child(target)
	unit.target = target
	wanted.current_stars = 1
	unit._vehicle_combat.tick(unit, 2)
	await create_timer(.25).timeout
	assert(target.health == 100, "One-star passenger does not shoot")
	wanted.current_stars = 2
	unit._vehicle_combat.tick(unit, 2)
	await create_timer(.3).timeout
	assert(target.health == 95, "Passenger shoots real projectile at fleeing car")
	var wall := StaticBody2D.new()
	wall.position = Vector2(80, 0)
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 180)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	scene.add_child(wall)
	await physics_frame
	unit._vehicle_combat.tick(unit, 4)
	await create_timer(.3).timeout
	assert(target.health == 95, "Wall blocks passenger fire")
	wall.free()
	unit._police_available_seats = 1
	unit._vehicle_combat.tick(unit, 4)
	await create_timer(.3).timeout
	assert(target.health == 95, "Killed passenger is not recreated for vehicle combat")
	wanted.dismiss_all_police()
	print("POLICE_VEHICLE_COMBAT PASS: low-star restraint, real damage, wall, absent passenger")
	quit()
