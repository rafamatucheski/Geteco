extends "res://tests/test_police_motorcycle_combat.gd"
func _run() -> void:
 paused = true
 await root.get_node("EmergencyPool").prepare_officers()
 paused = false
 await super._run()
