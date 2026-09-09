extends SceneTree

const CONTRACT := preload("res://legacy/district/bairro1_v2/design/AlleyStealthContract.gd")

func _init() -> void:
	var contract = CONTRACT.new()
	assert(contract.PEDESTRIAN_ALLEYS.size() == 5, "District must define five pedestrian alleys")
	for alley in contract.PEDESTRIAN_ALLEYS:
		assert(not alley["vehicle_access"], "Alley must not allow vehicles: %s" % alley["id"])
		assert(int(alley["exits"]) >= 2, "Alley needs an escape path: %s" % alley["id"])
	assert(contract.LOS_BREAK_SECONDS > 0.0 and contract.SEARCH_DURATION_SECONDS > contract.LOS_BREAK_SECONDS, "Stealth timing must be valid")
	print("Alley stealth contract passed")
	quit(0)
