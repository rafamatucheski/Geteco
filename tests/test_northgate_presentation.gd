extends SceneTree

const Services := preload("res://runtime/Services.gd")
const Economy := preload("res://systems/economy/Economy.gd")
const Vehicle := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

class Player extends Node3D:
	var input_locked := false

class Gameplay extends Node:
	var health := 100.0
	var stars := 3
	func clear_wanted() -> void: stars = 0

class Driving extends Node:
	var occupied := true
	var car: CharacterBody3D
	func is_body_transition_active() -> bool: return false

class World extends Node3D:
	var player: Node3D
	var gameplay: Node
	var driving: Node

class Session extends Node:
	var world: Node3D
	var state: Dictionary
	var ready_for_play := true
	var room: Node3D
	var saves := 0
	var messages: Array[String] = []
	func save_game() -> bool: saves += 1; return true
	func show_message(message: String) -> void: messages.append(message)
	func is_transition_blocked() -> bool: return false

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func frames(count: int) -> void:
	for index in count: await process_frame

func run() -> void:
	var world := World.new()
	root.add_child(world)
	var player := Player.new()
	var gameplay := Gameplay.new()
	var driving := Driving.new()
	var car := Vehicle.new()
	car.archetype = "sport_coupe"
	car.vehicle_id = "northgate_test"
	car.controlled = true
	world.add_child(player)
	world.add_child(gameplay)
	world.add_child(driving)
	world.player = player
	world.gameplay = gameplay
	world.driving = driving
	world.add_child(car)
	driving.car = car
	car.position = Services.AUTO_ORIGIN+Vector3(0,.04,-131.0/16.0)
	player.position = car.position
	var economy := Economy.new()
	economy.grant_reward("northgate_fixture",500)
	var session := Session.new()
	session.world = world
	session.state = {"place_id":"","region_id":"harbor","economy":economy}
	world.add_child(session)
	var services := Services.new()
	world.add_child(services)
	services.configure(session)
	services.set_physics_process(false)
	await frames(2)
	var presentation = services._presentation
	check(is_instance_valid(presentation) and is_instance_valid(presentation.shutter),"Northgate owns one real shutter presentation")
	services._physics_process(.1)
	check(services._auto_phase=="closing" and car.input_locked and player.input_locked,"service closes and locks the existing car/player")
	check(car.collision_layer==0 and not car.is_physics_processing(),"service suspends vehicle collision and motion")
	services._physics_process(.35)
	check(services._auto_phase=="repair" and presentation.spray.emitting and presentation.service_audio.playing,"closed bay starts V1 spray and service audio")
	var before := economy.balance
	services._physics_process(Services.AUTO_SECONDS-.35)
	check(economy.balance==before-Services.AUTO_PRICE and services.serviced_count==1,"Northgate charges exactly once at the preserved duration")
	check(car.health==car.max_health and gameplay.stars==0 and not presentation.spray.emitting,"result repairs and clears wanted before reopening")
	services._physics_process(.35)
	check(services._auto_phase=="idle" and not car.input_locked and not player.input_locked,"opening releases car and controls")
	check(car.collision_layer==4 and car.is_physics_processing(),"opening restores vehicle physics")
	services._physics_process(6.0)
	check(economy.balance==before-Services.AUTO_PRICE and services.serviced_count==1,"remaining in the bay cannot charge twice")

	car.position += Vector3(20,0,0)
	services._physics_process(.1)
	car.position = Services.AUTO_ORIGIN+Vector3(0,.04,-131.0/16.0)
	car.health = 40
	services._physics_process(.1)
	services._physics_process(.40)
	driving.occupied = false
	services._physics_process(.1)
	check(services._auto_phase=="idle" and economy.balance==before-Services.AUTO_PRICE and car.health==40,"interruption before result neither charges nor repairs")
	check(not car.input_locked and not player.input_locked and car.collision_layer==4 and presentation._door_open,"interruption opens shutter and releases every lock")

	driving.occupied = true
	car.position += Vector3(20,0,0)
	services._physics_process(.1)
	car.position = Services.AUTO_ORIGIN+Vector3(0,.04,-131.0/16.0)
	services._physics_process(.1)
	check(services._auto_phase=="closing","second service starts before removal")
	car.queue_free()
	await process_frame
	services._physics_process(.1)
	check(services._auto_phase=="idle" and not player.input_locked and presentation._door_open,"removed car cancels without trapping controls or shutter")

	for failure in failures: push_error(failure)
	print("NORTHGATE_PRESENTATION ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
