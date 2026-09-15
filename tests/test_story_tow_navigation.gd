extends SceneTree
## Isolated navigation contract; real transport is test_first_favors.gd.
class Controller extends Node2D:
	signal changed
	const WORKSHOP := Vector2(8000, 1700)
	var stage := 2
	var objective_position := Vector2.ZERO
class Truck extends Node2D:
	var is_driven_by_player := false
class Service extends Node:
	var truck: Node2D
class Yard extends Node2D:
	var dock := Vector2(20, 60)
	var npc: Node2D
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var c := Controller.new()
	root.add_child(c)
	var truck := Truck.new()
	root.add_child(truck)
	truck.position = Vector2(1400, 500)
	var service := Service.new()
	root.add_child(service)
	service.truck = truck
	var yard := Yard.new()
	root.add_child(yard)
	yard.position = Vector2(2800, 1200)
	var helper := preload("res://world/harbor/campaign/HarborStoryTow.gd").new()
	helper.configure(c)
	helper.service = service
	helper.yard = yard
	helper._update_destination()
	var return_ok: bool = c.objective_position == truck.global_position and helper.objective_text().contains("GPS")
	truck.is_driven_by_player = true
	helper._update_destination()
	var delivery_ok: bool = c.objective_position == yard.to_global(yard.dock)
	print("STORY_TOW_NAVIGATION return_to_abandoned_truck=", return_ok, " delivery_after_reboarding=", delivery_ok)
	quit(0 if return_ok and delivery_ok else 1)
