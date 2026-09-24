extends Node3D
class_name StaticSawmillWorkTruck3D

## Static scenery counterpart of the work pickup mounted by V1
## MountainSceneryBuilder.build_detailed_sawmill(). It deliberately does not
## create a drivable Vehicle or run vehicle simulation.

const ARCHETYPE := "lumber_pickup_4x4"
const SOURCE_COLOR := Color("576574")

func _ready() -> void:
	var visual := preload("res://runtime/FleetCatalog.gd").create(ARCHETYPE)
	if visual == null:
		push_warning("StaticSawmillWorkTruck3D: authored lumber pickup scene is unavailable.")
		return
	visual.name = "AuthoredLumberPickup"
	add_child(visual)

	var paint := preload("res://runtime/VehiclePaint.gd").new()
	paint.bind(visual, ARCHETYPE)
	paint.apply(SOURCE_COLOR)

	var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(ARCHETYPE)
	var dimensions := Vector3(2.32, 1.76, 5.28)
	if specification.has("bounds_size"):
		var authored: Array = specification.bounds_size
		if authored.size() >= 3:
			dimensions = Vector3(float(authored[0]), float(authored[1]), float(authored[2]))

	var body := StaticBody3D.new()
	body.name = "WorkTruckSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	collision.position.y = dimensions.y * 0.5
	body.add_child(collision)
	add_child(body)

	set_meta("source_id", "world/mountain_pass/MountainSceneryBuilder.gd:build_detailed_sawmill/work_truck")
	set_meta("scenery_only", true)

