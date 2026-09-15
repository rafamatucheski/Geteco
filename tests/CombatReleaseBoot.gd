extends Node
## Entry point only for the exported performance-evidence package.
func _ready() -> void:
	var tree := get_tree()
	tree.set_script(load("res://tests/measure_city_scenarios.gd"))
	tree.call("_initialize")
	queue_free()
