extends "res://world/mountain_pass/WinterResidentModel.gd"

var travel_metres := -1.0
var stride_phase := 0.0
const STRIDE = preload("res://world/harbor/cemetery/CemeteryStride.gd")

func _ready() -> void:
	super._ready()
	for knee in knees: STRIDE.ankle(knee, .34)
	var head := pose_root.get_node("Head")
	var parts = preload("res://world/shared/pedestrians/CitizenDetails.gd")
	for side in [-1, 1]:
		parts.piece(head, Vector3(.036,.018,.014), Vector3(side*.06,.01,-.155), Color("b6a08a"), true)
		parts.piece(head, Vector3(.014,.014,.01), Vector3(side*.06,.01,-.164), Color("292b2e"), true)

func _process(delta: float) -> void:
	super._process(delta)
	if walking and sit_amount <= 0:
		stride_phase = fposmod(stride_phase + (travel_metres if travel_metres >= 0 else motion_speed * delta / 13.0) * TAU / .8, TAU)
		for side in 2:
			limbs[side*2].position.y = .748
			STRIDE.pose(limbs[side*2], knees[side], stride_phase+side*PI, .35, .34, .0895, 1.0)
			limbs[side*2+1].rotation.x = cos(stride_phase+side*PI)*.25
	else:
		for side in 2:
			limbs[side*2].position.y = .78
			knees[side].get_node("StrideFoot").rotation.x = 0
	travel_metres = -1.0
