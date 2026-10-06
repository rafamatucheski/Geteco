extends "res://tests/test_jessica_crossing_yield.gd"
## Same owner curve, signal and 15s physical deadline; only the explicit rear
## fixture uses the separately observed 114.16m position with available room.
func _initialize() -> void:
	rear_fixture_point = Vector3(114.1632,.12,79.83971)
	expect_clear = true
	super._initialize()
