extends RefCounted
## Cabin dimensions authored alongside the exterior, independent of mirrors and
## door cuts. The shared seated-driver system still builds and animates the cabin.
static func spec(s: Dictionary) -> Dictionary:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var l := float(s["size"][2])
	var coupe := str(s.body)=="coupe"
	var sport := str(s.body) in ["coupe","muscle"]
	return {
		"kind":"sport" if sport else ("pickup" if s.body=="pickup" else "car"),
		"floor":float(s.wheel_radius)*.72+.025,
		"seat_floor":float(s.wheel_radius)*.72+.025,
		"belt":float(s.shoulder),
		"roof":h-(.085 if coupe else .115),
		"hw":w*.41,
		"wz0":l*float(s.cabin_front)+.035,
		"wz1":l*float(s.roof_front)+.035,
		"rear":l*float(s.cabin_back)-.045,
		"rear_top":l*float(s.roof_back)-.035,
		"rows":str(s.body) in ["hatch","sedan"],
		# Exterior roof already closes the cabin. A rectangular liner would cut
		# through its tapered shoulders and appear as a second, transparent roof.
		"roof_liner":false,
		"roof_rear":l*float(s.roof_back)-.035,
		"roof_trim_x":w*(.30 if coupe else .34),
		"roof_trim_y":h-(.13 if coupe else .16),
		"dash_front_inset":.055,
		"dash_min_depth":.10,
		"cluster_rise":.02,
		"cluster_depth":.12,
	}
