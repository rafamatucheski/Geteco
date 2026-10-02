extends "res://tests/dispatch/test_dispatch_lifecycle.gd"
## Completa só os grupos pertinentes ainda não executados; não aprova a suíte ampla.
func run()->void:
	await _suspension_of_people()
	await _controller_leaves_tree()
	report("GROUND_REMAINING_LIFECYCLE",["suspension_of_people","controller_leaves_tree"],12)
