extends SceneTree

class TransitProbe extends "res://world/harbor/urban_transit/UrbanTransit.gd":
	func _ready() -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var transit := TransitProbe.new()
	root.add_child(transit)
	var passenger := Node2D.new()
	root.add_child(passenger)
	transit.passengers.append(passenger)
	passenger.queue_free()
	await process_frame
	transit._prune_removed_passengers()
	var passed := transit.passengers.is_empty()
	print("URBAN_TRANSIT_REMOVED_PASSENGER ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
