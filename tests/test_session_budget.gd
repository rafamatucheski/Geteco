extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.add_child(load("res://tests/diagnostics/SessionBudgetProbe.cs").new())
