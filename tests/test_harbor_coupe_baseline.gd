extends "res://tests/test_harbor_interiors_gameplay.gd"

## Runs the identical regression with the original car, in memory only.
## child_entered_tree fires before this scene's children become ready.
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node):
		if node.name == "BreakwaterPreview":
			node.get_node("PlayerCar").set_script(load("res://characters/PlayerCar.gd"))
			print("COUPE_BASELINE original PlayerCar restored before ready")
	)
	call_deferred("_run_test")
