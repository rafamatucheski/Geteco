extends SceneTree

const PLAN := preload("res://legacy/district/bairro1_v2/design/DistrictV2MasterPlan.gd")

func _init() -> void:
	var plan = PLAN.new()
	assert(plan.BUILDABLE_LOTS.size() == 10, "Master plan must define ten buildable lots")
	assert(plan.get_road_spines().size() == 10, "Master plan must define ten road spines")
	assert(plan.REQUIRED_MARKERS.size() == 10, "Master plan must preserve the marker contract")
	for lot in plan.BUILDABLE_LOTS:
		var rect: Rect2 = lot["rect"]
		assert(plan.DISTRICT_BOUNDS.encloses(rect), "Lot outside district bounds: %s" % lot["id"])
	for required_id in plan.INITIAL_ROUTE:
		assert(plan.REQUIRED_MARKERS.has(required_id), "Initial route marker missing: %s" % required_id)
	print("DistrictV2 master plan passed")
	quit(0)
