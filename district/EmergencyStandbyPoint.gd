class_name EmergencyStandbyPoint
extends Node2D

## Ponto de Prontidão da Polícia Militar com viatura real autêntica.
## A viatura é um TrafficVehicle completo no grupo 'vehicle', interativo e dirigível.
## Se o jogador tentar roubá-la, o alarme anti-furto dispara e a polícia é chamada imediatamente!

@export var standby_id := "alley_unit_01"
@export var service_key := "police"
@export var available := true
@export var restore_after_seconds := 18.0

var parked_car: CharacterBody2D = null

func _ready() -> void:
	add_to_group("emergency_standby_point")
	# Remove o colisor falso herdado da cena anterior para evitar sobreposição
	var legacy_body := get_node_or_null("Body")
	if legacy_body:
		legacy_body.queue_free()
	call_deferred("_spawn_standby_car")

func _spawn_standby_car() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(parked_car):
		parked_car.queue_free()
		parked_car = null
		
	var car_scene := load("res://city_demo/scenes/TrafficVehicle.tscn") as PackedScene
	if not car_scene:
		return
		
	var car: CharacterBody2D = car_scene.instantiate()
	car.name = "PM_Cruiser_" + standby_id
	
	var target_parent = get_parent() if get_parent() != null else self
	target_parent.add_child(car)
	car.global_position = global_position
	car.global_rotation = global_rotation
	
	if car.has_method("apply_archetype"):
		car.set("_detached_from_lane", true)
		car.set("is_police_vehicle", true)
		car.set("is_standby_unit", true)
		car.set("standby_source", self)
		car.apply_archetype("police_cruiser")
		
	parked_car = car
	available = true

func claim() -> bool:
	if not available:
		return false
	if is_instance_valid(parked_car):
		# Se já foi roubada pelo jogador, o despacho da central não pode tomá-la
		if parked_car.get("is_driven_by_player") == true:
			return false
		parked_car.hide()
		parked_car.set_physics_process(false)
		for col in parked_car.find_children("", "CollisionShape2D", true, false):
			col.set_deferred("disabled", true)
	available = false
	return true

func restore_after_return() -> void:
	await get_tree().create_timer(restore_after_seconds).timeout
	if is_instance_valid(parked_car) and parked_car.get("is_driven_by_player") != true:
		parked_car.show()
		parked_car.set_physics_process(true)
		for col in parked_car.find_children("", "CollisionShape2D", true, false):
			col.set_deferred("disabled", false)
		available = true
	else:
		_spawn_standby_car()

func notify_stolen() -> void:
	available = false
	# Respawn de nova viatura na base após o jogador fugir com a viatura roubada
	await get_tree().create_timer(restore_after_seconds * 2.5).timeout
	if not available:
		_spawn_standby_car()
