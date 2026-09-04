extends SceneTree

const PLAN := preload("res://district/bairro1_v2/design/DistrictV2RafaelPlan.gd")

func _init() -> void:
	var plan = PLAN.new()
	assert(plan.PLAN_VERSION == 3, "Rafael plan must be the current plan")
	assert(plan.ZONES.size() == 18, "Rafael plan must retain every named sector")
	assert(plan.get_road_spines().size() == 7, "Rafael plan must define the primary roads")
	assert(plan.get_scenic_rail_segments().size() == 3, "Rail must have tunnel and elevated segments")
	assert(plan.PEDESTRIAN_ALLEY_IDS.size() == 5, "Five pedestrian alleys are required")
	assert(plan.REQUIRED_MARKERS.has(&"PaintSprayEntrance"), "Paint & Spray entrance is required")
	assert(plan.REQUIRED_MARKERS.has(&"CemeteryIMLEntrance"), "Cemetery/IML entrance is required")
	print("DistrictV2 Rafael plan passed")
	quit(0)
