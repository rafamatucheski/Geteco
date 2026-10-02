extends Node
## Presentation coordinator only. Driving, damage, fire and equipment remain authoritative elsewhere.

const TIRE := preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd")
const IMPACT := preload("res://gameplay/vehicle_effects/VehicleImpactEffects.gd")
const POWERTRAIN := preload("res://gameplay/vehicle_effects/VehiclePowertrainEffects.gd")
const EFFECT_DISTANCE := 85.0
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var vehicle: CharacterBody3D
var tire_effects: Node
var impact_effects: Node
var powertrain_effects: Node
var presentation_enabled := true
var _active := true
var _range_clock := 0.0

func configure(car: CharacterBody3D) -> void:
	vehicle = car

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	tire_effects = TIRE.new()
	tire_effects.name = "TireEffects"
	tire_effects.configure(vehicle)
	add_child(tire_effects)
	impact_effects = IMPACT.new()
	impact_effects.name = "ImpactEffects"
	impact_effects.configure(vehicle)
	add_child(impact_effects)
	powertrain_effects = POWERTRAIN.new()
	powertrain_effects.name = "PowertrainEffects"
	powertrain_effects.configure(vehicle)
	add_child(powertrain_effects)

func physics_tick(delta: float, incoming_velocity: Vector3) -> void:
	if not presentation_enabled or not vehicle.visible or not vehicle.is_visible_in_tree():
		_active = false
		_range_clock = 0
	else:
		_range_clock -= delta
	if presentation_enabled and _range_clock <= 0:
		_range_clock = .25
		_active = _presentation_active()
	var stage := STALL_WORK.begin()
	tire_effects.physics_tick(delta,_active)
	STALL_WORK.finish_slow("vehicle.effects.tires", stage, 5000, vehicle)
	stage = STALL_WORK.begin()
	powertrain_effects.physics_tick(_active)
	STALL_WORK.finish_slow("vehicle.effects.powertrain", stage, 5000, vehicle)
	stage = STALL_WORK.begin()
	impact_effects.physics_tick(_active,incoming_velocity)
	STALL_WORK.finish_slow("vehicle.effects.impact", stage, 5000, vehicle)

func _presentation_active() -> bool:
	if not presentation_enabled or not vehicle.visible or not vehicle.is_visible_in_tree(): return false
	if vehicle.controlled: return true
	var camera := vehicle.get_viewport().get_camera_3d()
	return camera == null or camera.global_position.distance_to(vehicle.global_position)<=EFFECT_DISTANCE

func clear_all() -> void:
	tire_effects.clear_all()
	powertrain_effects.clear_all()
	impact_effects.stop()
