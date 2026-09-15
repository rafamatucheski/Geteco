class_name ColdSurvivalController
extends Node

## Controlador de Sobrevivência ao Frio & Hipotermia:
## Monitora a temperatura corporal do jogador, detectando exposição ao frio polar,
## aquecimento dentro de veículos e proximidade de fogueiras/fontes de calor.

signal temperature_changed(current_temp: float, max_temp: float)
signal hypothermia_started()
signal hypothermia_ended()
signal thermal_suit_equipped(has_suit: bool)

@export var max_temperature: float = 100.0
@export var current_temperature: float = 100.0
@export var cold_drain_rate: float = 3.5 # Perda de temperatura por segundo exposto ao frio
@export var blizzard_extra_drain: float = 2.0
@export var car_warming_rate: float = 20.0 # Recuperação por segundo dentro de veículo
@export var campfire_warming_rate: float = 35.0 # Recuperação por segundo próximo a fogo
@export var hypothermia_damage_rate: float = 5.0 # Dano por segundo quando a barra zerar
@export var arrival_grace_seconds: float = 15.0
@export var exposure_ramp_seconds: float = 15.0

# Altitude onde o frio se inicia (coordenada Y menor = mais alto na montanha)
@export var cold_zone_y_threshold: float = -1500.0
@export var force_cold_active: bool = false

var player_target: Node2D = null
var is_in_vehicle: bool = false
var is_near_heat_source: bool = false
var outfit_protection := 0.0
var has_thermal_suit: bool = false
var is_hypothermic: bool = false

var _damage_accumulator: float = 0.0
var sheltered := false
var weather_exposure := 0.0
var exposure_seconds := 0.0

func _ready() -> void:
	current_temperature = max_temperature
	add_to_group("cold_controller")

func _process(delta: float) -> void:
	_update_player_state()
	_update_temperature(delta)

func set_player(player: Node2D) -> void:
	player_target = player

func equip_thermal_suit(equipped: bool = true) -> void:
	has_thermal_suit = equipped
	thermal_suit_equipped.emit(has_thermal_suit)

func _update_player_state() -> void:
	if player_target == null or not is_instance_valid(player_target):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_target = players[0] as Node2D
		else:
			return

	# Checa se está dentro de um carro
	is_in_vehicle = false
	if player_target.has_method("is_driving") and player_target.is_driving():
		is_in_vehicle = true
	elif player_target.get("current_vehicle") != null or player_target.get("is_inside_vehicle") == true:
		is_in_vehicle = true
	elif not player_target.visible: # Convenção clássica quando embarcado
		is_in_vehicle = true

	# Checa proximidade com fontes de calor (fogueiras, barris com fogo na madeireira)
	is_near_heat_source = false
	var heat_sources := get_tree().get_nodes_in_group("heat_source")
	for source in heat_sources:
		if source is Node2D and is_instance_valid(source):
			var dist: float = (source as Node2D).global_position.distance_to(player_target.global_position)
			if dist < 220.0: # Raio de calor agradável da fogueira
				is_near_heat_source = true
				break

func is_in_cold_zone() -> bool:
	if sheltered:
		return false
	if force_cold_active:
		return true
	if player_target and is_instance_valid(player_target):
		return player_target.global_position.y <= cold_zone_y_threshold
	return false

func _update_temperature(delta: float) -> void:
	var in_cold: bool = is_in_cold_zone()
	var prev_temp: float = current_temperature
	var exposed := in_cold and not is_near_heat_source and not is_in_vehicle
	var previous_exposure := exposure_seconds
	if exposed:
		exposure_seconds += delta
	else:
		exposure_seconds = maxf(0.0, exposure_seconds - delta * 2.0)
	# Integrating the ramp keeps grace and drain independent of frame rate.
	var drain_seconds := _exposure_integral(exposure_seconds) - _exposure_integral(previous_exposure) if exposed else 0.0

	if in_cold:
		if is_near_heat_source:
			# Fogueira aquece rápido
			current_temperature = minf(max_temperature, current_temperature + campfire_warming_rate * delta)
		elif is_in_vehicle:
			# Aquecedor do carro protege e esquenta
			current_temperature = minf(max_temperature, current_temperature + car_warming_rate * delta)
		elif has_thermal_suit or outfit_protection>0:
			# Roupa térmica reduz exposição em 80%; ainda exige abrigo.
			current_temperature = maxf(0.0, current_temperature - (cold_drain_rate + blizzard_extra_drain * weather_exposure) * (1.0-clampf(maxf(outfit_protection,0.8 if has_thermal_suit else 0.0),0.0,1.0)) * drain_seconds)
		else:
			# Exposto ao relento: temperatura cai
			var drain: float = cold_drain_rate + blizzard_extra_drain * weather_exposure
			current_temperature = maxf(0.0, current_temperature - drain * drain_seconds)
	else:
		# Fora da zona fria: temperatura normaliza naturalmente
		current_temperature = minf(max_temperature, current_temperature + 15.0 * delta)

	if prev_temp != current_temperature:
		temperature_changed.emit(current_temperature, max_temperature)

	# Lógica de Hipotermia
	if current_temperature <= 0.0:
		if not is_hypothermic:
			is_hypothermic = true
			hypothermia_started.emit()
		
		# Aplica dano de congelamento
		_damage_accumulator += hypothermia_damage_rate * delta
		if _damage_accumulator >= 1.0:
			var dmg_int: int = int(_damage_accumulator)
			_damage_accumulator -= float(dmg_int)
			_apply_cold_damage(dmg_int)
	else:
		_damage_accumulator = 0.0
		if is_hypothermic:
			is_hypothermic = false
			hypothermia_ended.emit()

func _apply_cold_damage(amount: int) -> void:
	if player_target and is_instance_valid(player_target):
		if player_target.has_method("take_environment_damage"):
			player_target.take_environment_damage(amount)
		elif "health" in player_target:
			player_target.health = max(0, player_target.health - amount)

func _exposure_integral(seconds: float) -> float:
	var time := maxf(0.0, seconds - arrival_grace_seconds)
	var ramp := maxf(0.001, exposure_ramp_seconds)
	return time * time / (2.0 * ramp) if time < ramp else time - ramp * 0.5

func should_show_status() -> bool:
	# Show the cold zone immediately, including grace time and vehicle heating.
	# Exposure controls temperature loss, not whether the player can see the HUD.
	return current_temperature < max_temperature - 0.5 or is_in_cold_zone()
