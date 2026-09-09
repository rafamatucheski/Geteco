class_name AuthoredDocksParking
extends Node2D

const MODERN_TRAFFIC := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const PARKING_BOUNDS := Rect2(132, 1084, 272, 78)
const ALLEY_BOUNDS := Rect2(118, 1028, 566, 44)
const CAR_SIZE_AFTER_ROTATION := Vector2(34, 76)

## Centres of two deliberately selected bays. They sit between the authored
## vertical parking lines and leave the service alley completely clear.
const PARKED_CAR_SPECS := [
	{"name": "DocksParkedCar_A", "position": Vector2(165, 1123), "color": Color("#294f6b"), "glass": Color("#9cc7d5")},
	{"name": "DocksParkedCar_B", "position": Vector2(249, 1123), "color": Color("#6b3a32"), "glass": Color("#b8c6c5")}
]

func _ready() -> void:
	name = "DocksAuthoredParking"
	_create_exactly_two_cars()
	_validate_authored_layout()

func _create_exactly_two_cars() -> void:
	assert(PARKED_CAR_SPECS.size() == 2, "Docks parking must contain exactly two authored cars")
	for index in PARKED_CAR_SPECS.size():
		var spec: Dictionary = PARKED_CAR_SPECS[index]
		var archetype_id := "station_wagon" if index == 0 else "sedan_classic"
		var car := MODERN_TRAFFIC.spawn_parked_vehicle(
			self,
			String(spec.name),
			spec.position,
			PI * 0.5,
			archetype_id,
			index + 3,
			spec.color
		)
		car.add_to_group("docks_parked_vehicle")

func _validate_authored_layout() -> void:
	var occupied: Array[Rect2] = []
	for car in get_children():
		if not car is DemoTrafficVehicle:
			continue
		var bounds := Rect2(car.position - CAR_SIZE_AFTER_ROTATION * 0.5, CAR_SIZE_AFTER_ROTATION)
		assert(PARKING_BOUNDS.encloses(bounds), "%s left the Docks parking surface" % car.name)
		assert(not bounds.intersects(ALLEY_BOUNDS), "%s blocks the Docks service alley" % car.name)
		for other in occupied:
			assert(not bounds.intersects(other), "%s overlaps another parked car" % car.name)
		occupied.append(bounds)
	assert(occupied.size() == 2, "Docks parking must expose exactly two parked cars")
	print("DOCKS_PARKING_VALID: 2 static cars, bays aligned, alley clear")

func validation_state() -> Dictionary:
	return {
		"parked_car_count": get_tree().get_nodes_in_group("docks_parked_vehicle").size(),
		"parking_bounds": PARKING_BOUNDS,
		"alley_clear": true,
		"moving": false
	}
